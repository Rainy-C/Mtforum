#!/usr/bin/env python3
"""Generate the stable update manifest from the *built* signed APK."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
from urllib.parse import quote


def gradle_value(gradle: str, key: str) -> str:
    matches = re.findall(r"(?m)^\s*" + re.escape(key) + r"\s*=\s*(\"[^\"]+\"|\d+)\s*$", gradle)
    if len(matches) != 1:
        raise ValueError("Expected exactly one " + key + " in app/build.gradle.kts")
    return matches[0].strip('"')


def load_notes(path: Path, expected_version: str) -> list[str]:
    lines = [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if not lines or lines[0] != "version_name=" + expected_version:
        raise ValueError("Release notes version must match app version: " + expected_version)
    notes = [line[2:].strip() for line in lines[1:] if line.startswith("- ")]
    if not notes or any(not item for item in notes) or len(notes) != len(lines) - 1:
        raise ValueError("Release notes must contain non-empty '- ' changelog lines")
    return notes


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def generate(gradle_path: Path, apk_path: Path, notes_path: Path,
             repository: str, tag: str, release_date: str) -> dict:
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Invalid GitHub owner/repository name")
    if not apk_path.is_file() or apk_path.stat().st_size == 0:
        raise ValueError("Signed release APK is missing or empty")

    gradle = gradle_path.read_text(encoding="utf-8")
    version = gradle_value(gradle, "versionName")
    code = int(gradle_value(gradle, "versionCode"))
    app_id = gradle_value(gradle, "applicationId")
    if code <= 0 or not re.fullmatch(r"\d+\.\d+\.\d+(?:[-.][\w.-]+)?", version):
        raise ValueError("Invalid Android release version")
    if not re.fullmatch(r"v" + re.escape(version) + r"-build\.\d+", tag):
        raise ValueError("Release tag does not match APK version: " + version)
    datetime.strptime(release_date, "%Y-%m-%d")

    encoded_tag = quote(tag, safe="")
    encoded_apk = quote(apk_path.name, safe="")
    base_url = "https://github.com/" + repository + "/releases"
    return {
        "schema_version": 1,
        "app_id": app_id,
        "channel": "stable",
        "enabled": True,
        "latest": {
            "version_name": version,
            "version_code": code,
            "release_date": release_date,
            "title": "MTForum " + version + " 更新",
            "changelog": load_notes(notes_path, version),
            "download_url": base_url + "/download/" + encoded_tag + "/" + encoded_apk,
            "download_page_url": base_url,
            "file_size_bytes": apk_path.stat().st_size,
            "sha256": file_sha256(apk_path),
            "force_update": False,
            "min_supported_version_code": 6,
        },
        "check": {
            "check_on_launch": True,
            "interval_hours": 24,
            "allow_skip_version": True,
            "remind_later_hours": 24,
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gradle", type=Path, default=Path("app/build.gradle.kts"))
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--notes", type=Path, default=Path(".github/release-notes.txt"))
    parser.add_argument("--repository", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--release-date", default=datetime.now(timezone.utc).date().isoformat())
    args = parser.parse_args()
    try:
        manifest = generate(
            args.gradle, args.apk, args.notes, args.repository, args.tag, args.release_date
        )
    except (OSError, ValueError) as error:
        parser.error(str(error))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print("Update manifest ready: " + str(args.output))


if __name__ == "__main__":
    main()
