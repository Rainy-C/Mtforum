#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "===== VERSION ====="
grep '^version:' pubspec.yaml

echo
echo "===== ACCOUNT PARSER TEST ====="
flutter test test/account_parser_test.dart

echo
echo "===== SIGN PARSER TEST ====="
if [[ -f test/sign_parser_test.dart ]]; then
  flutter test test/sign_parser_test.dart
fi

echo
echo "===== ANALYZE ====="
flutter analyze
