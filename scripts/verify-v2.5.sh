#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "===== VERSION ====="
grep '^version:' pubspec.yaml

echo
echo "===== NAKED LINK PARSER TEST ====="
flutter test test/linkify_parser_test.dart

echo
echo "===== EXISTING RICH CONTENT TEST ====="
if [[ -f test/rich_content_parser_test.dart ]]; then
  flutter test test/rich_content_parser_test.dart
fi

echo
echo "===== ANALYZE ====="
flutter analyze
