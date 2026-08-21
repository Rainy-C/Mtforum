#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "===== VERSION ====="
grep '^version:' pubspec.yaml

echo
echo "===== PUB GET ====="
flutter pub get

echo
echo "===== POST / EDIT TESTS ====="
flutter test test/post_editor_parser_test.dart test/forum_parser_test.dart test/smiley_editor_test.dart

echo
echo "===== V2.12 REGRESSION ====="
flutter test test/user_center_v212_test.dart

echo
echo "===== ANALYZE ====="
flutter analyze
