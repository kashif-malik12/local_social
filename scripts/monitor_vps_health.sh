#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${HOME}/monitoring"
LOG_FILE="${LOG_DIR}/health.log"
TMP_FILE="$(mktemp)"

mkdir -p "${LOG_DIR}"

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

check_url() {
  local name="$1"
  local url="$2"
  local status
  status="$(curl -k -L -s -o /dev/null -w '%{http_code}' --max-time 20 "$url" || true)"
  printf 'url[%s]=%s %s\n' "$name" "${status:-000}" "$url" >> "${TMP_FILE}"
}

{
  echo "=== $(timestamp) ==="
  echo "hostname=$(hostname)"
  echo "uptime=$(uptime -p || true)"
  echo "load=$(uptime | awk -F'load average:' '{print $2}' | xargs || true)"
  echo "--- disk ---"
  df -h /
  echo "--- memory ---"
  free -h || true
  echo "--- docker ---"
  docker ps --format 'container={{.Names}} status={{.Status}}'
  echo "--- endpoints ---"
} >> "${TMP_FILE}"

check_url "app" "https://app.allonssy.com"
check_url "supabase-root" "https://supabase.allonssy.com"
check_url "supabase-rest" "https://supabase.allonssy.com/rest/v1/"
check_url "supabase-auth-health" "https://supabase.allonssy.com/auth/v1/health"
check_url "supabase-storage-health" "https://supabase.allonssy.com/storage/v1/status"
check_url "function-admin-auth" "https://supabase.allonssy.com/functions/v1/admin-user-auth"

echo >> "${TMP_FILE}"
cat "${TMP_FILE}" >> "${LOG_FILE}"
rm -f "${TMP_FILE}"
