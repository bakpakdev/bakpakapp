#!/usr/bin/env bash
# Apply SQL to your Supabase Postgres using psql (install: brew install libpq && brew link --force libpq)
#
# 1. Dashboard → Project Settings → Database → Connection string → URI
# 2. Replace [YOUR-PASSWORD] with the database password (not the anon key).
# 3. Run:
#    export DATABASE_URL='postgresql://postgres.[ref]:[PASSWORD]@aws-0-[region].pooler.supabase.com:6543/postgres'
#    ./supabase/apply_with_psql.sh
#
# Or use the direct connection on port 5432 if pooler fails.
#
# To apply only the school/meetup + storage RLS fix on an existing project:
#    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/migrate_school_meetup.sql"
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "Set DATABASE_URL to your Supabase Postgres connection URI first." >&2
  exit 1
fi
export PGSSLMODE="${PGSSLMODE:-require}"
if [[ "${1:-}" == "migrate" ]]; then
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/migrate_school_meetup.sql"
  echo "Migration applied."
  exit 0
fi
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/schema.sql"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/storage.sql"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/policies.sql"
echo "Done. Next: Dashboard → Authentication → turn off Confirm email (dev)."
echo "For existing projects, also run: ./supabase/apply_with_psql.sh migrate"
