#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "===== VERSION ====="
grep '^version:' pubspec.yaml

echo
echo "===== LAUNCHER ICON ====="
test -f android/app/src/main/res/drawable/ic_launcher_foreground.xml
test -f android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
grep -q 'android:roundIcon="@mipmap/ic_launcher_round"' android/app/src/main/AndroidManifest.xml

echo
echo "===== PUB GET ====="
flutter pub get

echo
echo "===== POST EDITOR TESTS ====="
flutter test test/post_editor_parser_test.dart test/post_editor_v214_test.dart test/forum_parser_test.dart test/smiley_editor_test.dart

echo
echo "===== V2.12 REGRESSION ====="
flutter test test/user_center_v212_test.dart

echo
echo "===== ANALYZE ====="
flutter analyze
