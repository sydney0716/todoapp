#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter pub get
dart run sqflite_common_ffi_web:setup --force
flutter build web --release --base-href /app/ --no-web-resources-cdn "$@"
cp assets/fonts/OFL.txt build/web/assets/assets/fonts/OFL.txt
python3 scripts/prepare_web_cache.py
