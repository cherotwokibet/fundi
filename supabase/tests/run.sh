#!/usr/bin/env bash
# Applies the stub, every migration and every *_test.sql to a fresh local
# database. Needs Postgres with PostGIS. Usage: supabase/tests/run.sh [dbname]
set -euo pipefail
cd "$(dirname "$0")/.."
DB="${1:-fundi_test}"
dropdb --if-exists "$DB"
createdb "$DB"
run() { psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -f "$1" > /dev/null; }
run tests/stub_supabase.sql
for f in migrations/*.sql; do run "$f"; done
for t in tests/*_test.sql; do
  psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -f "$t"
done
