#!/usr/bin/env bash
set -Eeuo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-/root/mtforum}"

[[ -d "$TARGET" ]] || { echo "Target not found: $TARGET" >&2; exit 2; }

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$TARGET/.refactor-backup-$STAMP"
mkdir -p "$BACKUP"

for path in lib pubspec.yaml android/app/src/main REFACTOR_NOTES.md docs; do
  if [[ -e "$TARGET/$path" ]]; then
    mkdir -p "$BACKUP/$(dirname "$path")"
    cp -a "$TARGET/$path" "$BACKUP/$path"
  fi
done

rm -rf "$TARGET/lib"
cp -a "$SRC_DIR/lib" "$TARGET/lib"
cp -f "$SRC_DIR/pubspec.yaml" "$TARGET/pubspec.yaml"
cp -f "$SRC_DIR/android/app/src/main/AndroidManifest.xml" \
  "$TARGET/android/app/src/main/AndroidManifest.xml"
mkdir -p "$TARGET/android/app/src/main/kotlin/com/binmt/mtforum"
cp -f "$SRC_DIR/android/app/src/main/kotlin/com/binmt/mtforum/MainActivity.kt" \
  "$TARGET/android/app/src/main/kotlin/com/binmt/mtforum/MainActivity.kt"
cp -f "$SRC_DIR/REFACTOR_NOTES.md" "$TARGET/REFACTOR_NOTES.md"
mkdir -p "$TARGET/docs"
cp -f "$SRC_DIR/docs/MT请求响应参考.md" "$TARGET/docs/MT请求响应参考.md"
mkdir -p "$TARGET/test"
cp -f "$SRC_DIR/test/forum_parser_test.dart" "$TARGET/test/forum_parser_test.dart"

# 自动保证发布脚本把同一 PUBLIC_BASE 注入 App 更新地址。
PUBLISH="$TARGET/scripts/publish-release.sh"
if [[ -f "$PUBLISH" ]] && ! grep -q 'MTFORUM_UPDATE_URL' "$PUBLISH"; then
  python3 - "$PUBLISH" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text(encoding='utf-8')
needle = '    --build-number="$VERSION_CODE"'
if needle in s:
    s = s.replace(
        needle,
        needle + ' \\\n    --dart-define=MTFORUM_UPDATE_URL="$PUBLIC_BASE/Mt/update.json"',
        1,
    )
    p.write_text(s, encoding='utf-8')
    print('✓ 发布脚本已注入 MTFORUM_UPDATE_URL')
else:
    print('! 未自动修改发布脚本：没找到 build-number 行')
PY
fi

echo
echo "===== MTForum Refactor Applied ====="
grep '^version:' "$TARGET/pubspec.yaml"
echo "Parser : $(grep -c 'class ForumParser' "$TARGET/lib/data/forum_parser.dart")"
echo "Theme  : $(grep -c '深色模式' "$TARGET/lib/pages/settings_page.dart")"
echo "Update : $(grep -c 'startDownload' "$TARGET/lib/services/update_service.dart")"
echo "Backup : $BACKUP"
