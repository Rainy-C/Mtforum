#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "===== VERSION ====="
grep '^version:' pubspec.yaml

echo
echo "===== SMILEY CATALOG TEST ====="
flutter test test/smiley_catalog_test.dart

echo
echo "===== RICH CONTENT REGRESSION ====="
if [[ -f test/rich_content_parser_test.dart ]]; then
  flutter test test/rich_content_parser_test.dart
fi

echo
echo "===== ANALYZE ====="
flutter analyze
