#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "===== VERSION ====="
grep '^version:' pubspec.yaml

echo
echo "===== RICH CONTENT TEST ====="
flutter test test/rich_content_parser_test.dart

echo
echo "===== EXISTING PARSER TEST ====="
if [[ -f test/forum_parser_test.dart ]]; then
  flutter test test/forum_parser_test.dart
fi

echo
echo "===== ANALYZE ====="
flutter analyze
