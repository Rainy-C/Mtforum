#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Cloud Push Build · Cloud Only
# Run inside an Android Gradle or Flutter project:
#   ./build.sh
#   ./build.sh debug
#   ./build.sh release
#
# Optional:
#   CLOUD_BUILD_CLEAN=1 ./build.sh release
#     -> after a successful build, remove remote project build outputs
#        (global Gradle / Pub / SDK / Flutter caches are still kept)
# ============================================================

SERVER_USER="root"
SERVER_HOST="159.195.21.203"
SERVER_PORT="22"
REMOTE_BASE="/opt/remote-build"
ANDROID_ABI="arm64-v8a"
FLUTTER_TARGET="android-arm64"

# Persistent dependency caches on the build server.
REMOTE_CACHE_BASE="${REMOTE_BASE}/.cache"
REMOTE_SIGN_BASE="${REMOTE_BASE}/.signing"

CLOUD_BUILD_CLEAN="${CLOUD_BUILD_CLEAN:-0}"

# ---------- terminal UI ----------
# Compact by default: only meaningful state transitions + live compiler output.
# Set CLOUD_BUILD_VERBOSE=1 when diagnosing environment/bootstrap details.
CLOUD_BUILD_VERBOSE="${CLOUD_BUILD_VERBOSE:-0}"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  BOLD='\033[1m'; DIM='\033[2m'; GREEN='\033[32m'; YELLOW='\033[33m'
  RED='\033[31m'; CYAN='\033[36m'; WHITE='\033[97m'; RESET='\033[0m'
else
  BOLD=''; DIM=''; GREEN=''; YELLOW=''; RED=''; CYAN=''; WHITE=''; RESET=''
fi

say()   { printf "%b\n" "$*"; }
info()  { say "${CYAN}›${RESET} $*"; }
ok()    { say "${GREEN}✓${RESET} $*"; }
warn()  { say "${YELLOW}!${RESET} $*"; }
verbose(){ [[ "$CLOUD_BUILD_VERBOSE" == "1" ]] && say "${DIM}  $*${RESET}" || true; }

# Keep the saved log complete, but trim known bootstrap/Gradle boilerplate from
# the live phone display. Error lines and task output always pass through.
filter_build_output() {
  awk '
    /For the best experience using Android CLI with agents/ { next }
    /running android init to install the necessary skills/ { next }
    /SDK Manager CLI tool \(sdkmanager\) is deprecated/ { next }
    /Android CLI will be used instead/ { next }
    /The .android. binary can also be found in the cmdline-tools directory/ { next }
    /replacement for .sdkmanager./ { next }
    /To learn more about the Android CLI and how to use it/ { next }
    /To honour the JVM settings for this build a single-use Daemon process will be forked/ { next }
    /For more on this, please refer to https:\/\/docs\.gradle\.org\/.*gradle_daemon/ { next }
    /Daemon will be stopped at the end of the build/ { next }
    { print; fflush() }
  '
}

CURRENT_PHASE="启动"
die() {
  local msg="$1" code="${2:-1}"
  say "" >&2
  say "${RED}${BOLD}✗ ${msg}${RESET}" >&2
  [[ -n "${LOG_FILE:-}" ]] && say "${DIM}  阶段 ${CURRENT_PHASE} · 日志 ${LOG_FILE}${RESET}" >&2
  exit "$code"
}

# Width follows the terminal, but stays compact on phones.
_term_cols=62
if command -v tput >/dev/null 2>&1; then
  _term_cols="$(tput cols 2>/dev/null || printf '62')"
fi
[[ "$_term_cols" =~ ^[0-9]+$ ]] || _term_cols=62
(( _term_cols < 48 )) && _term_cols=48
(( _term_cols > 68 )) && _term_cols=68
UI_WIDTH="$_term_cols"

# Do NOT use `tr ' ' '─'`: tr is byte-oriented on Termux and corrupts UTF-8.
line() {
  local i
  for ((i=0; i<UI_WIDTH; i++)); do printf '─'; done
  printf '\n'
}
section() {
  local title="$1"
  say ""
  say "${BOLD}${title}${RESET}"
  say "${DIM}$(line)${RESET}"
}
phase() {
  local n="$1" total="$2" text="$3"
  CURRENT_PHASE="$text"
  say "${DIM}[${n}/${total}]${RESET} ${BOLD}${text}${RESET}"
}
kv() {
  local k="$1" v="$2"
  printf "  ${DIM}%-10s${RESET} %s\n" "$k" "$v"
}

fmt_time() {
  local s="${1:-0}"
  if (( s < 60 )); then
    printf '%ss' "$s"
  elif (( s < 3600 )); then
    printf '%dm %02ds' "$((s/60))" "$((s%60))"
  else
    printf '%dh %02dm %02ds' "$((s/3600))" "$(((s%3600)/60))" "$((s%60))"
  fi
}

fmt_bytes() {
  local b="${1:-0}"
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec-i --suffix=B "$b" 2>/dev/null || printf '%s B' "$b"
  else
    awk -v b="$b" 'BEGIN{split("B KiB MiB GiB TiB",u); i=1; while(b>=1024 && i<5){b/=1024;i++} if(i==1) printf "%.0f %s",b,u[i]; else printf "%.1f %s",b,u[i]}'
  fi
}

short_hash() {
  local h="$1"
  [[ ${#h} -le 28 ]] && printf '%s' "$h" || printf '%s…%s' "${h:0:14}" "${h: -10}"
}

need_local() {
  command -v "$1" >/dev/null 2>&1 || die "本机缺少命令: $1" 10
}

# ---------- local project detection ----------
PROJECT_DIR="$(pwd -P)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
PROJECT_SAFE="$(printf '%s' "$PROJECT_NAME" | tr -cs 'A-Za-z0-9._-' '-' | sed 's/^-*//;s/-*$//')"
[[ -n "$PROJECT_SAFE" ]] || PROJECT_SAFE="project"

if [[ -f pubspec.yaml ]] && grep -Eq '(^|[[:space:]])flutter:' pubspec.yaml; then
  PROJECT_KIND="flutter"
elif [[ -f settings.gradle || -f settings.gradle.kts || -f build.gradle || -f build.gradle.kts || -f gradlew ]]; then
  PROJECT_KIND="gradle"
else
  die "当前目录不像 Flutter 或 Gradle Android 项目: $PROJECT_DIR" 11
fi

# Use package/application identity when possible, so moving the local folder does not
# unnecessarily create a new remote signing identity.
IDENTITY=""
if [[ "$PROJECT_KIND" == "flutter" ]]; then
  IDENTITY="$(sed -nE 's/^[[:space:]]*name:[[:space:]]*([^#[:space:]]+).*/\1/p' pubspec.yaml | head -n1 || true)"
fi
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(grep -RhsE 'applicationId' \
    --include='build.gradle' --include='build.gradle.kts' app android/app 2>/dev/null \
    | grep -Eo '"[^"[:space:]]+"' | head -n1 | tr -d '"' || true)"
fi
[[ -n "$IDENTITY" ]] || IDENTITY="$PROJECT_NAME@$PROJECT_DIR"

need_local ssh
need_local rsync
need_local sha256sum

PROJECT_ID="$(printf '%s' "$PROJECT_SAFE|$IDENTITY" | sha256sum | awk '{print substr($1,1,10)}')"
REMOTE_DIR="${REMOTE_BASE}/${PROJECT_SAFE}-${PROJECT_ID}"
REMOTE_OUT="${REMOTE_DIR}/.remote-build-out"
SSH_TARGET="${SERVER_USER}@${SERVER_HOST}"

SSH_OPTS=(
  -p "$SERVER_PORT"
  -o ServerAliveInterval=15
  -o ServerAliveCountMax=4
  -o TCPKeepAlive=yes
  -o StrictHostKeyChecking=accept-new
)
RSYNC_SSH="ssh -p ${SERVER_PORT} -o ServerAliveInterval=15 -o ServerAliveCountMax=4 -o TCPKeepAlive=yes -o StrictHostKeyChecking=accept-new"

# ---------- build mode ----------
MODE="${1:-}"
MODE="$(printf '%s' "$MODE" | tr '[:upper:]' '[:lower:]')"

if [[ -z "$MODE" ]]; then
  clear 2>/dev/null || true
  say "${GREEN}${BOLD}CLOUD BUILD${RESET}  ${DIM}/ remote compiler${RESET}"
  say "${DIM}$(line)${RESET}"
  say "  ${BOLD}1${RESET}  Debug     ${DIM}快速调试包${RESET}"
  say "  ${BOLD}2${RESET}  Release   ${DIM}正式构建 / 自动签名兜底${RESET}"
  say "${DIM}$(line)${RESET}"
  read -r -p "选择模式 [1/2] › " CHOICE
  case "$CHOICE" in
    1|d|D|debug|Debug) MODE="debug" ;;
    2|r|R|release|Release) MODE="release" ;;
    *) die "无效选择" 12 ;;
  esac
fi

case "$MODE" in
  debug|release) ;;
  *) die "用法: ./build.sh [debug|release]" 12 ;;
esac

START_ALL="$(date +%s)"
LOG_FILE="${PROJECT_DIR}/.cloud-build-last.log"
ARTIFACT_NAME="app-${MODE}.apk"
LOCAL_ARTIFACT="${PROJECT_DIR}/${ARTIFACT_NAME}"

clear 2>/dev/null || true
MODE_UPPER="$(printf '%s' "$MODE" | tr '[:lower:]' '[:upper:]')"
KIND_LABEL="$PROJECT_KIND"
[[ "$PROJECT_KIND" == "gradle" ]] && KIND_LABEL="Android · Gradle"
[[ "$PROJECT_KIND" == "flutter" ]] && KIND_LABEL="Flutter · Android"

say "${GREEN}${BOLD}CLOUD BUILD${RESET}  ${DIM}/ remote compiler${RESET}"
say "${DIM}$(line)${RESET}"
printf "${BOLD}%-32s${RESET} ${YELLOW}%s${RESET}\n" "$PROJECT_NAME" "$MODE_UPPER"
kv "工程" "$KIND_LABEL"
kv "目标" "$ANDROID_ABI"
kv "节点" "$SSH_TARGET"
verbose "远端目录  $REMOTE_DIR"
say "${DIM}$(line)${RESET}"

# ---------- connectivity ----------
phase 1 5 "连接云节点"
PHASE_START="$(date +%s)"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" 'printf ready' >/dev/null || die "SSH 连接失败" 13
ok "已连接 ${SSH_TARGET} · $(fmt_time "$(( $(date +%s)-PHASE_START ))")"

# ---------- bootstrap a fresh Debian/Ubuntu build server ----------
phase 2 5 "准备编译环境"
PHASE_START="$(date +%s)"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" bash -s -- \
  "$REMOTE_DIR" "$REMOTE_OUT" "$REMOTE_CACHE_BASE" "$REMOTE_SIGN_BASE" <<'BOOTSTRAP_REMOTE'
set -Eeuo pipefail

REMOTE_DIR="$1"
REMOTE_OUT="$2"
CACHE_BASE="$3"
SIGN_BASE="$4"
export DEBIAN_FRONTEND=noninteractive

rinfo() { printf '\033[36m›\033[0m %s\n' "$*"; }
rok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
rfail() { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit "${2:-1}"; }

# rsync must exist before the source can be uploaded, so fresh-server
# bootstrap happens before the first rsync call.
required=(
  curl unzip zip xz git python3 rsync openssl
  java keytool cmake ninja tar file make gcc g++ pkg-config
)
missing=()
for c in "${required[@]}"; do
  command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done

# Flutter's documented Linux prerequisites include libglu1-mesa. It is
# harmless for Android-only builds and avoids a second apt round-trip later.
need_libglu=0
if command -v dpkg >/dev/null 2>&1; then
  dpkg -s libglu1-mesa >/dev/null 2>&1 || need_libglu=1
fi

if ((${#missing[@]})) || ((need_libglu)); then
  [[ "$(id -u)" == "0" ]] || rfail "服务器是裸环境，但 SSH 用户不是 root，无法自动安装依赖" 20
  command -v apt-get >/dev/null 2>&1 || rfail "当前脚本的裸机自动初始化支持 Debian/Ubuntu（需要 apt-get）" 20

  rinfo "首次初始化 · 安装基础工具"
  APT_LOG="$(mktemp)"
  if ! apt-get update -qq >"$APT_LOG" 2>&1; then
    tail -n 30 "$APT_LOG" >&2
    rm -f "$APT_LOG"
    rfail "apt 索引更新失败" 20
  fi
  if ! apt-get install -y -qq --no-install-recommends \
    ca-certificates curl unzip zip xz-utils git python3 rsync openssl \
    openjdk-17-jdk-headless cmake ninja-build build-essential clang pkg-config \
    libglu1-mesa file tar gzip bzip2 >>"$APT_LOG" 2>&1; then
    tail -n 40 "$APT_LOG" >&2
    rm -f "$APT_LOG"
    rfail "基础工具安装失败" 20
  fi
  rm -f "$APT_LOG"
fi

mkdir -p \
  "$REMOTE_DIR" "$REMOTE_OUT" \
  "$CACHE_BASE/gradle" "$CACHE_BASE/pub" "$CACHE_BASE/gradle-dist" \
  "$SIGN_BASE" /opt/android-sdk

BOOTSTRAP_REMOTE

# ---------- prepare remote workspace ----------
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
  "mkdir -p '$REMOTE_DIR' '$REMOTE_OUT' '$REMOTE_CACHE_BASE/gradle' '$REMOTE_CACHE_BASE/pub' '$REMOTE_SIGN_BASE'" >/dev/null
ok "编译环境就绪 · $(fmt_time "$(( $(date +%s)-PHASE_START ))")"

# ---------- source sync ----------
phase 3 5 "同步源码"
SYNC_START="$(date +%s)"

RSYNC_ARGS=(
  -az
  --checksum
  --delete
  --stats
  --exclude='.git/'
  --exclude='.idea/'
  --exclude='.vscode/'
  --exclude='.gradle/'
  --exclude='.dart_tool/'
  --exclude='.flutter-plugins'
  --exclude='.flutter-plugins-dependencies'
  --exclude='.packages'
  --exclude='build/'
  --exclude='*/build/'
  --exclude='.remote-build-out/'
  --exclude='.cloud-build-last.log'
  --exclude='local.properties'
  --exclude='*.apk'
  --exclude='*.aab'
  --exclude='*.apks'
  -e "$RSYNC_SSH"
)

# If a Flutter source intentionally has no android/ platform folder, preserve the
# server-generated android/ scaffold instead of deleting it on every sync.
if [[ "$PROJECT_KIND" == "flutter" && ! -d android ]]; then
  RSYNC_ARGS+=(--exclude='/android/')
fi

RSYNC_LOG="$(mktemp)"
if ! LC_ALL=C rsync "${RSYNC_ARGS[@]}" ./ "${SSH_TARGET}:${REMOTE_DIR}/" >"$RSYNC_LOG" 2>&1; then
  tail -n 30 "$RSYNC_LOG" >&2
  rm -f "$RSYNC_LOG"
  die "源码同步失败" 14
fi
SYNC_END="$(date +%s)"
SYNC_BYTES="$(awk -F': ' '/^Total transferred file size:/ {gsub(/,/ ,"",$2); sub(/ bytes.*/,"",$2); print $2; exit}' "$RSYNC_LOG")"
SYNC_FILES="$(awk -F': ' '/^Number of regular files transferred:/ {gsub(/,/ ,"",$2); print $2; exit}' "$RSYNC_LOG")"
rm -f "$RSYNC_LOG"
SYNC_BYTES="${SYNC_BYTES:-0}"
SYNC_FILES="${SYNC_FILES:-0}"
ok "同步完成 · $(fmt_time "$((SYNC_END-SYNC_START))") · $(fmt_bytes "$SYNC_BYTES") · ${SYNC_FILES} files"

# ---------- remote build ----------
phase 4 5 "远端编译"
say "${DIM}  仅显示任务、警告与错误 · 完整日志仍保存${RESET}"
say "${DIM}$(line)${RESET}"
BUILD_START_LOCAL="$(date +%s)"

set +e
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" bash -s -- \
  "$REMOTE_DIR" "$PROJECT_KIND" "$MODE" "$PROJECT_ID" "$PROJECT_SAFE" \
  "$ANDROID_ABI" "$FLUTTER_TARGET" "$REMOTE_CACHE_BASE" "$REMOTE_SIGN_BASE" "$CLOUD_BUILD_CLEAN" \
  2>&1 <<'REMOTE_SCRIPT' | tee "$LOG_FILE" | filter_build_output
set -Eeuo pipefail

REMOTE_DIR="$1"
PROJECT_KIND="$2"
MODE="$3"
PROJECT_ID="$4"
PROJECT_SAFE="$5"
ANDROID_ABI="$6"
FLUTTER_TARGET="$7"
CACHE_BASE="$8"
SIGN_BASE="$9"
CLEAN_PROJECT="${10}"

export DEBIAN_FRONTEND=noninteractive
export GRADLE_USER_HOME="${CACHE_BASE}/gradle"
export PUB_CACHE="${CACHE_BASE}/pub"
export ANDROID_HOME="${ANDROID_HOME:-/opt/android-sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/platform-tools:$PATH"

# Human-readable status belongs on stderr. stdout is reserved for function
# return values (paths/versions), so command substitution cannot be polluted.
rinfo() { printf '\033[36m›\033[0m %s\n' "$*" >&2; }
rok()   { printf '\033[32m✓\033[0m %s\n' "$*" >&2; }
rwarn() { printf '\033[33m!\033[0m %s\n' "$*" >&2; }
rfail() { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit "${2:-1}"; }
rfmt_time() {
  local s="${1:-0}"
  if (( s < 60 )); then printf '%ss' "$s";
  elif (( s < 3600 )); then printf '%dm %02ds' "$((s/60))" "$((s%60))";
  else printf '%dh %02dm %02ds' "$((s/3600))" "$(((s%3600)/60))" "$((s%60))"; fi
}
rfmt_bytes() {
  local b="${1:-0}"
  if command -v numfmt >/dev/null 2>&1; then numfmt --to=iec-i --suffix=B "$b" 2>/dev/null || printf '%s B' "$b";
  else awk -v b="$b" 'BEGIN{split("B KiB MiB GiB",u);i=1;while(b>=1024&&i<4){b/=1024;i++}printf(i==1?"%.0f %s":"%.1f %s",b,u[i])}'; fi
}

cd "$REMOTE_DIR"
mkdir -p .remote-build-out "$GRADLE_USER_HOME" "$PUB_CACHE" "$SIGN_BASE"
rm -f .remote-build-out/*.apk .remote-build-out/*.aab 2>/dev/null || true

# ------------------------------------------------------------
# Base tools
# ------------------------------------------------------------
missing_base=0
for c in curl unzip zip xz git python3 rsync openssl; do
  command -v "$c" >/dev/null 2>&1 || missing_base=1
done
command -v java >/dev/null 2>&1 || missing_base=1
command -v keytool >/dev/null 2>&1 || missing_base=1

if (( missing_base )); then
  [[ "$(id -u)" == "0" ]] || rfail "服务器缺少基础环境，且当前 SSH 用户不是 root，无法自动补全" 20
  rinfo "补全基础编译环境"
  APT_LOG="$(mktemp)"
  if ! apt-get update -qq >"$APT_LOG" 2>&1 || ! apt-get install -y -qq --no-install-recommends \
    ca-certificates curl unzip zip xz-utils git python3 rsync openssl \
    openjdk-17-jdk-headless cmake ninja-build >>"$APT_LOG" 2>&1; then
    tail -n 30 "$APT_LOG" >&2
    rm -f "$APT_LOG"
    rfail "基础编译环境补全失败" 20
  fi
  rm -f "$APT_LOG"
fi

if [[ -z "${JAVA_HOME:-}" ]]; then
  JAVA_BIN="$(readlink -f "$(command -v java)")"
  export JAVA_HOME="${JAVA_BIN%/bin/java}"
fi

# ------------------------------------------------------------
# Android SDK / sdkmanager
# ------------------------------------------------------------
find_sdkmanager() {
  local p=""
  for p in \
    "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" \
    "$ANDROID_HOME/cmdline-tools/bin/sdkmanager" \
    "$ANDROID_HOME/tools/bin/sdkmanager"; do
    [[ -x "$p" ]] && { printf '%s\n' "$p"; return 0; }
  done
  find "$ANDROID_HOME/cmdline-tools" -type f -name sdkmanager -perm -u+x 2>/dev/null | head -n1
}

install_cmdline_tools() {
  [[ "$(id -u)" == "0" ]] || rfail "Android SDK 不完整，且无法自动安装 command-line tools" 21
  rinfo "Android command-line tools 缺失，自动补全"
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  local xml tmp url
  xml="$(mktemp)"
  tmp="$(mktemp -d)"
  curl -fsSL --retry 3 --connect-timeout 15 \
    https://dl.google.com/android/repository/repository2-1.xml -o "$xml"
  url="$(python3 - "$xml" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
items=[]
for rp in root.iter():
    if rp.tag.split('}')[-1] != 'remotePackage':
        continue
    path = rp.attrib.get('path','')
    if not path.startswith('cmdline-tools;'):
        continue
    channel = None
    revision = (0,0,0)
    linux_url = None
    for el in rp.iter():
        tag = el.tag.split('}')[-1]
        if tag == 'channelRef':
            channel = el.attrib.get('ref')
        elif tag == 'revision':
            vals = {}
            for x in el:
                try: vals[x.tag.split('}')[-1]] = int(x.text or 0)
                except: pass
            revision = (vals.get('major',0), vals.get('minor',0), vals.get('micro',0))
    for arch in rp.iter():
        if arch.tag.split('}')[-1] != 'archive':
            continue
        host=''
        u=''
        for el in arch.iter():
            tag=el.tag.split('}')[-1]
            if tag == 'host-os': host=(el.text or '').strip()
            if tag == 'url': u=(el.text or '').strip()
        if host == 'linux' and u:
            linux_url=u
            break
    if linux_url and (channel in (None, '', 'channel-0')):
        items.append((revision, linux_url))
if not items:
    raise SystemExit(2)
items.sort(reverse=True)
print(items[0][1])
PY
)" || rfail "无法解析 Android command-line tools 下载地址" 21
  curl -fsSL --retry 3 --connect-timeout 15 \
    "https://dl.google.com/android/repository/$url" -o "$tmp/cmdline-tools.zip"
  unzip -q "$tmp/cmdline-tools.zip" -d "$tmp/unpack"
  rm -rf "$ANDROID_HOME/cmdline-tools/latest"
  mkdir -p "$ANDROID_HOME/cmdline-tools/latest"
  if [[ -d "$tmp/unpack/cmdline-tools" ]]; then
    cp -a "$tmp/unpack/cmdline-tools/." "$ANDROID_HOME/cmdline-tools/latest/"
  else
    cp -a "$tmp/unpack/." "$ANDROID_HOME/cmdline-tools/latest/"
  fi
  rm -rf "$tmp" "$xml"
}

SDKMANAGER="$(find_sdkmanager || true)"
if [[ -z "$SDKMANAGER" ]]; then
  install_cmdline_tools
  SDKMANAGER="$(find_sdkmanager || true)"
fi
[[ -n "$SDKMANAGER" ]] || rfail "sdkmanager 不可用" 21

# Extract numeric SDK / NDK requirements from common Gradle layouts.
scan_files=()
for f in \
  android/app/build.gradle android/app/build.gradle.kts \
  app/build.gradle app/build.gradle.kts \
  build.gradle build.gradle.kts \
  gradle/libs.versions.toml android/gradle/libs.versions.toml; do
  [[ -f "$f" ]] && scan_files+=("$f")
done

COMPILE_SDK=""
BUILD_TOOLS=""
NDK_VERSION=""
if ((${#scan_files[@]})); then
  COMPILE_SDK="$(grep -hE 'compileSdk(Version)?[^0-9]{0,20}[0-9]{2,3}' "${scan_files[@]}" 2>/dev/null \
    | grep -oE '[0-9]{2,3}' | head -n1 || true)"
  BUILD_TOOLS="$(grep -hE 'buildToolsVersion[^0-9]{0,20}[0-9]+\.[0-9]+\.[0-9]+' "${scan_files[@]}" 2>/dev/null \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"
  NDK_VERSION="$(grep -hE 'ndkVersion[^0-9]{0,20}[0-9]+\.[0-9]+\.[0-9]+' "${scan_files[@]}" 2>/dev/null \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"
fi
[[ -n "$COMPILE_SDK" ]] || COMPILE_SDK="36"

rinfo "Android SDK · API $COMPILE_SDK"
yes | "$SDKMANAGER" --licenses >/dev/null 2>&1 || true
sdk_packages=("platform-tools" "platforms;android-${COMPILE_SDK}")
[[ -n "$BUILD_TOOLS" ]] && sdk_packages+=("build-tools;${BUILD_TOOLS}")
[[ -n "$NDK_VERSION" ]] && sdk_packages+=("ndk;${NDK_VERSION}")
SDK_LOG="$(mktemp)"
if ! "$SDKMANAGER" "${sdk_packages[@]}" >"$SDK_LOG" 2>&1; then
  tail -n 35 "$SDK_LOG" >&2
  rm -f "$SDK_LOG"
  rfail "Android SDK 组件安装失败 · API $COMPILE_SDK" 21
fi
rm -f "$SDK_LOG"

# Make build-tools available for signing. If none exists, install a modern one.
APKSIGNER="$(find "$ANDROID_HOME/build-tools" -type f -name apksigner 2>/dev/null | sort -V | tail -n1 || true)"
if [[ -z "$APKSIGNER" ]]; then
  SDK_LOG="$(mktemp)"
  if ! "$SDKMANAGER" "build-tools;36.0.0" >"$SDK_LOG" 2>&1; then
    tail -n 35 "$SDK_LOG" >&2
    rm -f "$SDK_LOG"
    rfail "Android Build Tools 安装失败" 21
  fi
  rm -f "$SDK_LOG"
  APKSIGNER="$(find "$ANDROID_HOME/build-tools" -type f -name apksigner 2>/dev/null | sort -V | tail -n1 || true)"
fi

# ------------------------------------------------------------
# Flutter bootstrap without git clone
# ------------------------------------------------------------
ensure_flutter() {
  if command -v flutter >/dev/null 2>&1; then
    return 0
  fi
  if [[ -x /opt/flutter/bin/flutter ]]; then
    export PATH="/opt/flutter/bin:$PATH"
    return 0
  fi
  [[ "$(id -u)" == "0" ]] || rfail "服务器没有 Flutter，且当前用户无法自动安装" 22

  rinfo "Flutter 缺失，下载 stable SDK"
  local meta archive base tmp
  meta="$(mktemp)"
  tmp="$(mktemp -d)"
  curl -fsSL --retry 3 --connect-timeout 15 \
    https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json -o "$meta"
  readarray -t FLUTTER_META < <(python3 - "$meta" <<'PY'
import json, sys
j=json.load(open(sys.argv[1], encoding='utf-8'))
h=j['current_release']['stable']
r=next(x for x in j['releases'] if x['hash']==h)
print(j['base_url'])
print(r['archive'])
PY
)
  base="${FLUTTER_META[0]}"
  archive="${FLUTTER_META[1]}"
  curl -fsSL --retry 3 --connect-timeout 15 "$base/$archive" -o "$tmp/flutter.tar.xz"
  rm -rf /opt/flutter
  tar -xf "$tmp/flutter.tar.xz" -C /opt
  rm -rf "$tmp" "$meta"
  export PATH="/opt/flutter/bin:$PATH"
  git config --global --add safe.directory /opt/flutter >/dev/null 2>&1 || true
  flutter config --no-analytics >/dev/null 2>&1 || true
}

# ------------------------------------------------------------
# Gradle resolver
# ------------------------------------------------------------
download_gradle() {
  local version="$1"
  local url="${2:-https://services.gradle.org/distributions/gradle-${version}-bin.zip}"
  local root="${CACHE_BASE}/gradle-dist/gradle-${version}"
  local zipfile="${CACHE_BASE}/gradle-dist/gradle-${version}-bin.zip"
  mkdir -p "${CACHE_BASE}/gradle-dist"
  if [[ ! -x "$root/bin/gradle" ]]; then
    rinfo "补全 Gradle $version"
    rm -rf "$root"
    curl -fsSL --retry 3 --connect-timeout 15 "$url" -o "$zipfile"
    unzip -q -o "$zipfile" -d "${CACHE_BASE}/gradle-dist"
  fi
  [[ -x "$root/bin/gradle" ]] || rfail "Gradle $version 安装失败" 23
  printf '%s\n' "$root/bin/gradle"
}

infer_agp_version() {
  local v=""
  local files=()
  for f in \
    build.gradle build.gradle.kts settings.gradle settings.gradle.kts \
    android/build.gradle android/build.gradle.kts android/settings.gradle android/settings.gradle.kts \
    gradle/libs.versions.toml android/gradle/libs.versions.toml; do
    [[ -f "$f" ]] && files+=("$f")
  done
  ((${#files[@]})) || return 0
  v="$(grep -hEo 'com\.android\.tools\.build:gradle:[0-9]+\.[0-9]+(\.[0-9]+)?' "${files[@]}" 2>/dev/null \
      | head -n1 | sed 's/.*://' || true)"
  if [[ -z "$v" ]]; then
    v="$(grep -hE 'com\.android\.(application|library).*version|agp[[:space:]]*=' "${files[@]}" 2>/dev/null \
      | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || true)"
  fi
  printf '%s\n' "$v"
}

infer_gradle_for_agp() {
  local agp="$1"
  local major minor
  major="${agp%%.*}"
  minor="${agp#*.}"; minor="${minor%%.*}"
  if [[ "$major" -ge 10 ]]; then printf '9.1.0\n'; return; fi
  if [[ "$major" -eq 9 ]]; then printf '9.1.0\n'; return; fi
  if [[ "$major" -eq 8 ]]; then
    case "$minor" in
      0|1) printf '8.0.2\n' ;;
      2)   printf '8.2.1\n' ;;
      3)   printf '8.4\n' ;;
      4)   printf '8.6\n' ;;
      5|6) printf '8.7\n' ;;
      7)   printf '8.9\n' ;;
      8)   printf '8.10.2\n' ;;
      9|10) printf '8.11.1\n' ;;
      11|12|13|*) printf '8.13\n' ;;
    esac
    return
  fi
  printf '8.13\n'
}

resolve_gradle() {
  local prop url version agp
  if [[ -f gradlew && -f gradle/wrapper/gradle-wrapper.jar ]]; then
    chmod +x gradlew
    printf './gradlew\n'
    return
  fi
  if [[ -f android/gradlew && -f android/gradle/wrapper/gradle-wrapper.jar ]]; then
    chmod +x android/gradlew
    printf './android/gradlew\n'
    return
  fi

  prop=""
  [[ -f gradle/wrapper/gradle-wrapper.properties ]] && prop="gradle/wrapper/gradle-wrapper.properties"
  [[ -z "$prop" && -f android/gradle/wrapper/gradle-wrapper.properties ]] && prop="android/gradle/wrapper/gradle-wrapper.properties"
  if [[ -n "$prop" ]]; then
    url="$(sed -nE 's/^distributionUrl=(.*)$/\1/p' "$prop" | tail -n1 | sed 's/\\:/:/g')"
    version="$(printf '%s' "$url" | grep -oE 'gradle-[0-9]+(\.[0-9]+){1,2}' | head -n1 | sed 's/gradle-//' || true)"
    if [[ -n "$version" && -n "$url" ]]; then
      download_gradle "$version" "$url"
      return
    fi
  fi

  if command -v gradle >/dev/null 2>&1; then
    command -v gradle
    return
  fi

  agp="$(infer_agp_version)"
  [[ -n "$agp" ]] || rfail "项目没有可用 Gradle Wrapper，且无法从源码推断 AGP 版本" 23
  version="$(infer_gradle_for_agp "$agp")"
  rwarn "项目缺少完整 Gradle Wrapper；根据 AGP $agp 选择 Gradle $version"
  download_gradle "$version"
}

# ------------------------------------------------------------
# Project preparation
# ------------------------------------------------------------
if [[ "$PROJECT_KIND" == "flutter" ]]; then
  ensure_flutter
  rinfo "Flutter: $(flutter --version 2>/dev/null | head -n1)"

  if [[ ! -d android ]]; then
    rinfo "源码没有 android/，仅在远端补全 Android scaffold"
    flutter create --platforms=android . >/dev/null
  fi

  cat > android/local.properties <<EOF
sdk.dir=$ANDROID_HOME
flutter.sdk=$(dirname "$(dirname "$(command -v flutter)")")
EOF

  rinfo "Flutter 依赖"
  PUB_LOG="$(mktemp)"
  if ! flutter pub get >"$PUB_LOG" 2>&1; then
    cat "$PUB_LOG" >&2
    rm -f "$PUB_LOG"
    rfail "Flutter/Dart 依赖解析失败" 24
  fi
  rm -f "$PUB_LOG"
else
  # Standard Android Gradle project.
  if [[ -d android && ! -f local.properties && ( -f android/settings.gradle || -f android/settings.gradle.kts ) ]]; then
    printf 'sdk.dir=%s\n' "$ANDROID_HOME" > android/local.properties
  else
    printf 'sdk.dir=%s\n' "$ANDROID_HOME" > local.properties
  fi
fi

# ------------------------------------------------------------
# Build without deleting previous Gradle outputs.
#
# Important: an UP-TO-DATE assemble is a valid successful build. Gradle owns
# incremental invalidation, and rsync --checksum --delete already guarantees
# that the remote source tree matches the local source tree. Deleting APKs
# before invoking Gradle can break that contract: AGP may keep its canonical
# package in an internal artifact directory and consider packageDebug current.
# ------------------------------------------------------------
rinfo "增量构建 · 保留有效缓存"
BUILD_BEGIN="$(date +%s)"

if [[ "$PROJECT_KIND" == "flutter" ]]; then
  if [[ "$MODE" == "debug" ]]; then
    flutter build apk --debug --target-platform="$FLUTTER_TARGET"
  else
    flutter build apk --release --target-platform="$FLUTTER_TARGET"
  fi
else
  GRADLE_CMD="$(resolve_gradle)"
  if [[ "$GRADLE_CMD" =~ gradle-([0-9]+(\.[0-9]+){1,2})/bin/gradle ]]; then
    rinfo "Gradle · ${BASH_REMATCH[1]}"
  else
    rinfo "Gradle · Wrapper"
  fi

  # If the Gradle binary came from android/, execute from that project root.
  if [[ "$GRADLE_CMD" == "./android/gradlew" ]]; then
    pushd android >/dev/null
    GRADLE_CMD="./gradlew"
    [[ "$MODE" == "debug" ]] && TASK="assembleDebug" || TASK="assembleRelease"
    "$GRADLE_CMD" "$TASK" --console=plain --no-daemon \
      -Pandroid.injected.build.abi="$ANDROID_ABI"
    popd >/dev/null
  else
    [[ "$MODE" == "debug" ]] && TASK="assembleDebug" || TASK="assembleRelease"
    "$GRADLE_CMD" "$TASK" --console=plain --no-daemon \
      -Pandroid.injected.build.abi="$ANDROID_ABI"
  fi
fi

BUILD_END="$(date +%s)"

# ------------------------------------------------------------
# Resolve the APK using the build system's own artifact metadata.
#
# Priority:
#   1. Flutter documented output
#   2. Android */build/outputs/apk/**
#   3. AGP create*ApkListingFileRedirect/redirect.txt -> output-metadata.json
#
# Modern AGP can expose the assemble result through an IDE redirect file whose
# listing points at build/intermediates/apk/.../output-metadata.json. That is
# materially different from blindly scanning every file under intermediates:
# we only accept an APK that AGP itself names in its artifact listing.
# ------------------------------------------------------------
APK="$(python3 - "$PROJECT_KIND" "$MODE" "$ANDROID_ABI" <<'PY_APK'
import json
import os
import sys
from pathlib import Path

kind, mode, abi = sys.argv[1:4]
root = Path('.').resolve()
mode_l = mode.lower()
abi_l = abi.lower()

# (score, path, reason)
candidates = []
seen = set()

def add(path, score, reason):
    try:
        p = Path(path).resolve()
    except Exception:
        return
    if not p.is_file() or p.suffix.lower() != '.apk':
        return
    ps = str(p)
    if '/.remote-build-out/' in ps.replace('\\', '/'):
        return
    key = os.path.realpath(ps)
    if key in seen:
        return
    seen.add(key)
    name = p.name.lower()
    low = ps.lower().replace('\\', '/')
    if name == f'app-{mode_l}.apk':
        score += 120
    if mode_l in name:
        score += 50
    if f'/{mode_l}/' in low:
        score += 40
    if abi_l in name or abi_l.replace('-', '_') in name or 'arm64' in name and abi_l == 'arm64-v8a':
        score += 25
    if 'universal' in name:
        score += 15
    if 'androidtest' in low or '-test' in name:
        score -= 500
    candidates.append((score, p, reason))

def metadata_apks(meta_path, base_score, reason):
    try:
        meta_path = Path(meta_path).resolve()
        data = json.loads(meta_path.read_text(errors='replace'))
    except Exception:
        return
    variant = str(data.get('variantName', '')).lower()
    if variant and not variant.endswith(mode_l):
        return
    for e in data.get('elements') or []:
        out = e.get('outputFile')
        if not out:
            continue
        score = base_score
        filters = e.get('filters') or []
        if not filters:
            score += 35
        for f in filters:
            val = str(f.get('value', '')).lower()
            if val == abi_l:
                score += 45
        add(meta_path.parent / out, score, reason)

# Flutter has a stable documented handoff path.
if kind == 'flutter':
    add(root / 'build' / 'app' / 'outputs' / 'flutter-apk' / f'app-{mode_l}.apk', 1500, 'flutter-output')

# Official/public Android output convention.
for p in root.glob('**/build/outputs/apk/**/*.apk'):
    add(p, 1300, 'outputs-apk')
for m in root.glob('**/build/outputs/apk/**/output-metadata.json'):
    metadata_apks(m, 1320, 'outputs-metadata')

# AGP's own assemble artifact redirect. We do not blindly trust intermediates;
# the redirect must point to a metadata file, and that metadata must name APK.
for redirect in root.glob('**/build/intermediates/apk_ide_redirect_file/**/redirect.txt'):
    try:
        listing = None
        for line in redirect.read_text(errors='replace').splitlines():
            if line.startswith('listingFile='):
                listing = line.split('=', 1)[1].strip()
                break
        if not listing:
            continue
        mp = Path(listing)
        if not mp.is_absolute():
            mp = (redirect.parent / mp).resolve()
        metadata_apks(mp, 1200, 'agp-redirect')
    except Exception:
        pass

if not candidates:
    sys.exit(3)

candidates.sort(key=lambda x: (x[0], x[1].stat().st_size, x[1].stat().st_mtime_ns), reverse=True)
score, chosen, reason = candidates[0]
print(os.path.relpath(chosen, root))
PY_APK
)" || {
  printf '\nGradle/Flutter 构建成功，但未能从正式输出或 AGP artifact redirect 解析 APK。\n' >&2
  printf '诊断：outputs / redirect / metadata 文件：\n' >&2
  find -L . -type f \( -path '*/build/outputs/apk/*' -o -path '*/build/intermediates/apk_ide_redirect_file/*/redirect.txt' -o -path '*/build/intermediates/apk/*/output-metadata.json' \) \
    -print 2>/dev/null | sed 's#^#  #' >&2 || true
  rfail "构建成功，但找不到 Gradle/Flutter 声明的 APK 产物" 30
}

[[ -n "$APK" && -f "$APK" ]] || rfail "解析到了 APK 路径，但文件不存在: $APK" 31
rinfo "产物 · ${APK##*/}"

# Validate the selected file as a real installable APK container. apksigner is
# authoritative for the Android package signature format; for release without
# project signing, validation happens after the fallback signer below.
if [[ "$MODE" == "debug" && -n "${APKSIGNER:-}" && -x "$APKSIGNER" ]]; then
  "$APKSIGNER" verify --verbose "$APK" >/dev/null || rfail "APK 签名校验失败: $APK" 31
fi

# ------------------------------------------------------------
# Release signing fallback.
# If the project has no obvious custom keystore configuration, create a
# persistent per-project random key once and re-sign the release APK.
# ------------------------------------------------------------
SIGNING_MODE="项目签名"
if [[ "$MODE" == "release" ]]; then
  CUSTOM_SIGNING=0
  signing_files=()
  for f in \
    android/app/build.gradle android/app/build.gradle.kts android/key.properties \
    app/build.gradle app/build.gradle.kts key.properties; do
    [[ -f "$f" ]] && signing_files+=("$f")
  done
  if ((${#signing_files[@]})) && grep -qE 'storeFile|storePassword|keyPassword|keystoreProperties|RELEASE_STORE_FILE' "${signing_files[@]}" 2>/dev/null; then
    CUSTOM_SIGNING=1
  fi

  if (( ! CUSTOM_SIGNING )); then
    [[ -n "$APKSIGNER" && -x "$APKSIGNER" ]] || rfail "Release 需要自动签名，但 apksigner 不可用" 32
    KEY_DIR="${SIGN_BASE}/${PROJECT_ID}"
    KEYSTORE="${KEY_DIR}/release.jks"
    CREDS="${KEY_DIR}/credentials"
    mkdir -p "$KEY_DIR"
    chmod 700 "$KEY_DIR"

    if [[ ! -f "$KEYSTORE" || ! -f "$CREDS" ]]; then
      rinfo "未检测到项目签名配置，首次生成随机 Release 签名"
      PASS="$(openssl rand -hex 24)"
      umask 077
      printf '%s\n' "$PASS" > "$CREDS"
      keytool -genkeypair -v \
        -keystore "$KEYSTORE" \
        -storepass "$PASS" \
        -keypass "$PASS" \
        -alias cloudbuild \
        -keyalg RSA -keysize 3072 -validity 36500 \
        -dname "CN=Cloud Build, OU=Android, O=Local Build, C=US" >/dev/null 2>&1
      chmod 600 "$KEYSTORE" "$CREDS"
    else
      PASS="$(cat "$CREDS")"
    fi

    SIGNED_TMP="${APK%.apk}.cloudsigned.apk"
    rm -f "$SIGNED_TMP"
    "$APKSIGNER" sign \
      --ks "$KEYSTORE" \
      --ks-key-alias cloudbuild \
      --ks-pass "pass:$PASS" \
      --key-pass "pass:$PASS" \
      --out "$SIGNED_TMP" \
      "$APK"
    "$APKSIGNER" verify --verbose "$SIGNED_TMP" >/dev/null
    mv -f "$SIGNED_TMP" "$APK"
    SIGNING_MODE="自动签名 · 持久密钥"
  fi
fi

cp -f "$APK" ".remote-build-out/app-${MODE}.apk"
SIZE_BYTES="$(stat -c %s ".remote-build-out/app-${MODE}.apk")"
SHA256="$(sha256sum ".remote-build-out/app-${MODE}.apk" | awk '{print $1}')"

cat > .remote-build-out/build-info.txt <<EOF
project=$PROJECT_SAFE
kind=$PROJECT_KIND
mode=$MODE
abi=$ANDROID_ABI
artifact=app-${MODE}.apk
bytes=$SIZE_BYTES
sha256=$SHA256
signing=$SIGNING_MODE
build_seconds=$((BUILD_END-BUILD_BEGIN))
EOF

printf '\n'
rok "编译完成 · $(rfmt_time "$((BUILD_END-BUILD_BEGIN))") · $(rfmt_bytes "$SIZE_BYTES")"
[[ "$SIGNING_MODE" != "项目签名" ]] && rinfo "签名 · $SIGNING_MODE"

# Optional project-output cleanup. Never delete global dependency caches,
# SDKs, Flutter SDK, or the persistent signing key.
if [[ "$CLEAN_PROJECT" == "1" ]]; then
  rinfo "清理远端项目生成目录（保留全局依赖缓存与签名）"
  find . -type d -name build -prune -exec rm -rf {} + 2>/dev/null || true
  rm -rf .dart_tool 2>/dev/null || true
fi
REMOTE_SCRIPT

REMOTE_RC=${PIPESTATUS[0]}
set -e
BUILD_END_LOCAL="$(date +%s)"

say "${DIM}$(line)${RESET}"
if (( REMOTE_RC != 0 )); then
  die "远端构建失败" "$REMOTE_RC"
fi

# ---------- pull artifact ----------
phase 5 5 "拉取产物"
PULL_START="$(date +%s)"
rm -f "$LOCAL_ARTIFACT"
PULL_TMP="$(mktemp -d)"
if ! rsync -az -e "$RSYNC_SSH" \
  --include="$ARTIFACT_NAME" --include='build-info.txt' --exclude='*' \
  "${SSH_TARGET}:${REMOTE_OUT}/" "$PULL_TMP/" >/dev/null 2>&1; then
  rm -rf "$PULL_TMP"
  die "APK 拉取失败" 40
fi
[[ -s "$PULL_TMP/$ARTIFACT_NAME" ]] || { rm -rf "$PULL_TMP"; die "APK 拉取失败或文件为空" 40; }
mv -f "$PULL_TMP/$ARTIFACT_NAME" "$LOCAL_ARTIFACT"

REMOTE_BUILD_SECONDS=""
SIGNING_MODE_LOCAL=""
if [[ -f "$PULL_TMP/build-info.txt" ]]; then
  REMOTE_BUILD_SECONDS="$(sed -n 's/^build_seconds=//p' "$PULL_TMP/build-info.txt" | tail -1)"
  SIGNING_MODE_LOCAL="$(sed -n 's/^signing=//p' "$PULL_TMP/build-info.txt" | tail -1)"
fi
rm -rf "$PULL_TMP"

LOCAL_SHA="$(sha256sum "$LOCAL_ARTIFACT" | awk '{print $1}')"
LOCAL_SIZE="$(stat -c %s "$LOCAL_ARTIFACT" 2>/dev/null || wc -c < "$LOCAL_ARTIFACT")"
PULL_END="$(date +%s)"
ok "已保存 ${ARTIFACT_NAME} · $(fmt_bytes "$LOCAL_SIZE") · $(fmt_time "$((PULL_END-PULL_START))")"

# Remove only the handoff copy. The remote source workspace remains for fast,
# correctly-invalidated incremental builds next time.
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
  "rm -f '$REMOTE_OUT/$ARTIFACT_NAME' '$REMOTE_OUT/build-info.txt'" >/dev/null 2>&1 || true

END_ALL="$(date +%s)"
TASK_STAT="$(grep -E '[0-9]+ actionable tasks:' "$LOG_FILE" 2>/dev/null | tail -1 || true)"

section "${GREEN}✓ BUILD COMPLETE${RESET}"
kv "APK" "$ARTIFACT_NAME"
kv "大小" "$(fmt_bytes "$LOCAL_SIZE")"
kv "SHA-256" "$(short_hash "$LOCAL_SHA")"
[[ -n "$SIGNING_MODE_LOCAL" ]] && kv "签名" "$SIGNING_MODE_LOCAL"
[[ -n "$REMOTE_BUILD_SECONDS" ]] && kv "编译" "$(fmt_time "$REMOTE_BUILD_SECONDS")"
kv "同步" "$(fmt_time "$((SYNC_END-SYNC_START))")"
kv "总耗时" "$(fmt_time "$((END_ALL-START_ALL))")"
[[ -n "$TASK_STAT" ]] && kv "任务" "$TASK_STAT"
kv "日志" "$(basename "$LOG_FILE")"
verbose "APK 路径    $LOCAL_ARTIFACT"
verbose "完整 SHA    $LOCAL_SHA"
say "${DIM}$(line)${RESET}"

if [[ "$CLOUD_BUILD_CLEAN" != "1" ]]; then
  say "${DIM}提示：默认保留远端增量编译缓存。需要彻底清项目生成目录时：CLOUD_BUILD_CLEAN=1 ./build.sh $MODE${RESET}"
fi
