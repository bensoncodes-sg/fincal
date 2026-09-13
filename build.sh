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

# Feedback relay address (a Cloudflare Worker; see feedback-relay/README.md).
# Refuse anything that would compile the Telegram token into the public app.
FEEDBACK_URL="${FEEDBACK_URL:-}"
if [ -n "$FEEDBACK_URL" ]; then
  if [[ "$FEEDBACK_URL" == *telegram.org* ]] || [[ "$FEEDBACK_URL" =~ [0-9]{6,}:[A-Za-z0-9_-]{30,} ]] || [[ "$FEEDBACK_URL" != https://* ]]; then
    echo "REFUSING TO BUILD: FEEDBACK_URL must be your https relay URL, never a Telegram API URL or bot token."
    exit 1
  fi
  echo "Feedback will be sent to the relay."
  flutter build web --release --dart-define=FEEDBACK_URL="$FEEDBACK_URL"
else
  echo "No FEEDBACK_URL set: feedback stays on the device."
  flutter build web --release
fi
echo "Build complete -> build/web"
