#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${RUNNERS_CONFIG:-$BASE_DIR/runners.conf}"
PID_DIR="$BASE_DIR/.runner-pids"
LOG_DIR="$BASE_DIR/.runner-logs"
CACHE_ENV_PATH="$BASE_DIR/runner-cache-env.sh"
LOG_MAX_BYTES="${RUNNER_LOG_MAX_BYTES:-10485760}"
ARCHIVE_DIAG_PAGES_ON_START="${RUNNER_ARCHIVE_DIAG_PAGES_ON_START:-1}"

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
  doctor     valida estrutura e stack por perfil
  health     mostra alertas locais resumidos
  logs       mostra caminho do log
  help       mostra ajuda

Exemplos:
  ./runners.sh status
  ./runners.sh start all
  ./runners.sh start neurotrack-app
  ./runners.sh stop agentsorch
  ./runners.sh restart neurotrack-web
  ./runners.sh doctor all
  ./runners.sh health all
EOF
}

die() {
  echo "ERRO: $*" >&2
  exit 1
}

info() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

is_running_pid() {
  local pid="${1:-}"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

pid_file() {
  printf '%s/%s.pid\n' "$PID_DIR" "$1"
}

log_file() {
  printf '%s/%s.log\n' "$LOG_DIR" "$1"
}

runner_pid() {
  local file
  file="$(pid_file "$1")"
  [[ -f "$file" ]] && tr -d '[:space:]' < "$file"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

read_config() {
  [[ -f "$CONFIG_PATH" ]] || die "arquivo de configuracao nao encontrado: $CONFIG_PATH"

  RUNNER_NAMES=()
  RUNNER_PATHS=()
  RUNNER_PROFILES=()
  RUNNER_REPOS=()
  RUNNER_ENABLED=()

  while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    line="${raw_line//$'\r'/}"
    line="$(trim "$line")"

    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
    [[ "$line" == *"|"* ]] || die "linha invalida no runners.conf: $line"

    IFS='|' read -r name path profile repo enabled _ <<< "$line"
    name="$(trim "${name:-}")"
    path="$(trim "${path:-}")"
    profile="$(trim "${profile:-generic}")"
    repo="$(trim "${repo:-}")"
    enabled="$(trim "${enabled:-true}")"

    [[ -n "$name" ]] || die "nome de runner vazio no runners.conf"
    [[ -n "$path" ]] || die "path vazio para runner '$name'"

    case "${enabled,,}" in
      true|1|yes|y|sim) enabled="true" ;;
      false|0|no|n|nao|não) enabled="false" ;;
      *) enabled="true" ;;
    esac

    RUNNER_NAMES+=("$name")
    RUNNER_PATHS+=("$path")
    RUNNER_PROFILES+=("${profile:-generic}")
    RUNNER_REPOS+=("$repo")
    RUNNER_ENABLED+=("$enabled")
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

runner_processes_by_path() {
  local path="$1"
  [[ -d "$path" ]] || return 0

  # Detects orphaned/duplicate GitHub runner processes tied to this runner folder.
  # This prevents a second run.sh from starting while Runner.Listener/Runner.Worker
  # from a previous interrupted session is still alive.
  pgrep -af "$path" 2>/dev/null |
    awk '/run\.sh|Runner\.Listener|Runner\.Worker/ { print $1 }' |
    sort -n -u || true
}

runner_has_process_by_path() {
  local path="$1"
  [[ -n "$(runner_processes_by_path "$path" | head -n 1)" ]]
}

rotate_log_if_needed() {
  local file="$1"

  [[ -f "$file" ]] || return 0

  local size
  size="$(wc -c < "$file" 2>/dev/null || echo 0)"

  if [[ "$size" -gt "$LOG_MAX_BYTES" ]]; then
    mv "$file" "$file.$(date '+%Y%m%d%H%M%S')"
    touch "$file"
  fi
}

archive_diag_pages() {
  local path="$1"
  local pages_dir="$path/_diag/pages"
  local archive_dir

  [[ "$ARCHIVE_DIAG_PAGES_ON_START" == "1" ]] || return 0
  [[ -d "$pages_dir" ]] || return 0

  if ! find "$pages_dir" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
    return 0
  fi

  archive_dir="$path/_diag/pages.archive.$(date '+%Y%m%d%H%M%S')"
  mkdir -p "$archive_dir"
  find "$pages_dir" -mindepth 1 -maxdepth 1 -exec mv {} "$archive_dir" \;
  echo "[DIAG] _diag/pages arquivado em: $archive_dir"
}

source_cache_env() {
  local name="$1"
  local profile="$2"
  local repo="$3"

  if [[ -f "$CACHE_ENV_PATH" ]]; then
    export LOCAL_RUNNER_NAME="$name"
    export LOCAL_RUNNER_PROFILE="$profile"
    export LOCAL_RUNNER_REPO="$repo"
    # shellcheck source=/dev/null
    source "$CACHE_ENV_PATH"
    mkdir -p "${RUNNER_CACHE_ROOT:-$BASE_DIR/.runner-cache}"
  fi
}

start_runner() {
  local name="$1"
  local path="$2"
  local profile="$3"
  local repo="$4"
  local enabled="$5"
  local run_sh="$path/run.sh"
  local pid
  local file
  local orphan_pids

  if [[ "$enabled" != "true" ]]; then
    info "[SKIP] $name desabilitado no runners.conf"
    return 0
  fi

  [[ -d "$path" ]] || die "$name: diretorio nao encontrado: $path"
  [[ -x "$run_sh" ]] || die "$name: run.sh nao encontrado ou sem permissao em: $path"

  pid="$(runner_pid "$name" || true)"
  if is_running_pid "$pid"; then
    echo "[OK] $name ja esta rodando (pid $pid)"
    return 0
  fi

  orphan_pids="$(runner_processes_by_path "$path" | paste -sd ' ' -)"
  if [[ -n "$orphan_pids" ]]; then
    echo "[OK] $name parece ja estar rodando sem pid file valido: $orphan_pids"
    echo "${orphan_pids%% *}" > "$(pid_file "$name")"
    return 0
  fi

  mkdir -p "$PID_DIR" "$LOG_DIR"
  file="$(log_file "$name")"
  rotate_log_if_needed "$file"
  archive_diag_pages "$path"
  source_cache_env "$name" "$profile" "$repo"

  echo "[START] iniciando $name"
  echo "   path: $path"
  echo "   profile: $profile"
  [[ -n "$repo" ]] && echo "   repo: $repo"
  echo "   cache: ${RUNNER_STACK_CACHE_ROOT:-n/a}"
  echo "   tools: ${RUNNER_TOOL_CACHE:-n/a}"
  echo "   log: $file"

  (
    cd "$path"
    export LOCAL_RUNNER_NAME="$name"
    export LOCAL_RUNNER_PROFILE="$profile"
    export LOCAL_RUNNER_REPO="$repo"
    if command_exists setsid; then
      nohup setsid bash -c 'exec ./run.sh' >> "$file" 2>&1 &
    else
      nohup ./run.sh >> "$file" 2>&1 &
    fi
    echo $! > "$(pid_file "$name")"
  )
}

terminate_pid_group() {
  local pid="$1"

  [[ -n "$pid" ]] || return 0

  if is_running_pid "$pid"; then
    kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
  fi
}

kill_runner_processes_by_path() {
  local path="$1"
  local pid

  while read -r pid; do
    [[ -n "$pid" ]] || continue
    kill "$pid" 2>/dev/null || true
  done < <(runner_processes_by_path "$path")
}

stop_runner() {
  local name="$1"
  local path="${2:-}"
  local pid

  pid="$(runner_pid "$name" || true)"

  if ! is_running_pid "$pid" && [[ -n "$path" ]] && ! runner_has_process_by_path "$path"; then
    echo "[STOP] $name ja esta parado"
    rm -f "$(pid_file "$name")"
    return 0
  fi

  echo "[STOP] parando $name${pid:+ (pid $pid)}"
  terminate_pid_group "$pid"

  for _ in {1..20}; do
    if ! is_running_pid "$pid" && { [[ -z "$path" ]] || ! runner_has_process_by_path "$path"; }; then
      rm -f "$(pid_file "$name")"
      return 0
    fi
    sleep 0.5
  done

  echo "[STOP] encerrando processos remanescentes de $name"
  if [[ -n "$path" ]]; then
    kill_runner_processes_by_path "$path"
  fi
  [[ -n "$pid" ]] && kill -9 "$pid" 2>/dev/null || true
  rm -f "$(pid_file "$name")"
}

status_runner() {
  local name="$1"
  local path="$2"
  local profile="$3"
  local repo="$4"
  local enabled="$5"
  local pid
  local extra_pids

  pid="$(runner_pid "$name" || true)"
  extra_pids="$(runner_processes_by_path "$path" | paste -sd ' ' -)"

  if [[ "$enabled" != "true" ]]; then
    echo "[DISABLED] $name profile=$profile repo=${repo:-n/a} $path"
  elif is_running_pid "$pid" || [[ -n "$extra_pids" ]]; then
    echo "[OK] $name rodando pid=${pid:-n/a} detected=${extra_pids:-n/a} profile=$profile repo=${repo:-n/a} $path"
  else
    echo "[STOP] $name parado profile=$profile repo=${repo:-n/a} $path"
  fi
}

profile_commands() {
  case "$1" in
    node)
      echo "git node npm"
      ;;
    python)
      echo "git python3 pip3"
      ;;
    flutter|android)
      echo "git java flutter"
      ;;
    java)
      echo "git java"
      ;;
    dotnet)
      echo "git dotnet"
      ;;
    go)
      echo "git go"
      ;;
    *)
      echo "git"
      ;;
  esac
}

doctor_runner() {
  local name="$1"
  local path="$2"
  local profile="$3"
  local repo="$4"
  local enabled="$5"
  local ok=0
  local cmd
  local detected_pids

  echo
  echo "Runner: $name"
  echo "Path:   $path"
  echo "Profile: $profile"
  echo "Repo:   ${repo:-n/a}"
  echo "Enabled: $enabled"

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

  detected_pids="$(runner_processes_by_path "$path" | paste -sd ' ' -)"
  if [[ -n "$detected_pids" ]]; then
    echo "[OK] processos detectados: $detected_pids"
  else
    echo "[INFO] nenhum processo ativo detectado para este runner"
  fi

  if [[ -f "$CACHE_ENV_PATH" ]]; then
    echo "[OK] runner-cache-env.sh encontrado"
    source_cache_env "$name" "$profile" "$repo"
    echo "[OK] cache profile=$RUNNER_CACHE_PROFILE stack=$RUNNER_STACK_CACHE_ROOT tools=$RUNNER_TOOL_CACHE"
  else
    echo "[WARN] runner-cache-env.sh nao encontrado"
  fi

  echo "Stack:"
  for cmd in $(profile_commands "$profile"); do
    if command_exists "$cmd"; then
      echo "[OK] $cmd -> $(command -v "$cmd")"
    else
      echo "[WARN] $cmd nao encontrado no PATH"
    fi
  done

  return "$ok"
}

recent_log_has_error() {
  local file="$1"

  [[ -f "$file" ]] || return 1

  tail -n 200 "$file" | grep -Eiq 'error|fatal|unauthorized|forbidden|denied|failed|cannot|exception|segmentation fault|already exists'
}

health_runner() {
  local name="$1"
  local path="$2"
  local profile="$3"
  local _repo="$4"
  local enabled="$5"
  local pid
  local detected_count

  pid="$(runner_pid "$name" || true)"
  detected_count="$(runner_processes_by_path "$path" | wc -l | tr -d '[:space:]')"

  if [[ "$enabled" != "true" ]]; then
    echo "[INFO] $name desabilitado"
    return 0
  fi

  if [[ -f "$(pid_file "$name")" ]] && ! is_running_pid "$pid" && [[ "$detected_count" -eq 0 ]]; then
    echo "[WARN] $name possui PID stale: $(pid_file "$name")"
  fi

  if [[ "$detected_count" -gt 1 ]]; then
    echo "[WARN] $name pode ter processos duplicados detectados: $(runner_processes_by_path "$path" | paste -sd ' ' -)"
  fi

  if ! is_running_pid "$pid" && [[ "$detected_count" -eq 0 ]]; then
    echo "[WARN] $name parado"
  fi

  if [[ ! -x "$path/run.sh" ]]; then
    echo "[CRITICAL] $name sem run.sh executavel"
  fi

  if recent_log_has_error "$(log_file "$name")"; then
    echo "[WARN] $name tem erro recente no log"
  fi

  if [[ "$profile" == "flutter" || "$profile" == "android" ]]; then
    command_exists flutter || echo "[WARN] $name profile=$profile mas flutter nao esta no PATH"
    command_exists java || echo "[WARN] $name profile=$profile mas java nao esta no PATH"
  fi
}

list_runners() {
  local i
  for i in "${!RUNNER_NAMES[@]}"; do
    echo "${RUNNER_NAMES[$i]} -> ${RUNNER_PATHS[$i]} profile=${RUNNER_PROFILES[$i]} repo=${RUNNER_REPOS[$i]:-n/a} enabled=${RUNNER_ENABLED[$i]}"
  done
}

ACTION="${1:-status}"
TARGET="${2:-all}"

if [[ "$ACTION" == "help" || "$ACTION" == "-h" || "$ACTION" == "--help" ]]; then
  usage
  exit 0
fi

case "$ACTION" in
  start|stop|restart|status|list|doctor|health|logs) ;;
  *) die "acao desconhecida: $ACTION" ;;
esac

read_config

if [[ "$ACTION" == "list" ]]; then
  list_runners
  exit 0
fi

mapfile -t indexes < <(target_indexes "$TARGET")

case "$ACTION" in
  start)
    for i in "${indexes[@]}"; do
      start_runner "${RUNNER_NAMES[$i]}" "${RUNNER_PATHS[$i]}" "${RUNNER_PROFILES[$i]}" "${RUNNER_REPOS[$i]}" "${RUNNER_ENABLED[$i]}"
    done
    ;;
  stop)
    for i in "${indexes[@]}"; do
      stop_runner "${RUNNER_NAMES[$i]}" "${RUNNER_PATHS[$i]}"
    done
    ;;
  restart)
    for i in "${indexes[@]}"; do
      stop_runner "${RUNNER_NAMES[$i]}" "${RUNNER_PATHS[$i]}"
      start_runner "${RUNNER_NAMES[$i]}" "${RUNNER_PATHS[$i]}" "${RUNNER_PROFILES[$i]}" "${RUNNER_REPOS[$i]}" "${RUNNER_ENABLED[$i]}"
    done
    ;;
  status)
    for i in "${indexes[@]}"; do
      status_runner "${RUNNER_NAMES[$i]}" "${RUNNER_PATHS[$i]}" "${RUNNER_PROFILES[$i]}" "${RUNNER_REPOS[$i]}" "${RUNNER_ENABLED[$i]}"
    done
    ;;
  doctor)
    exit_code=0
    for i in "${indexes[@]}"; do
      doctor_runner "${RUNNER_NAMES[$i]}" "${RUNNER_PATHS[$i]}" "${RUNNER_PROFILES[$i]}" "${RUNNER_REPOS[$i]}" "${RUNNER_ENABLED[$i]}" || exit_code=1
    done
    exit "$exit_code"
    ;;
  health)
    for i in "${indexes[@]}"; do
      health_runner "${RUNNER_NAMES[$i]}" "${RUNNER_PATHS[$i]}" "${RUNNER_PROFILES[$i]}" "${RUNNER_REPOS[$i]}" "${RUNNER_ENABLED[$i]}"
    done
    ;;
  logs)
    for i in "${indexes[@]}"; do
      echo "${RUNNER_NAMES[$i]} -> $(log_file "${RUNNER_NAMES[$i]}")"
    done
    ;;
esac
