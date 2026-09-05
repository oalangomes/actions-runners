#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$BASE_DIR/runner-runtime-env.sh"
HOST="${RUNNERS_DASHBOARD_HOST:-127.0.0.1}"
PORT="${RUNNERS_DASHBOARD_PORT:-8765}"
BACKEND_PORT="${RUNNERS_DASHBOARD_BACKEND_PORT:-8766}"

  if [[ "${RUNNERS_DASHBOARD_BACKEND_MODE:-0}" == "1" ]]; then
  HOST="${RUNNERS_DASHBOARD_BACKEND_HOST:-0.0.0.0}"
  PORT="$BACKEND_PORT"
fi

if command -v ss >/dev/null 2>&1 && ss -ltn "sport = :$PORT" | grep -q ":$PORT"; then
  echo "Dashboard ja esta rodando em http://$HOST:$PORT"
  exit 0
fi

if command -v lsof >/dev/null 2>&1 && lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Dashboard ja esta rodando em http://$HOST:$PORT"
  exit 0
fi

cd "$BASE_DIR"
export RUNNERS_DASHBOARD_HOST="$HOST"
export RUNNERS_DASHBOARD_PORT="$PORT"
exec ./dashboard.py
