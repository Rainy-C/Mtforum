#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "===== VERSION ====="
grep '^version:' pubspec.yaml

echo
echo "===== FORMAT ====="
dart format lib/theme/app_theme.dart \
  lib/pages/home_page.dart \
  lib/pages/search_page.dart \
  lib/pages/profile_page.dart \
  lib/pages/settings_page.dart \
  lib/pages/thread_detail_page.dart

echo
echo "===== ANALYZE ====="
flutter analyze
