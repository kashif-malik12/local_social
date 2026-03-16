#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${HOME}/supabase-project"
BACKUP_ROOT="${HOME}/backups/supabase"
TIMESTAMP="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
WORK_DIR="${BACKUP_ROOT}/${TIMESTAMP}"
RETENTION_DAYS="${RETENTION_DAYS:-5}"

mkdir -p "${WORK_DIR}/db" "${WORK_DIR}/storage" "${WORK_DIR}/config"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found on PATH" >&2
  exit 1
fi

if [ ! -d "${BASE_DIR}" ]; then
  echo "supabase project directory not found: ${BASE_DIR}" >&2
  exit 1
fi

echo "[$(date -u +%FT%TZ)] starting backup in ${WORK_DIR}"

docker exec supabase-db pg_dump -U postgres -d postgres -Fc \
  > "${WORK_DIR}/db/postgres.dump"

tar -C "${BASE_DIR}" -czf "${WORK_DIR}/storage/storage.tar.gz" \
  volumes/storage

tar -C "${BASE_DIR}" -czf "${WORK_DIR}/config/config.tar.gz" \
  .env docker-compose.yml volumes/functions

cat > "${WORK_DIR}/manifest.txt" <<EOF
timestamp=${TIMESTAMP}
hostname=$(hostname)
base_dir=${BASE_DIR}
retention_days=${RETENTION_DAYS}
EOF

find "${BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -type d -mtime +"${RETENTION_DAYS}" -exec rm -rf {} +

LATEST_LINK="${BACKUP_ROOT}/latest"
rm -f "${LATEST_LINK}"
ln -s "${WORK_DIR}" "${LATEST_LINK}"

echo "[$(date -u +%FT%TZ)] backup complete"
