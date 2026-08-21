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
echo "===== V2.12 TEST ====="
flutter test test/user_center_v212_test.dart

echo
echo "===== V2.11 REGRESSION ====="
if [[ -f test/user_center_v211_test.dart ]]; then
  flutter test test/user_center_v211_test.dart
fi

echo
echo "===== V2.10 REGRESSION ====="
if [[ -f test/user_center_v210_test.dart ]]; then
  flutter test test/user_center_v210_test.dart
fi

echo
echo "===== ANALYZE ====="
flutter analyze
