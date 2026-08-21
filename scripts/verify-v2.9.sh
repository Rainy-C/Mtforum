#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "===== VERSION ====="
grep '^version:' pubspec.yaml

echo
echo "===== USER CENTER PARSER ====="
flutter test test/user_center_parser_test.dart

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
echo "===== PORTAL REGRESSION ====="
if [[ -f test/portal_parser_test.dart ]]; then
  flutter test test/portal_parser_test.dart
fi

echo
echo "===== ANALYZE ====="
flutter analyze
