#!/bin/bash
# Run the full news fetch locally using the production micro-batch settings.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

: "${SUPABASE_URL:?Set SUPABASE_URL in .env or environment}"
: "${SUPABASE_SERVICE_ROLE_KEY:?Set SUPABASE_SERVICE_ROLE_KEY in .env or environment}"

exec "$ROOT/.venv/bin/india-market-news" \
  --ticker-csv data/EQUITY_L.csv \
  --series EQ
