#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${RUNNERS_CONFIG:-$BASE_DIR/runners.conf}"
CACHE_ENV_PATH="$BASE_DIR/runner-cache-env.sh"
SERVICE_ENV_DIR="$BASE_DIR/.runner-service-env"
SERVICE_LOG_LINES="${RUNNER_SERVICE_LOG_LINES:-200}"
SERVICE_USER="${RUNNER_SERVICE_USER:-${SUDO_USER:-$USER}}"

usage() {
  cat <<'USAGE'
Uso:
  ./runner-services.sh <acao> [runner|group:<grupo>|all]

Acoes:
  list       mostra estado de migracao e unit systemd
  install    instala o runner como servico, sem iniciar
  migrate    para o modo legado, instala o servico e inicia
  uninstall  para e remove o servico (nao remove o runner do GitHub)
  start      inicia servico(s)
  stop       para servico(s)
  restart    reinicia servico(s)
  status     mostra status resumido
  logs       mostra logs via journalctl
  doctor     valida systemd, svc.sh, .runner e cache env
  help       mostra ajuda

Exemplos:
  ./runner-services.sh doctor all
  ./runner-services.sh migrate agentsorchnext-2
  ./runner-services.sh migrate group:agentsorch
  ./runner-services.sh status all
  ./runner-services.sh logs agentsorchnext-2

Variaveis:
  RUNNER_SERVICE_USER       usuario do servico (default: usuario atual/SUDO_USER)
  RUNNER_SERVICE_LOG_LINES  linhas de journalctl (default: 200)
USAGE
}

die() {
  echo "ERRO: $*" >&2
  exit 1
}

info() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
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

require_systemd() {
  command -v systemctl >/dev/null 2>&1 || die "systemctl nao encontrado"
  [[ -d /run/systemd/system ]] || die "systemd nao esta ativo. No WSL, habilite systemd antes de migrar runners."
}

require_sudo() {
  command -v sudo >/dev/null 2>&1 || die "sudo nao encontrado"
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
    local line name path profile repo enabled group
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
  local group_target i matched=0

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

service_unit() {
  local path="$1"
  local service_file="$path/.service"
  [[ -f "$service_file" ]] || return 1
  tr -d '[:space:]' < "$service_file"
}

service_installed() {
  local path="$1"
  [[ -n "$(service_unit "$path" 2>/dev/null || true)" ]]
}

service_active() {
  local unit="$1"
  systemctl is-active --quiet "$unit" 2>/dev/null
}

escape_env_value() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

write_service_env() {
  local name="$1"
  local profile="$2"
  local repo="$3"
  local group="$4"
  local env_file="$SERVICE_ENV_DIR/$name.env"
  local tmp
  local -a keys=(
    RUNNER_CACHE_ROOT RUNNER_CACHE_PROFILE RUNNER_SHARED_CACHE_ROOT
    RUNNER_STACK_CACHE_ROOT RUNNER_TOOLS_CACHE_ROOT XDG_CACHE_HOME
    RUNNER_TOOL_CACHE AGENT_TOOLSDIRECTORY npm_config_cache NPM_CONFIG_CACHE
    npm_config_prefix NPM_CONFIG_PREFIX npm_config_prefer_offline
    NPM_CONFIG_PREFER_OFFLINE npm_config_audit NPM_CONFIG_AUDIT
    npm_config_fund NPM_CONFIG_FUND COREPACK_HOME PNPM_HOME PNPM_STORE_PATH
    YARN_CACHE_FOLDER GRADLE_USER_HOME MAVEN_OPTS PIP_CACHE_DIR PIPX_HOME
    PIPX_BIN_DIR PUB_CACHE CARGO_HOME GOPATH GOMODCACHE GOCACHE
    DOTNET_CLI_HOME NUGET_PACKAGES COMPOSER_CACHE_DIR PLAYWRIGHT_BROWSERS_PATH
  )

  [[ -f "$CACHE_ENV_PATH" ]] || return 0
  mkdir -p "$SERVICE_ENV_DIR"
  tmp="$(mktemp)"

  (
    export LOCAL_RUNNER_NAME="$name"
    export LOCAL_RUNNER_PROFILE="$profile"
    export LOCAL_RUNNER_REPO="$repo"
    export LOCAL_RUNNER_GROUP="$group"
    # shellcheck source=/dev/null
    source "$CACHE_ENV_PATH"

    local key value
    for key in "${keys[@]}"; do
      value="${!key:-}"
      [[ -n "$value" ]] || continue
      printf '%s="%s"\n' "$key" "$(escape_env_value "$value")"
    done
  ) > "$tmp"

  install -m 0600 "$tmp" "$env_file"
  rm -f "$tmp"
  printf '%s\n' "$env_file"
}

install_env_dropin() {
  local name="$1"
  local path="$2"
  local profile="$3"
  local repo="$4"
  local group="$5"
  local unit env_file dropin_dir tmp

  unit="$(service_unit "$path")"
  env_file="$(write_service_env "$name" "$profile" "$repo" "$group" || true)"
  [[ -n "$env_file" ]] || return 0

  dropin_dir="/etc/systemd/system/$unit.d"
  tmp="$(mktemp)"
  cat > "$tmp" <<EOF
[Service]
EnvironmentFile=$env_file
EOF

  sudo mkdir -p "$dropin_dir"
  sudo install -m 0644 "$tmp" "$dropin_dir/10-actions-runners-cache.conf"
  rm -f "$tmp"
  sudo systemctl daemon-reload
}

install_runner_service() {
  local name="$1"
  local path="$2"
  local profile="$3"
  local repo="$4"
  local enabled="$5"
  local group="$6"
  local unit

  [[ "$enabled" == "true" ]] || {
    info "[SKIP] $name desabilitado no runners.conf"
    return 0
  }

  [[ -d "$path" ]] || die "$name: diretorio nao encontrado: $path"
  [[ -x "$path/svc.sh" ]] || die "$name: svc.sh nao encontrado/executavel em $path"
  [[ -f "$path/.runner" ]] || die "$name: runner nao parece registrado (.runner ausente)"

  if service_installed "$path"; then
    unit="$(service_unit "$path")"
    info "[OK] $name ja possui servico $unit"
  else
    info "Instalando $name como servico para usuario '$SERVICE_USER'"
    (cd "$path" && sudo ./svc.sh install "$SERVICE_USER")
    unit="$(service_unit "$path" || true)"
    [[ -n "$unit" ]] || die "$name: svc.sh concluiu, mas .service nao foi criado"
  fi

  install_env_dropin "$name" "$path" "$profile" "$repo" "$group"
  info "[OK] $name -> $unit"
}

stop_legacy_runner() {
  local name="$1"
  if [[ -x "$BASE_DIR/runners.sh" ]]; then
    info "Parando processo legado de $name antes da migracao"
    "$BASE_DIR/runners.sh" stop "$name" || true
  fi
}

migrate_runner() {
  local name="$1" path="$2" profile="$3" repo="$4" enabled="$5" group="$6"
  local unit

  stop_legacy_runner "$name"
  install_runner_service "$name" "$path" "$profile" "$repo" "$enabled" "$group"
  unit="$(service_unit "$path")"
  sudo systemctl enable "$unit" >/dev/null
  sudo systemctl start "$unit"

  if service_active "$unit"; then
    info "[OK] $name migrado e ativo ($unit)"
  else
    sudo systemctl status "$unit" --no-pager || true
    die "$name: servico instalado, mas nao ficou ativo"
  fi
}

uninstall_runner_service() {
  local name="$1" path="$2"
  local unit
  unit="$(service_unit "$path" 2>/dev/null || true)"
  if [[ -z "$unit" ]]; then
    info "[SKIP] $name ainda nao possui servico"
    return 0
  fi

  sudo systemctl stop "$unit" 2>/dev/null || true
  sudo systemctl disable "$unit" 2>/dev/null || true
  (cd "$path" && sudo ./svc.sh uninstall)
  rm -f "$SERVICE_ENV_DIR/$name.env"
  info "[OK] $name removido do systemd; registro GitHub preservado"
}

operate_runner() {
  local action="$1" name="$2" path="$3"
  local unit
  unit="$(service_unit "$path" 2>/dev/null || true)"
  [[ -n "$unit" ]] || die "$name: ainda nao migrado. Use './runner-services.sh migrate $name'"

  case "$action" in
    start)
      sudo systemctl start "$unit"
      ;;
    stop)
      sudo systemctl stop "$unit"
      ;;
    restart)
      sudo systemctl restart "$unit"
      ;;
    status)
      printf '%-24s %-12s %-8s %s\n' "$name" "$(systemctl is-active "$unit" 2>/dev/null || true)" "$(systemctl is-enabled "$unit" 2>/dev/null || true)" "$unit"
      ;;
    logs)
      sudo journalctl -u "$unit" -n "$SERVICE_LOG_LINES" --no-pager
      ;;
    *)
      die "acao de servico desconhecida: $action"
      ;;
  esac
}

list_runner() {
  local name="$1" path="$2" profile="$3" repo="$4" enabled="$5" group="$6"
  local unit="-" active="legacy"
  if service_installed "$path"; then
    unit="$(service_unit "$path")"
    active="$(systemctl is-active "$unit" 2>/dev/null || true)"
  fi
  printf '%-24s %-12s %-12s %-8s %-14s %s\n' "$name" "$group" "$profile" "$enabled" "$active" "$unit"
}

doctor_runner() {
  local name="$1" path="$2"
  local errors=0 unit

  printf '\n[%s]\n' "$name"
  if [[ -d "$path" ]]; then
    echo "  OK dir: $path"
  else
    echo "  ERRO dir ausente: $path"
    errors=$((errors + 1))
  fi

  if [[ -x "$path/svc.sh" ]]; then
    echo "  OK svc.sh"
  else
    echo "  ERRO svc.sh ausente"
    errors=$((errors + 1))
  fi

  if [[ -f "$path/.runner" ]]; then
    echo "  OK registro .runner"
  else
    echo "  ERRO .runner ausente"
    errors=$((errors + 1))
  fi

  unit="$(service_unit "$path" 2>/dev/null || true)"
  if [[ -n "$unit" ]]; then
    echo "  OK systemd: $unit ($(systemctl is-active "$unit" 2>/dev/null || true))"
  else
    echo "  INFO ainda em modo legado"
  fi

  return "$errors"
}

main() {
  local action="${1:-help}"
  local target="${2:-all}"
  local i name path profile repo enabled group
  local failures=0

  case "$action" in
    help|-h|--help)
      usage
      return 0
      ;;
    list|install|migrate|uninstall|start|stop|restart|status|logs|doctor)
      ;;
    *)
      usage
      die "acao desconhecida: $action"
      ;;
  esac

  read_config
  require_systemd

  if [[ "$action" != "list" && "$action" != "doctor" && "$action" != "status" ]]; then
    require_sudo
  fi

  if [[ "$action" == "list" ]]; then
    printf '%-24s %-12s %-12s %-8s %-14s %s\n' "RUNNER" "GROUP" "PROFILE" "ENABLED" "STATE" "SYSTEMD UNIT"
  fi

  while IFS= read -r i; do
    [[ -n "$i" ]] || continue
    name="${RUNNER_NAMES[$i]}"
    path="${RUNNER_PATHS[$i]}"
    profile="${RUNNER_PROFILES[$i]}"
    repo="${RUNNER_REPOS[$i]}"
    enabled="${RUNNER_ENABLED[$i]}"
    group="${RUNNER_GROUPS[$i]}"

    case "$action" in
      list)
        list_runner "$name" "$path" "$profile" "$repo" "$enabled" "$group"
        ;;
      install)
        install_runner_service "$name" "$path" "$profile" "$repo" "$enabled" "$group"
        ;;
      migrate)
        migrate_runner "$name" "$path" "$profile" "$repo" "$enabled" "$group"
        ;;
      uninstall)
        uninstall_runner_service "$name" "$path"
        ;;
      start|stop|restart|status|logs)
        operate_runner "$action" "$name" "$path"
        ;;
      doctor)
        doctor_runner "$name" "$path" || failures=$((failures + 1))
        ;;
    esac
  done < <(target_indexes "$target")

  if [[ "$failures" -gt 0 ]]; then
    die "$failures runner(s) com problema"
  fi
}

main "$@"
