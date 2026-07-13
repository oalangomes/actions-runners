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
  cat <<'USAGE'
Uso:
  ./runners.sh <acao> [runner|group:<grupo>|all]

Acoes:
  start      inicia runner(s)
  stop       para runner(s)
  restart    reinicia runner(s)
  status     mostra status
  list       lista runners
  groups     lista grupos e capacidade
  doctor     valida estrutura e stack por perfil
  health     mostra alertas locais resumidos
  logs       mostra caminho do log
  help       mostra ajuda

Exemplos:
  ./runners.sh status
  ./runners.sh start all
  ./runners.sh start agentsorch-2
  ./runners.sh start group:neurotrack
  ./runners.sh restart group:agentsorch
  ./runners.sh stop group:ea-fc
  ./runners.sh groups
  ./runners.sh doctor all
  ./runners.sh health group:roboapostas
USAGE
}

die() {
  echo "ERRO: $*" >&2
  exit 1
}

info() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

normalize_slug() {
  local value="${1,,}"
  value="$(printf '%s' "$value" | tr -c 'a-z0-9._-' '-')"
  value="${value#-}"
  value="${value%-}"
  [[ -n "$value" ]] || value="generic"
  printf '%s\n' "$value"
}

infer_group() {
  local name="${1,,}"
  local repo="${2,,}"
  local value="$name,$repo"

  case "$value" in
    *agentsorch*) echo "agentsorch" ;;
    *neurotrack*|*docsneurotrack*) echo "neurotrack" ;;
    *ea-fc*|*sheffield*) echo "ea-fc" ;;
    *roboapostas*|*robo-apostas*|*apostas*) echo "roboapostas" ;;
    *) normalize_slug "${repo##*/}" ;;
  esac
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
  RUNNER_GROUPS=()

  while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    line="${raw_line//$'\r'/}"
    line="$(trim "$line")"

    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
    [[ "$line" == *"|"* ]] || die "linha invalida no runners.conf: $line"

    IFS='|' read -r name path profile repo enabled group _ <<< "$line"
    name="$(trim "${name:-}")"
    path="$(trim "${path:-}")"
    profile="$(trim "${profile:-generic}")"
    repo="$(trim "${repo:-}")"
    enabled="$(trim "${enabled:-true}")"
    group="$(trim "${group:-}")"

    [[ -n "$name" ]] || die "nome de runner vazio no runners.conf"
    [[ -n "$path" ]] || die "path vazio para runner '$name'"

    case "${enabled,,}" in
      true|1|yes|y|sim) enabled="true" ;;
      false|0|no|n|nao|não) enabled="false" ;;
      *) enabled="true" ;;
    esac

    [[ -n "$group" ]] || group="$(infer_group "$name" "$repo")"
    group="$(normalize_slug "$group")"

    RUNNER_NAMES+=("$name")
    RUNNER_PATHS+=("$path")
    RUNNER_PROFILES+=("${profile:-generic}")
    RUNNER_REPOS+=("$repo")
    RUNNER_ENABLED+=("$enabled")
    RUNNER_GROUPS+=("$group")
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
  local group_target
  local i
  local matched=0

  if [[ "$target" == "all" ]]; then
    for i in "${!RUNNER_NAMES[@]}"; do
      printf '%s\n' "$i"
    done
    return 0
  fi

  if [[ "$target" == group:* ]]; then
    group_target="$(normalize_slug "${target#group:}")"
    for i in "${!RUNNER_NAMES[@]}"; do
      if [[ "${RUNNER_GROUPS[$i]}" == "$group_target" ]]; then
        printf '%s\n' "$i"
        matched=1
      fi
    done
    [[ "$matched" -eq 1 ]] || die "grupo desconhecido ou vazio: $group_target"
    return 0
  fi

  runner_index "$target" || die "runner desconhecido: $target"
}

runner_matching_processes() {
  local path="$1"
  [[ -d "$path" ]] || return 0
  pgrep -af "$path" 2>/dev/null || true
}

runner_listener_pids_by_path() {
  local path="$1"
  runner_matching_processes "$path" |
    awk '/Runner\.Listener/ { print $1 }' |
    sort -n -u
}

runner_worker_pids_by_path() {
  local path="$1"
  runner_matching_processes "$path" |
    awk '/Runner\.Worker/ { print $1 }' |
    sort -n -u
}

runner_shell_pids_by_path() {
  local path="$1"
  runner_matching_processes "$path" |
    awk '/(^|[[:space:]])([^[:space:]]*\/)?run\.sh([[:space:]]|$)/ && $0 !~ /Runner\.(Listener|Worker)/ { print $1 }' |
    sort -n -u
}

runner_processes_by_path() {
  local path="$1"
  {
    runner_listener_pids_by_path "$path"
    runner_worker_pids_by_path "$path"
    runner_shell_pids_by_path "$path"
  } | sort -n -u
}

runner_primary_pid_by_path() {
  local path="$1"
  local pid

  pid="$(runner_listener_pids_by_path "$path" | head -n 1)"
  if [[ -n "$pid" ]]; then
    printf '%s\n' "$pid"
    return 0
  fi

  runner_shell_pids_by_path "$path" | head -n 1
}

runner_listener_count_by_path() {
  local path="$1"
  runner_listener_pids_by_path "$path" | awk 'NF { count++ } END { print count+0 }'
}

runner_worker_count_by_path() {
  local path="$1"
  runner_worker_pids_by_path "$path" | awk 'NF { count++ } END { print count+0 }'
}

runner_shell_count_by_path() {
  local path="$1"
  runner_shell_pids_by_path "$path" | awk 'NF { count++ } END { print count+0 }'
}

runner_has_supervisor_by_path() {
  local path="$1"
  [[ -n "$(runner_primary_pid_by_path "$path")" ]]
}

runner_has_process_by_path() {
  local path="$1"
  [[ -n "$(runner_processes_by_path "$path" | head -n 1)" ]]
}

runner_process_summary() {
  local path="$1"
  local listeners workers shells
  listeners="$(runner_listener_pids_by_path "$path" | paste -sd ',' -)"
  workers="$(runner_worker_pids_by_path "$path" | paste -sd ',' -)"
  shells="$(runner_shell_pids_by_path "$path" | paste -sd ',' -)"
  printf 'listener=%s worker=%s shell=%s' "${listeners:-none}" "${workers:-none}" "${shells:-none}"
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
  find "$pages_dir" -mindepth 1 -maxdepth 1 -print -quit | grep -q . || return 0

  archive_dir="$path/_diag/pages.archive.$(date '+%Y%m%d%H%M%S')"
  mkdir -p "$archive_dir"
  find "$pages_dir" -mindepth 1 -maxdepth 1 -exec mv {} "$archive_dir" \;
  echo "[DIAG] _diag/pages arquivado em: $archive_dir"
}

source_cache_env() {
  local name="$1"
  local profile="$2"
  local repo="$3"
  local group="$4"

  if [[ -f "$CACHE_ENV_PATH" ]]; then
    export LOCAL_RUNNER_NAME="$name"
    export LOCAL_RUNNER_PROFILE="$profile"
    export LOCAL_RUNNER_REPO="$repo"
    export LOCAL_RUNNER_GROUP="$group"
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
  local group="$6"
  local run_sh="$path/run.sh"
  local pid
  local file
  local primary_pid
  local listener_count
  local worker_count

  if [[ "$enabled" != "true" ]]; then
    info "[SKIP] $name desabilitado no runners.conf"
    return 0
  fi

  [[ -d "$path" ]] || die "$name: diretorio nao encontrado: $path"
  [[ -x "$run_sh" ]] || die "$name: run.sh nao encontrado ou sem permissao em: $path"

  pid="$(runner_pid "$name" || true)"
  if is_running_pid "$pid"; then
    echo "[OK] $name ja esta rodando (pid $pid; $(runner_process_summary "$path"))"
    return 0
  fi

  listener_count="$(runner_listener_count_by_path "$path")"
  worker_count="$(runner_worker_count_by_path "$path")"
  primary_pid="$(runner_primary_pid_by_path "$path")"

  if [[ "$listener_count" -gt 1 ]]; then
    echo "[ERR] $name possui mais de um Runner.Listener: $(runner_listener_pids_by_path "$path" | paste -sd ' ' -)" >&2
    echo "      use: ./runners.sh restart $name" >&2
    return 1
  fi

  if [[ -n "$primary_pid" ]]; then
    mkdir -p "$PID_DIR"
    echo "$primary_pid" > "$(pid_file "$name")"
    echo "[OK] $name ja esta rodando sem pid file valido; PID recuperado: $primary_pid ($(runner_process_summary "$path"))"
    return 0
  fi

  if [[ "$worker_count" -gt 0 ]]; then
    echo "[ERR] $name possui Runner.Worker sem Listener/supervisor: $(runner_worker_pids_by_path "$path" | paste -sd ' ' -)" >&2
    echo "      use: ./runners.sh restart $name" >&2
    return 1
  fi

  mkdir -p "$PID_DIR" "$LOG_DIR"
  file="$(log_file "$name")"
  rotate_log_if_needed "$file"
  archive_diag_pages "$path"
  source_cache_env "$name" "$profile" "$repo" "$group"

  echo "[START] iniciando $name"
  echo "   group: $group"
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
    export LOCAL_RUNNER_GROUP="$group"
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
  local primary_pid

  pid="$(runner_pid "$name" || true)"
  primary_pid="$(runner_primary_pid_by_path "$path")"

  if ! is_running_pid "$pid" && [[ -z "$primary_pid" ]] && ! runner_has_process_by_path "$path"; then
    echo "[STOP] $name ja esta parado"
    rm -f "$(pid_file "$name")"
    return 0
  fi

  [[ -n "$pid" ]] || pid="$primary_pid"
  echo "[STOP] parando $name${pid:+ (pid $pid)}; $(runner_process_summary "$path")"
  terminate_pid_group "$pid"

  for _ in {1..20}; do
    if ! runner_has_process_by_path "$path"; then
      rm -f "$(pid_file "$name")"
      return 0
    fi
    sleep 0.5
  done

  echo "[STOP] encerrando processos remanescentes de $name"
  kill_runner_processes_by_path "$path"
  sleep 0.5
  if runner_has_process_by_path "$path"; then
    while read -r pid; do
      [[ -n "$pid" ]] && kill -9 "$pid" 2>/dev/null || true
    done < <(runner_processes_by_path "$path")
  fi
  rm -f "$(pid_file "$name")"
}

status_runner() {
  local name="$1"
  local path="$2"
  local profile="$3"
  local repo="$4"
  local enabled="$5"
  local group="$6"
  local pid
  local primary_pid
  local listener_count
  local worker_count

  pid="$(runner_pid "$name" || true)"
  primary_pid="$(runner_primary_pid_by_path "$path")"
  listener_count="$(runner_listener_count_by_path "$path")"
  worker_count="$(runner_worker_count_by_path "$path")"

  if [[ "$enabled" != "true" ]]; then
    echo "[DISABLED] $name group=$group profile=$profile repo=${repo:-n/a} $path"
  elif [[ "$listener_count" -gt 1 ]]; then
    echo "[WARN] $name multiplos listeners=$(runner_listener_pids_by_path "$path" | paste -sd ',' -) workers=$worker_count group=$group profile=$profile repo=${repo:-n/a} $path"
  elif is_running_pid "$pid" || [[ -n "$primary_pid" ]]; then
    echo "[OK] $name rodando pid=${pid:-$primary_pid} $(runner_process_summary "$path") group=$group profile=$profile repo=${repo:-n/a} $path"
  elif [[ "$worker_count" -gt 0 ]]; then
    echo "[WARN] $name worker orfao=$(runner_worker_pids_by_path "$path" | paste -sd ',' -) group=$group profile=$profile repo=${repo:-n/a} $path"
  else
    echo "[STOP] $name parado group=$group profile=$profile repo=${repo:-n/a} $path"
  fi
}

profile_commands() {
  case "$1" in
    node) echo "git node npm" ;;
    python) echo "git python3 pip3" ;;
    flutter|android) echo "git java flutter" ;;
    java) echo "git java" ;;
    dotnet) echo "git dotnet" ;;
    go) echo "git go" ;;
    *) echo "git" ;;
  esac
}

doctor_runner() {
  local name="$1"
  local path="$2"
  local profile="$3"
  local repo="$4"
  local enabled="$5"
  local group="$6"
  local ok=0
  local cmd

  echo
  echo "Runner: $name"
  echo "Group:  $group"
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

  if runner_has_process_by_path "$path"; then
    echo "[OK] processos: $(runner_process_summary "$path")"
  else
    echo "[INFO] nenhum processo ativo detectado para este runner"
  fi

  if [[ -f "$CACHE_ENV_PATH" ]]; then
    echo "[OK] runner-cache-env.sh encontrado"
    source_cache_env "$name" "$profile" "$repo" "$group"
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
  local group="$6"
  local pid
  local listener_count
  local worker_count
  local shell_count
  local primary_pid

  pid="$(runner_pid "$name" || true)"
  listener_count="$(runner_listener_count_by_path "$path")"
  worker_count="$(runner_worker_count_by_path "$path")"
  shell_count="$(runner_shell_count_by_path "$path")"
  primary_pid="$(runner_primary_pid_by_path "$path")"

  if [[ "$enabled" != "true" ]]; then
    echo "[INFO] $name group=$group desabilitado"
    return 0
  fi

  if [[ -f "$(pid_file "$name")" ]] && ! is_running_pid "$pid" && [[ -z "$primary_pid" ]]; then
    echo "[WARN] $name group=$group possui PID stale: $(pid_file "$name")"
  fi
  if [[ "$listener_count" -gt 1 ]]; then
    echo "[CRITICAL] $name tem $listener_count Runner.Listener: $(runner_listener_pids_by_path "$path" | paste -sd ' ' -)"
  fi
  if [[ "$worker_count" -gt 0 && "$listener_count" -eq 0 && "$shell_count" -eq 0 ]]; then
    echo "[CRITICAL] $name tem Runner.Worker sem Listener/supervisor: $(runner_worker_pids_by_path "$path" | paste -sd ' ' -)"
  fi
  if [[ -z "$primary_pid" && "$worker_count" -eq 0 ]]; then
    echo "[WARN] $name group=$group parado"
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
    echo "${RUNNER_NAMES[$i]} -> ${RUNNER_PATHS[$i]} group=${RUNNER_GROUPS[$i]} profile=${RUNNER_PROFILES[$i]} repo=${RUNNER_REPOS[$i]:-n/a} enabled=${RUNNER_ENABLED[$i]}"
  done
}

list_groups() {
  local groups
  local group
  local i
  local total
  local enabled
  local running
  local primary_pid

  groups="$(printf '%s\n' "${RUNNER_GROUPS[@]}" | sort -u)"
  while read -r group; do
    [[ -n "$group" ]] || continue
    total=0
    enabled=0
    running=0
    for i in "${!RUNNER_NAMES[@]}"; do
      [[ "${RUNNER_GROUPS[$i]}" == "$group" ]] || continue
      total=$((total + 1))
      if [[ "${RUNNER_ENABLED[$i]}" == "true" ]]; then
        enabled=$((enabled + 1))
        primary_pid="$(runner_primary_pid_by_path "${RUNNER_PATHS[$i]}")"
        if [[ -n "$primary_pid" ]]; then
          running=$((running + 1))
        fi
      fi
    done
    echo "$group total=$total enabled=$enabled running=$running stopped=$((enabled - running))"
  done <<< "$groups"
}

ACTION="${1:-status}"
TARGET="${2:-all}"

if [[ "$ACTION" == "help" || "$ACTION" == "-h" || "$ACTION" == "--help" ]]; then
  usage
  exit 0
fi

case "$ACTION" in
  start|stop|restart|status|list|groups|doctor|health|logs) ;;
  *) die "acao desconhecida: $ACTION" ;;
esac

read_config

if [[ "$ACTION" == "list" ]]; then
  list_runners
  exit 0
fi
if [[ "$ACTION" == "groups" ]]; then
  list_groups
  exit 0
fi

mapfile -t indexes < <(target_indexes "$TARGET")

case "$ACTION" in
  start)
    for i in "${indexes[@]}"; do
      start_runner "${RUNNER_NAMES[$i]}" "${RUNNER_PATHS[$i]}" "${RUNNER_PROFILES[$i]}" "${RUNNER_REPOS[$i]}" "${RUNNER_ENABLED[$i]}" "${RUNNER_GROUPS[$i]}"
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
      start_runner "${RUNNER_NAMES[$i]}" "${RUNNER_PATHS[$i]}" "${RUNNER_PROFILES[$i]}" "${RUNNER_REPOS[$i]}" "${RUNNER_ENABLED[$i]}" "${RUNNER_GROUPS[$i]}"
    done
    ;;
  status)
    for i in "${indexes[@]}"; do
      status_runner "${RUNNER_NAMES[$i]}" "${RUNNER_PATHS[$i]}" "${RUNNER_PROFILES[$i]}" "${RUNNER_REPOS[$i]}" "${RUNNER_ENABLED[$i]}" "${RUNNER_GROUPS[$i]}"
    done
    ;;
  doctor)
    exit_code=0
    for i in "${indexes[@]}"; do
      doctor_runner "${RUNNER_NAMES[$i]}" "${RUNNER_PATHS[$i]}" "${RUNNER_PROFILES[$i]}" "${RUNNER_REPOS[$i]}" "${RUNNER_ENABLED[$i]}" "${RUNNER_GROUPS[$i]}" || exit_code=1
    done
    exit "$exit_code"
    ;;
  health)
    for i in "${indexes[@]}"; do
      health_runner "${RUNNER_NAMES[$i]}" "${RUNNER_PATHS[$i]}" "${RUNNER_PROFILES[$i]}" "${RUNNER_REPOS[$i]}" "${RUNNER_ENABLED[$i]}" "${RUNNER_GROUPS[$i]}"
    done
    ;;
  logs)
    for i in "${indexes[@]}"; do
      echo "${RUNNER_NAMES[$i]} group=${RUNNER_GROUPS[$i]} -> $(log_file "${RUNNER_NAMES[$i]}")"
    done
    ;;
esac
