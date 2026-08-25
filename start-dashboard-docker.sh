#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_PORT="${RUNNERS_DASHBOARD_BACKEND_PORT:-8766}"
FRONT_PORT="${RUNNERS_DASHBOARD_PORT:-8765}"
PID_FILE="$BASE_DIR/.dashboard-backend.pid"

backend_ready() {
    curl --silent --fail --max-time 2 "http://127.0.0.1:$BACKEND_PORT/api/health" >/dev/null 2>&1
}

front_ready() {
  curl --silent --fail --max-time 2 "http://127.0.0.1:$FRONT_PORT/" >/dev/null 2>&1
}

if ! backend_ready; then
  stale_pid="$(ss -ltnp "sport = :$BACKEND_PORT" 2>/dev/null | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' | head -n 1)"
  if [[ -n "$stale_pid" ]]; then
    kill "$stale_pid" 2>/dev/null || true
    for _ in {1..20}; do
      ss -ltnp "sport = :$BACKEND_PORT" 2>/dev/null | grep -q LISTEN || break
      sleep 0.25
    done
  fi
  RUNNERS_DASHBOARD_BACKEND_MODE=1 \
    RUNNERS_DASHBOARD_BACKEND_PORT="$BACKEND_PORT" \
    "$BASE_DIR/start-dashboard.sh" >"$BASE_DIR/.dashboard-backend.log" 2>&1 &
  echo $! >"$PID_FILE"
  for _ in {1..20}; do
    backend_ready && break
    sleep 0.25
  done
fi

backend_ready || {
  echo "ERRO: backend do dashboard nao iniciou; veja $BASE_DIR/.dashboard-backend.log" >&2
  exit 1
}

cd "$BASE_DIR"
docker compose up -d --build
for _ in {1..20}; do
  front_ready && break
  sleep 0.25
done
front_ready || {
  echo "ERRO: front Docker nao iniciou; execute docker compose logs runners-dashboard" >&2
  exit 1
}
echo "Dashboard: http://127.0.0.1:$FRONT_PORT"