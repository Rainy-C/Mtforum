#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "===== VERSION ====="
grep '^version:' pubspec.yaml

echo
echo "===== COMMUNITY FALLBACK ====="
flutter test test/community_fallback_test.dart

echo
echo "===== SMILEY EDITOR ====="
flutter test test/smiley_editor_test.dart

echo
echo "===== EXISTING PORTAL TEST ====="
if [[ -f test/portal_parser_test.dart ]]; then
  flutter test test/portal_parser_test.dart
fi

echo
echo "===== EXISTING RICH CONTENT ====="
if [[ -f test/rich_content_parser_test.dart ]]; then
  flutter test test/rich_content_parser_test.dart
fi

echo
echo "===== ANALYZE ====="
flutter analyze
