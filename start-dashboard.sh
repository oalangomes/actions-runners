#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST="${RUNNERS_DASHBOARD_HOST:-127.0.0.1}"
PORT="${RUNNERS_DASHBOARD_PORT:-8765}"

if command -v ss >/dev/null 2>&1 && ss -ltn "sport = :$PORT" | grep -q ":$PORT"; then
  echo "Dashboard ja esta rodando em http://$HOST:$PORT"
  exit 0
fi

if command -v lsof >/dev/null 2>&1 && lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Dashboard ja esta rodando em http://$HOST:$PORT"
  exit 0
fi

cd "$BASE_DIR"
exec ./dashboard.py
