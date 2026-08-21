#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo '===== VERSION ====='
grep '^version:' pubspec.yaml

echo '===== DEPENDENCIES ====='
flutter pub get

echo '===== PARSER REGRESSION TEST ====='
flutter test test/forum_parser_test.dart

echo '===== ANALYZE ====='
flutter analyze

echo '===== OK ====='
