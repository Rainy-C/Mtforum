#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "===== VERSION ====="
grep '^version:' pubspec.yaml

echo
echo "===== SIGN PARSER TEST ====="
flutter test test/sign_parser_test.dart

echo
echo "===== ANALYZE ====="
flutter analyze
