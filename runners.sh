#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="$BASE_DIR/runners.conf"
PID_DIR="$BASE_DIR/.runner-pids"
LOG_DIR="$BASE_DIR/.runner-logs"
CACHE_ENV_PATH="$BASE_DIR/runner-cache-env.sh"

usage() {
  cat <<'EOF'
Uso:
  ./runners.sh <acao> [runner|all]

Acoes:
  start      inicia runner(s)
  stop       para runner(s)
  restart    reinicia runner(s)
  status     mostra status
  list       lista runners
  doctor     valida estrutura
  logs       mostra caminho do log
  help       mostra ajuda

Exemplos:
  ./runners.sh status
  ./runners.sh start all
  ./runners.sh start neurotrack-app
  ./runners.sh stop agentsorch
  ./runners.sh restart neurotrack-web
  ./runners.sh doctor all
EOF
}

die() {
  echo "ERRO: $*" >&2
  exit 1
}

is_running_pid() {
  local pid="$1"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

pid_file() {
  printf '%s/%s.pid\n' "$PID_DIR" "$1"
}

log_file() {
  printf '%s/%s.log\n' "$LOG_DIR" "$1"
}

read_config() {
  [[ -f "$CONFIG_PATH" ]] || die "arquivo de configuracao nao encontrado: $CONFIG_PATH"

  RUNNER_NAMES=()
  RUNNER_PATHS=()

  while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    line="${raw_line//$'\r'/}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
    [[ "$line" == *"|"* ]] || die "linha invalida no runners.conf: $line"

    name="${line%%|*}"
    path="${line#*|}"
    [[ -n "$name" ]] || die "nome de runner vazio no runners.conf"
    [[ -n "$path" ]] || die "path vazio para runner '$name'"

    RUNNER_NAMES+=("$name")
    RUNNER_PATHS+=("$path")
  done < "$CONFIG_PATH"
}

runner_index() {
  local target="$1"
  local i

  for i in "${!RUNNER_NAMES[@]}"; do
    if [[ "${RUNNER_NAMES[$i]}" == "$target" ]]; then
      printf '%s\n' "$i"
      return 0
    fi
  done

  return 1
}

target_indexes() {
  local target="$1"
  local i

  if [[ "$target" == "all" ]]; then
    for i in "${!RUNNER_NAMES[@]}"; do
      printf '%s\n' "$i"
    done
    return 0
  fi

  runner_index "$target" || die "runner desconhecido: $target"
}

runner_pid() {
  local file
  file="$(pid_file "$1")"
  [[ -f "$file" ]] && tr -d '[:space:]' < "$file"
}

start_runner() {
  local name="$1"
  local path="$2"
  local run_sh="$path/run.sh"
  local pid

  [[ -d "$path" ]] || die "$name: diretorio nao encontrado: $path"
  [[ -x "$run_sh" ]] || die "$name: run.sh nao encontrado ou sem permissao em: $path"

  pid="$(runner_pid "$name" || true)"
  if is_running_pid "$pid"; then
    echo "[OK] $name ja esta rodando (pid $pid)"
    return 0
  fi

  mkdir -p "$PID_DIR" "$LOG_DIR"
  if [[ -f "$CACHE_ENV_PATH" ]]; then
    # shellcheck source=/dev/null
    source "$CACHE_ENV_PATH"
    mkdir -p "$RUNNER_CACHE_ROOT"
  fi
  echo "[START] iniciando $name"
  echo "   $path"
  echo "   log: $(log_file "$name")"

  (
    cd "$path"
    nohup ./run.sh >> "$(log_file "$name")" 2>&1 &
    echo $! > "$(pid_file "$name")"
  )
}

stop_runner() {
  local name="$1"
  local pid

  pid="$(runner_pid "$name" || true)"
  if ! is_running_pid "$pid"; then
    echo "[STOP] $name ja esta parado"
    rm -f "$(pid_file "$name")"
    return 0
  fi

  echo "[STOP] parando $name (pid $pid)"
  kill "$pid" 2>/dev/null || true

  for _ in {1..20}; do
    if ! is_running_pid "$pid"; then
      rm -f "$(pid_file "$name")"
      return 0
    fi
    sleep 0.5
  done

  echo "[STOP] encerrando $name com SIGKILL"
  kill -9 "$pid" 2>/dev/null || true
  rm -f "$(pid_file "$name")"
}

status_runner() {
  local name="$1"
  local path="$2"
  local pid

  pid="$(runner_pid "$name" || true)"
  if is_running_pid "$pid"; then
    echo "[OK] $name rodando  pid=$pid  $path"
  else
    echo "[STOP] $name parado   $path"
  fi
}

doctor_runner() {
  local name="$1"
  local path="$2"
  local ok=0

  echo
  echo "Runner: $name"
  echo "Path:   $path"

  if [[ -d "$path" ]]; then
    echo "[OK] diretorio existe"
  else
    echo "[ERR] diretorio nao existe"
    ok=1
  fi

  if [[ -x "$path/run.sh" ]]; then
    echo "[OK] run.sh encontrado"
  else
    echo "[ERR] run.sh nao encontrado ou sem permissao"
    ok=1
  fi

  if [[ -f "$path/.runner" ]]; then
    echo "[OK] .runner encontrado"
  else
    echo "[WARN] .runner nao encontrado"
  fi

  return "$ok"
}

ACTION="${1:-status}"
TARGET="${2:-all}"

if [[ "$ACTION" == "help" || "$ACTION" == "-h" || "$ACTION" == "--help" ]]; then
  usage
  exit 0
fi

case "$ACTION" in
  start|stop|restart|status|list|doctor|logs) ;;
  *) die "acao desconhecida: $ACTION" ;;
esac

read_config

if [[ "$ACTION" == "list" ]]; then
  for i in "${!RUNNER_NAMES[@]}"; do
    echo "${RUNNER_NAMES[$i]} -> ${RUNNER_PATHS[$i]}"
  done
  exit 0
fi

mapfile -t indexes < <(target_indexes "$TARGET")

case "$ACTION" in
  start)
    for i in "${indexes[@]}"; do
      start_runner "${RUNNER_NAMES[$i]}" "${RUNNER_PATHS[$i]}"
    done
    ;;
  stop)
    for i in "${indexes[@]}"; do
      stop_runner "${RUNNER_NAMES[$i]}"
    done
    ;;
  restart)
    for i in "${indexes[@]}"; do
      stop_runner "${RUNNER_NAMES[$i]}"
      start_runner "${RUNNER_NAMES[$i]}" "${RUNNER_PATHS[$i]}"
    done
    ;;
  status)
    for i in "${indexes[@]}"; do
      status_runner "${RUNNER_NAMES[$i]}" "${RUNNER_PATHS[$i]}"
    done
    ;;
  doctor)
    exit_code=0
    for i in "${indexes[@]}"; do
      doctor_runner "${RUNNER_NAMES[$i]}" "${RUNNER_PATHS[$i]}" || exit_code=1
    done
    exit "$exit_code"
    ;;
  logs)
    for i in "${indexes[@]}"; do
      echo "${RUNNER_NAMES[$i]} -> $(log_file "${RUNNER_NAMES[$i]}")"
    done
    ;;
esac
