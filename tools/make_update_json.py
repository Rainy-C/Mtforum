#!/usr/bin/env python3
"""由 pubspec.yaml + CHANGELOG.md + 已构建的 APK 生成 update.json。

用法:
    python3 tools/make_update_json.py                     # 用默认 APK 路径
    python3 tools/make_update_json.py path/to/app.apk
    python3 tools/make_update_json.py path/to/app.apk -o update.json

默认 APK 路径: build/app/outputs/flutter-apk/app-release.apk
默认下载地址: https://loveqin.fun/Mt/MTForum-{version}-Release.apk

它会做两件"防止发错包"的校验 —— 这两件事都是手工发版时最容易出错的:

1. APK 里的 versionName 必须等于 pubspec.yaml 的版本号。
   否则用户装完仍是旧版本号, App 每次启动都会再次提示更新, 陷入死循环。
2. APK 不能是 debug 签名。
   本地 / CI 构建在没有正式 keystore 时会回落到 debug 签名
   (见 android/app/build.gradle.kts), 这种包无法覆盖安装正式版本。

两项校验失败时脚本会输出醒目警告并返回非 0 退出码, 但仍然打印 JSON
(方便先看内容); 正式发布请确保 APK 通过校验。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import struct
import sys
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_APK = REPO_ROOT / "build/app/outputs/flutter-apk/app-release.apk"
DOWNLOAD_URL_TEMPLATE = "https://loveqin.fun/Mt/MTForum-{version}-Release.apk"
SIGNATURE_SCAN_BYTES = 262144


def read_pubspec_version(repo_root: Path):
    """读取 `version: x.y.z+code`, 返回 (version, versionCode)。"""
    text = (repo_root / "pubspec.yaml").read_text(encoding="utf-8")
    match = re.search(r"^version:\s*(\S+)\s*$", text, re.M)
    if not match:
        raise SystemExit("pubspec.yaml 里找不到 version 字段")
    raw = match.group(1)
    if "+" in raw:
        name, _, code = raw.partition("+")
    else:
        name, code = raw, "0"
    return name.strip(), int(code.strip() or 0)


def read_changelog(repo_root: Path, version: str) -> str:
    """取 CHANGELOG.md 中 `## v{version}` 一节, 逐行作为更新条目。"""
    path = repo_root / "CHANGELOG.md"
    if not path.exists():
        raise SystemExit("找不到 CHANGELOG.md")

    collecting = False
    items = []
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if stripped.startswith("##"):
            if collecting:
                break
            collecting = stripped.lstrip("# ").strip() in (f"v{version}", version)
            continue
        if collecting and stripped:
            items.append(re.sub(r"^[-*\u2022]\s*", "", stripped))

    if not items:
        raise SystemExit(f"CHANGELOG.md 里没有 v{version} 这一节的更新条目")
    return "\n".join(items)


def _read_axml_strings(axml: bytes):
    """从二进制 AndroidManifest.xml 的字符串池里取出全部字符串。"""
    if len(axml) < 12 or struct.unpack_from("<I", axml, 0)[0] != 0x00080003:
        return []

    offset = 8
    while offset + 8 <= len(axml):
        chunk_type, chunk_size, _ = struct.unpack_from("<HHI", axml, offset)
        if chunk_size <= 0:
            break
        if chunk_type == 0x0001:  # RES_STRING_POOL_TYPE
            count, _styles, flags, strings_start, _ss = struct.unpack_from(
                "<IIIII", axml, offset + 8
            )
            is_utf8 = bool(flags & (1 << 8))
            offsets = struct.unpack_from("<%dI" % count, axml, offset + 28)
            base = offset + strings_start
            out = []
            for item in offsets:
                pos = base + item
                if is_utf8:
                    ln = axml[pos]
                    pos += 1
                    if ln & 0x80:
                        ln = ((ln & 0x7F) << 8) | axml[pos]
                        pos += 1
                    ln2 = axml[pos]
                    pos += 1
                    if ln2 & 0x80:
                        ln2 = ((ln2 & 0x7F) << 8) | axml[pos]
                        pos += 1
                    out.append(axml[pos:pos + ln2].decode("utf-8", "replace"))
                else:
                    length = struct.unpack_from("<H", axml, pos)[0]
                    pos += 2
                    if length & 0x8000:
                        length = ((length & 0x7FFF) << 16) | struct.unpack_from(
                            "<H", axml, pos
                        )[0]
                        pos += 2
                    out.append(
                        axml[pos:pos + length * 2].decode("utf-16-le", "replace")
                    )
            return out
        offset += chunk_size
    return []


def inspect_apk(apk: Path, version: str):
    """返回 (警告列表, 是否 debug 签名)。"""
    warnings = []

    with zipfile.ZipFile(apk) as archive:
        manifest = archive.read("AndroidManifest.xml")

    strings = set(_read_axml_strings(manifest))
    if version not in strings:
        found = sorted(
            s for s in strings if re.fullmatch(r"\d+\.\d+(?:\.\d+){0,2}", s)
        )
        warnings.append(
            "APK 内的 versionName 不是 %s（实际找到: %s）。"
            "用户装完仍会显示旧版本号，App 会反复提示更新。"
            % (version, ", ".join(found) or "未识别")
        )

    tail = apk.read_bytes()[-SIGNATURE_SCAN_BYTES:]
    is_debug = b"Android Debug" in tail
    if is_debug:
        warnings.append(
            "APK 使用了 debug 签名（CN=Android Debug）。"
            "这种包无法覆盖安装正式签名的版本，也不能用于正式发布。"
        )

    return warnings, is_debug


def main() -> int:
    parser = argparse.ArgumentParser(description="生成 MT论坛 update.json")
    parser.add_argument(
        "apk",
        nargs="?",
        default=str(DEFAULT_APK),
        help="APK 路径（默认 build/app/outputs/flutter-apk/app-release.apk）",
    )
    parser.add_argument(
        "-o", "--output", default="-", help="输出文件；默认打印到标准输出"
    )
    parser.add_argument("--url", default=None, help="覆盖下载地址")
    args = parser.parse_args()

    apk = Path(args.apk)
    if not apk.exists():
        raise SystemExit("找不到 APK: %s" % apk)

    version, version_code = read_pubspec_version(REPO_ROOT)
    changelog = read_changelog(REPO_ROOT, version)
    warnings, _is_debug = inspect_apk(apk, version)

    digest = hashlib.sha256()
    with apk.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)

    payload = {
        "version": version,
        "versionCode": version_code,
        "changelog": changelog,
        "downloadUrl": args.url or DOWNLOAD_URL_TEMPLATE.format(version=version),
        "sha256": digest.hexdigest(),
        "size": apk.stat().st_size,
    }

    text = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    if args.output == "-":
        sys.stdout.write(text)
    else:
        Path(args.output).write_text(text, encoding="utf-8")
        sys.stderr.write("已写入 %s\n" % args.output)

    sys.stderr.write("\nAPK: %s\n" % apk)
    sys.stderr.write("版本: %s+%d\n" % (version, version_code))
    sys.stderr.write("大小: %d 字节\n" % payload["size"])
    sys.stderr.write("sha256: %s\n" % payload["sha256"])

    if warnings:
        sys.stderr.write("\n" + "=" * 62 + "\n")
        sys.stderr.write("!! 发布前必须处理\n")
        for item in warnings:
            sys.stderr.write("   - %s\n" % item)
        sys.stderr.write("=" * 62 + "\n")
        return 1

    sys.stderr.write("\n校验通过：版本号匹配，且不是 debug 签名。\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
