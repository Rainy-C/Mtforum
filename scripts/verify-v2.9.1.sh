#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "===== VERSION ====="
grep '^version:' pubspec.yaml

echo
echo "===== LOGIN / FORMHASH STATIC CHECK ====="
grep -n "游客 formhash" lib/services/api_service.dart
grep -n "_formhashAuth" lib/services/api_service.dart | head
grep -n "_primeFormhashAfterLogin" lib/services/api_service.dart

echo
echo "===== ANALYZE ====="
flutter analyze
