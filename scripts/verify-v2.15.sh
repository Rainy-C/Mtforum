#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -x /opt/flutter/bin/flutter ]]; then
  FLUTTER=/opt/flutter/bin/flutter
else
  FLUTTER="$(command -v flutter)"
fi

echo "===== VERSION ====="
grep '^version:' pubspec.yaml

echo
echo "===== PUB GET ====="
"$FLUTTER" pub get

echo
echo "===== V2.15 REGRESSION ====="
"$FLUTTER" test \
  test/user_center_v215_test.dart \
  test/forum_parser_v215_test.dart \
  test/user_center_v212_test.dart \
  test/user_center_v211_test.dart \
  test/forum_parser_test.dart

echo
echo "===== ANALYZE ====="
"$FLUTTER" analyze
