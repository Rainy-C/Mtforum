#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "===== VERSION ====="
grep '^version:' pubspec.yaml

echo
echo "===== V2.10 PARSER TEST ====="
flutter test test/user_center_v210_test.dart

echo
echo "===== USER CENTER REGRESSION ====="
if [[ -f test/user_center_parser_test.dart ]]; then
  flutter test test/user_center_parser_test.dart
fi

echo
echo "===== COMMUNITY REGRESSION ====="
if [[ -f test/community_fallback_test.dart ]]; then
  flutter test test/community_fallback_test.dart
fi

echo
echo "===== SMILEY REGRESSION ====="
if [[ -f test/smiley_editor_test.dart ]]; then
  flutter test test/smiley_editor_test.dart
fi

echo
echo "===== ANALYZE ====="
flutter analyze
