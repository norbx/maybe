#!/bin/bash
#
# Monthly restore drill: pulls the most recent backup from R2, decrypts,
# restores into a throwaway DB on the same Postgres instance, and reports
# row counts on key tables. Never touches maybe_production.
#
# Run as: bash maybe-restore-test.sh

set -euo pipefail

PASS_FILE="${PASS_FILE:-/etc/maybe-backup.pass}"
RCLONE_REMOTE="${RCLONE_REMOTE:-r2:maybe-backups}"
CONTAINER="${CONTAINER:-maybe-db}"
DB_USER="${DB_USER:-maybe}"
TEST_DB="${TEST_DB:-maybe_restore_test}"

LATEST=$(rclone lsf "${RCLONE_REMOTE}" --include 'maybe_*.dump.gpg' | sort | tail -n1)
[ -z "${LATEST}" ] && { echo "No backups found in ${RCLONE_REMOTE}"; exit 1; }

echo "Restoring from: ${LATEST}"

docker exec "${CONTAINER}" psql -U "${DB_USER}" -d postgres \
  -c "DROP DATABASE IF EXISTS ${TEST_DB};"
docker exec "${CONTAINER}" psql -U "${DB_USER}" -d postgres \
  -c "CREATE DATABASE ${TEST_DB} OWNER ${DB_USER};"

rclone cat "${RCLONE_REMOTE}/${LATEST}" \
  | gpg --decrypt --batch --quiet --passphrase-file "${PASS_FILE}" \
  | docker exec -i "${CONTAINER}" pg_restore -U "${DB_USER}" -d "${TEST_DB}" \
      --no-owner --no-privileges --disable-triggers --single-transaction

echo
echo "Row counts in restored DB:"
docker exec "${CONTAINER}" psql -U "${DB_USER}" -d "${TEST_DB}" -c "
  SELECT 'users' AS tbl, count(*) FROM users
  UNION ALL SELECT 'accounts', count(*) FROM accounts
  UNION ALL SELECT 'transactions', count(*) FROM transactions
  UNION ALL SELECT 'holdings', count(*) FROM holdings;
"

docker exec "${CONTAINER}" psql -U "${DB_USER}" -d postgres \
  -c "DROP DATABASE ${TEST_DB};"

echo "Restore test passed."
