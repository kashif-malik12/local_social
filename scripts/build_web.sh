#!/bin/bash
# Build script for Flutter web — injects Firebase secrets at build time.
# Copy .env.local.example to .env.local and fill in your values before running.

set -e

ENV_FILE="$(dirname "$0")/../.env.local"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: .env.local not found. Copy .env.local.example to .env.local and fill in your values."
  exit 1
fi

# Load env vars
set -a
source "$ENV_FILE"
set +a

# Generate firebase-messaging-sw.js from template
TEMPLATE="web/firebase-messaging-sw.js.template"
OUTPUT="web/firebase-messaging-sw.js"
sed "s|{{FIREBASE_WEB_API_KEY}}|${FIREBASE_WEB_API_KEY}|g" "$TEMPLATE" > "$OUTPUT"
echo "Generated $OUTPUT"

# Build Flutter web
flutter build web \
  --dart-define=FIREBASE_WEB_API_KEY="${FIREBASE_WEB_API_KEY}"

echo "Web build complete."
