#!/bin/bash
# Build and deploy Flutter web to VPS.
# Copy .env.local.example to .env.local and fill in your values before running.
#
# Usage:
#   bash scripts/build_web.sh          # build only
#   bash scripts/build_web.sh --deploy # build + deploy to VPS

set -e

DEPLOY=false
if [[ "$1" == "--deploy" ]]; then
  DEPLOY=true
fi

VPS_USER="deploy"
VPS_HOST="87.106.13.170"
VPS_PATH="/var/www/local_social_web"

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

# Ensure index.html is present in build output (Flutter can omit it in some cases)
if [ ! -f "build/web/index.html" ]; then
  sed 's|\$FLUTTER_BASE_HREF|/|g' web/index.html > build/web/index.html
  echo "Copied and patched web/index.html to build/web/"
fi

echo "Web build complete."

# Deploy to VPS
if [ "$DEPLOY" = true ]; then
  echo "Deploying to ${VPS_USER}@${VPS_HOST}:${VPS_PATH}..."
  ssh "${VPS_USER}@${VPS_HOST}" "rm -rf ${VPS_PATH}/*"
  scp -r build/web/* "${VPS_USER}@${VPS_HOST}:${VPS_PATH}/"
  # Remove template file from server (not needed at runtime)
  ssh "${VPS_USER}@${VPS_HOST}" "rm -f ${VPS_PATH}/firebase-messaging-sw.js.template"
  echo "Deploy complete. Live at https://app.allonssy.com"
fi
