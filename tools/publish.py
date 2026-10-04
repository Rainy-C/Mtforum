#!/usr/bin/env python3
"""一键发布：校验 APK → 生成 update.json → 上传到 S3 兼容对象存储。

用法:
    python3 tools/publish.py build/app/outputs/flutter-apk/app-release.apk
    python3 tools/publish.py --dry-run            # 只生成 update.json，不上传

凭证来源（按优先级，**都不会进仓库**）:
    1. 环境变量 R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY
    2. 文件 ~/.mtforum-r2（第一行 AK，第二行 SK）
    3. 文件 .r2_credentials（仓库根目录，已加入 .gitignore）

配置默认值可用环境变量覆盖:
    R2_ENDPOINT / R2_BUCKET / R2_PREFIX / MTFORUM_UPDATE_BASE

上传前会做两项校验（不通过直接终止，避免把错包推给用户）:
    - APK 的 versionName 必须等于 pubspec.yaml 的版本号
    - APK 不能是 debug 签名
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import hmac
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from make_update_json import (  # noqa: E402
    DEFAULT_APK,
    REPO_ROOT,
    inspect_apk,
    read_changelog,
    read_pubspec_version,
)

DEFAULT_ENDPOINT = os.environ.get("R2_ENDPOINT", "")
DEFAULT_BUCKET = os.environ.get("R2_BUCKET", "chen")
DEFAULT_PREFIX = os.environ.get("R2_PREFIX", "Mt/")
APK_CONTENT_TYPE = "application/vnd.android.package-archive"
JSON_CONTENT_TYPE = "application/json; charset=utf-8"


# ---------------------------------------------------------------- 凭证


def load_credentials() -> tuple[str, str]:
    ak = os.environ.get("R2_ACCESS_KEY_ID", "").strip()
    sk = os.environ.get("R2_SECRET_ACCESS_KEY", "").strip()
    if ak and sk:
        return ak, sk

    candidates = [Path.home() / ".mtforum-r2", REPO_ROOT / ".r2_credentials"]
    for path in candidates:
        if not path.exists():
            continue
        lines = [l.strip() for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]
        if len(lines) >= 2:
            return lines[0], lines[1]

    raise SystemExit(
        "找不到对象存储凭证。请设置 R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY 环境变量，\n"
        "或写入 ~/.mtforum-r2（第一行 AK，第二行 SK）。"
    )


# ---------------------------------------------------------------- SigV4


def _hmac(key: bytes, msg: str) -> bytes:
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()


def _signing_key(secret: str, datestamp: str, region: str, service: str) -> bytes:
    key = _hmac(("AWS4" + secret).encode("utf-8"), datestamp)
    for part in (region, service, "aws4_request"):
        key = _hmac(key, part)
    return key


def s3_request(
    method: str,
    endpoint: str,
    bucket: str,
    key: str,
    payload: bytes,
    access_key: str,
    secret_key: str,
    region: str = "auto",
    content_type: str | None = None,
) -> tuple[int, bytes]:
    """最小可用的 S3 请求（SigV4），只覆盖 PUT / GET / HEAD。"""
    parsed = urllib.parse.urlparse(endpoint)
    host = parsed.netloc
    canonical_uri = "/" + bucket + ("/" + urllib.parse.quote(key, safe="/~") if key else "")

    now = datetime.datetime.now(datetime.timezone.utc)
    amz_date = now.strftime("%Y%m%dT%H%M%SZ")
    datestamp = now.strftime("%Y%m%d")
    payload_hash = hashlib.sha256(payload).hexdigest()

    headers = {
        "host": host,
        "x-amz-content-sha256": payload_hash,
        "x-amz-date": amz_date,
    }
    if content_type:
        headers["content-type"] = content_type

    signed_headers = ";".join(sorted(headers))
    canonical_headers = "".join("%s:%s\n" % (k, headers[k]) for k in sorted(headers))
    canonical_request = "\n".join(
        [method, canonical_uri, "", canonical_headers, signed_headers, payload_hash]
    )
    scope = "%s/%s/s3/aws4_request" % (datestamp, region)
    string_to_sign = "\n".join(
        [
            "AWS4-HMAC-SHA256",
            amz_date,
            scope,
            hashlib.sha256(canonical_request.encode("utf-8")).hexdigest(),
        ]
    )
    signature = hmac.new(
        _signing_key(secret_key, datestamp, region, "s3"),
        string_to_sign.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()

    url = endpoint.rstrip("/") + canonical_uri
    request = urllib.request.Request(
        url, data=payload if method in ("PUT", "POST") else None, method=method
    )
    for name, value in headers.items():
        request.add_header(name, value)
    request.add_header(
        "authorization",
        "AWS4-HMAC-SHA256 Credential=%s/%s, SignedHeaders=%s, Signature=%s"
        % (access_key, scope, signed_headers, signature),
    )

    try:
        with urllib.request.urlopen(request, timeout=600) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def upload(
    data: bytes,
    target: str,
    endpoint: str,
    bucket: str,
    access_key: str,
    secret_key: str,
    content_type: str,
) -> None:
    keys = target.split(",")
    for key in keys:
        key = key.strip()
        print("  上传 %s (%s, %s) ..." % (key, _human(len(data)), content_type))
        status, body = s3_request(
            "PUT", endpoint, bucket, key, data, access_key, secret_key,
            content_type=content_type,
        )
        if status not in (200, 201):
            raise SystemExit(
                "  上传失败: HTTP %s\n  %s" % (status, body[:400].decode("utf-8", "replace"))
            )


def _human(size: int) -> str:
    return "%.1f MB" % (size / 1024 / 1024)


# ---------------------------------------------------------------- main


def main() -> int:
    parser = argparse.ArgumentParser(description="校验并发布 MT论坛更新")
    parser.add_argument("apk", nargs="?", default=str(DEFAULT_APK))
    parser.add_argument("--endpoint", default=DEFAULT_ENDPOINT)
    parser.add_argument("--bucket", default=DEFAULT_BUCKET)
    parser.add_argument("--prefix", default=DEFAULT_PREFIX)
    parser.add_argument("--update-base", default=os.environ.get("MTFORUM_UPDATE_BASE", ""))
    parser.add_argument("--dry-run", action="store_true", help="只生成 update.json，不上传")
    args = parser.parse_args()

    apk = Path(args.apk)
    if not apk.exists():
        raise SystemExit("找不到 APK: %s" % apk)

    version, version_code = read_pubspec_version(REPO_ROOT)
    changelog = read_changelog(REPO_ROOT, version)
    warnings, _ = inspect_apk(apk, version)

    print("版本: %s+%d" % (version, version_code))
    print("APK : %s (%s)" % (apk, _human(apk.stat().st_size)))
    if warnings:
        print("\n" + "=" * 60)
        print("发布已终止，以下问题必须先解决：")
        for item in warnings:
            print("  - %s" % item)
        print("=" * 60)
        return 1

    data = apk.read_bytes()
    digest = hashlib.sha256(data).hexdigest()

    prefix = args.prefix if args.prefix.endswith("/") or not args.prefix else args.prefix + "/"
    apk_key = "%sMTForum-%s-Release.apk" % (prefix, version)
    json_key = "%supdate.json" % prefix

    base = args.update_base
    if not base and args.endpoint:
        base = ""
    download_url = (base.rstrip("/") + "/" + apk_key) if base else ""

    payload = {
        "version": version,
        "versionCode": version_code,
        "changelog": changelog,
        "downloadUrl": download_url,
        "sha256": digest,
        "size": len(data),
    }

    import json as _json

    text = _json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    out = REPO_ROOT / "update.json"
    out.write_text(text, encoding="utf-8")
    print("\n已生成 %s" % out)

    if not download_url:
        print("\n!! 缺少公网下载地址前缀（--update-base 或 MTFORUM_UPDATE_BASE），")
        print("   update.json 的 downloadUrl 为空。请补上后重跑。")
        return 1

    print("\nupdate.json:")
    print(text)

    if args.dry_run:
        print("--dry-run：跳过上传。")
        return 0

    if not args.endpoint:
        raise SystemExit("缺少 --endpoint 或 R2_ENDPOINT")

    access_key, secret_key = load_credentials()

    print("上传中 ...")
    upload(data, apk_key, args.endpoint, args.bucket, access_key, secret_key, APK_CONTENT_TYPE)
    upload(text.encode("utf-8"), json_key, args.endpoint, args.bucket,
           access_key, secret_key, JSON_CONTENT_TYPE)

    print("\n完成。")
    print("  安装包: %s" % download_url)
    print("  更新源: %s" % (base.rstrip("/") + "/" + json_key))
    print("  sha256: %s" % digest)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
