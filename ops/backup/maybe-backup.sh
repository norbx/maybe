#!/bin/bash
#
# Daily Postgres backup → encrypted → Cloudflare R2.
# Pings Healthchecks.io on success so silent failures get noticed.
#
# Server prerequisites (one-time):
#   apt-get install -y gnupg rclone curl
#   echo "<strong-passphrase>" > /etc/maybe-backup.pass && chmod 600 /etc/maybe-backup.pass
#   rclone config            # add a remote named "r2" pointing at your R2 bucket
#
# Configure by editing the variables below or exporting them in /etc/cron.d/maybe-backup.

set -euo pipefail

HEALTHCHECK_URL="${HEALTHCHECK_URL:-}"
PASS_FILE="${PASS_FILE:-/etc/maybe-backup.pass}"
RCLONE_REMOTE="${RCLONE_REMOTE:-r2:maybe-backups}"
CONTAINER="${CONTAINER:-maybe-db}"
DB_USER="${DB_USER:-maybe}"
DB_NAME="${DB_NAME:-maybe_production}"

TS=$(date -u +%Y%m%dT%H%M%SZ)
TMP=$(mktemp /tmp/maybe-backup.XXXXXX.dump.gpg)

ping() {
  [ -z "${HEALTHCHECK_URL}" ] && return 0
  curl -fsS -m 10 --retry 3 "$@" >/dev/null || true
}

cleanup() { rm -f "${TMP}"; }
trap 'cleanup; ping "${HEALTHCHECK_URL}/fail"' ERR
trap 'cleanup' EXIT

ping "${HEALTHCHECK_URL}/start"

docker exec "${CONTAINER}" pg_dump -U "${DB_USER}" -Fc "${DB_NAME}" \
  | gpg --symmetric --batch --quiet --yes --passphrase-file "${PASS_FILE}" \
  > "${TMP}"

rclone copyto "${TMP}" "${RCLONE_REMOTE}/maybe_${TS}.dump.gpg"

ping "${HEALTHCHECK_URL}"
