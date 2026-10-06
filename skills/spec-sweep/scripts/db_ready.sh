#!/usr/bin/env bash
# db_ready.sh <n> [<n> ...]  — are the <app>_test<n> databases usable for spec runs right now?
#
# Ready = database exists, its newest migration matches db/schema.rb's version, and the
# reference org (subdomain "testorg") is seeded. Prints one line per DB; exits 1 if any is not ready.
#
# Why check instead of always preparing: `rake parallel:prepare_with_seeds` reloads the schema of
# <app>_test AND <app>_test2..N — it WIPES them. Running it while bin/ci, another sweep, or any spec run
# uses one of those databases destroys that run's data mid-flight. Prepare only when this says so,
# and only when nothing else is running.
set -uo pipefail
# Database name prefix from config/database.yml (e.g. "myapp" for myapp_test); override with APP_DB_PREFIX.
APP_DB_PREFIX="${APP_DB_PREFIX:-$(sed -n 's/^ *database: *\([a-z0-9_]*\)_development.*/\1/p' config/database.yml | head -1)}"
[ -n "$APP_DB_PREFIX" ] || { echo "Could not detect the database name prefix from config/database.yml — set APP_DB_PREFIX" >&2; exit 2; }
want="$(grep -oE 'define\(version: [0-9_]+' db/schema.rb | grep -oE '[0-9_]+$' | tr -d _)"
status=0
for n in "$@"; do
  db="${APP_DB_PREFIX}_test${DATABASE_SUFFIX:-}${n}"
  have="$(psql -d "$db" -Atqc 'select max(version) from schema_migrations' 2>/dev/null)"
  org="$(psql -d "$db" -Atqc "select count(*) from organizations where subdomain='testorg'" 2>/dev/null)"
  if [ -z "$have" ]; then echo "NOT READY $db (missing)"; status=1
  elif [ "$have" != "$want" ]; then echo "NOT READY $db (schema $have, want $want)"; status=1
  elif [ "${org:-0}" = "0" ]; then echo "NOT READY $db (no reference data)"; status=1
  else echo "ready     $db"; fi
done
exit $status
