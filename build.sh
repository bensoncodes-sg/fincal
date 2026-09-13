#!/usr/bin/env bash
# Render runs this in a fresh Ubuntu container with no Flutter installed.
# It fetches the exact Flutter version Basis is tested on, runs the whole test
# suite, and only then builds the web bundle. A failing test fails the deploy,
# so a calculation regression can never go live.
set -euo pipefail

FLUTTER_VERSION="3.44.4"

if [ ! -d "flutter" ]; then
  echo "Cloning Flutter $FLUTTER_VERSION..."
  git clone https://github.com/flutter/flutter.git -b "$FLUTTER_VERSION" --depth 1
fi

export PATH="$PATH:$PWD/flutter/bin"
flutter --version
flutter config --enable-web --no-analytics
flutter pub get

echo "Running tests (deploy stops here if any fail)..."
flutter test

flutter build web --release
echo "Build complete -> build/web"
