#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_ENV_PATH="$BASE_DIR/runner-cache-env.sh"
DRY_RUN=0
OLDER_THAN_DAYS=30
CACHE_PROFILE="shared"

usage() {
  cat <<'EOF'
Uso:
  ./cache.sh <acao> [alvo] [opcoes]

Acoes:
  status      mostra tamanho de caches conhecidos
  doctor      valida variaveis e diretorios de cache
  clean       limpa cache por alvo e idade
  profiles    lista perfis/stacks com cache criado
  help        mostra ajuda

Alvos:
  all, npm, pnpm, yarn, gradle, maven, pip, pub, cargo, go, dotnet, nuget, playwright, tool-cache, logs

Opcoes:
  --profile NAME    profile/stack a inspecionar: shared, node, python, flutter, android, java...
  --older-than N    limpa arquivos com mais de N dias (default: 30)
  --dry-run         mostra o que seria removido sem apagar

Exemplos:
  ./cache.sh status --profile flutter
  ./cache.sh status --profile node
  ./cache.sh profiles
  ./cache.sh doctor --profile python
  ./cache.sh clean all --profile flutter --older-than 30 --dry-run
  ./cache.sh clean logs --older-than 14
EOF
}

die() {
  echo "ERRO: $*" >&2
  exit 1
}

normalize_profile() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._-' '-'
}

source_cache_env() {
  [[ -f "$CACHE_ENV_PATH" ]] || die "runner-cache-env.sh nao encontrado: $CACHE_ENV_PATH"
  export RUNNER_CACHE_PROFILE="$(normalize_profile "$CACHE_PROFILE")"
  export LOCAL_RUNNER_PROFILE="$RUNNER_CACHE_PROFILE"
  # shellcheck source=/dev/null
  source "$CACHE_ENV_PATH"
}

human_size() {
  local path="$1"
  if [[ -e "$path" ]]; then
    du -sh "$path" 2>/dev/null | awk '{print $1}'
  else
    echo "0"
  fi
}

cache_path() {
  case "$1" in
    npm) echo "$npm_config_cache" ;;
    pnpm) echo "$PNPM_STORE_PATH" ;;
    yarn) echo "$YARN_CACHE_FOLDER" ;;
    gradle) echo "$GRADLE_USER_HOME" ;;
    maven) echo "$RUNNER_STACK_CACHE_ROOT/maven/repository" ;;
    pip) echo "$PIP_CACHE_DIR" ;;
    pub) echo "$PUB_CACHE" ;;
    cargo) echo "$CARGO_HOME" ;;
    go) echo "$GOMODCACHE" ;;
    dotnet) echo "$DOTNET_CLI_HOME" ;;
    nuget) echo "$NUGET_PACKAGES" ;;
    playwright) echo "$PLAYWRIGHT_BROWSERS_PATH" ;;
    tool-cache) echo "$RUNNER_TOOL_CACHE" ;;
    logs) echo "$BASE_DIR/.runner-logs" ;;
    *) return 1 ;;
  esac
}

all_targets() {
  echo "tool-cache npm pnpm yarn gradle maven pip pub cargo go dotnet nuget playwright logs"
}

print_profiles() {
  local stacks_dir="$RUNNER_CACHE_ROOT/stacks"
  echo "Cache root: $RUNNER_CACHE_ROOT"
  echo "Tools:      $RUNNER_TOOLS_CACHE_ROOT"
  echo "Shared:     $RUNNER_SHARED_CACHE_ROOT"
  echo
  echo "Profiles:"

  if [[ -d "$stacks_dir" ]]; then
    find "$stacks_dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
  else
    echo "(nenhum profile criado ainda)"
  fi
}

print_status() {
  local target path
  echo "Profile: $RUNNER_CACHE_PROFILE"
  echo "Stack:   $RUNNER_STACK_CACHE_ROOT"
  echo "Tools:   $RUNNER_TOOL_CACHE"
  echo
  printf '%-14s %10s %s\n' "cache" "size" "path"
  printf '%-14s %10s %s\n' "-----" "----" "----"

  for target in $(all_targets); do
    path="$(cache_path "$target")"
    printf '%-14s %10s %s\n' "$target" "$(human_size "$path")" "$path"
  done

  printf '\n%-14s %10s %s\n' "STACK" "$(human_size "$RUNNER_STACK_CACHE_ROOT")" "$RUNNER_STACK_CACHE_ROOT"
  printf '%-14s %10s %s\n' "TOOLS" "$(human_size "$RUNNER_TOOLS_CACHE_ROOT")" "$RUNNER_TOOLS_CACHE_ROOT"
  printf '%-14s %10s %s\n' "TOTAL" "$(human_size "$RUNNER_CACHE_ROOT")" "$RUNNER_CACHE_ROOT"
}

doctor() {
  echo "RUNNER_CACHE_ROOT=$RUNNER_CACHE_ROOT"
  echo "RUNNER_CACHE_PROFILE=$RUNNER_CACHE_PROFILE"
  echo "RUNNER_STACK_CACHE_ROOT=$RUNNER_STACK_CACHE_ROOT"
  echo "RUNNER_TOOLS_CACHE_ROOT=$RUNNER_TOOLS_CACHE_ROOT"
  echo "RUNNER_TOOL_CACHE=$RUNNER_TOOL_CACHE"
  echo "AGENT_TOOLSDIRECTORY=$AGENT_TOOLSDIRECTORY"
  echo "XDG_CACHE_HOME=$XDG_CACHE_HOME"
  echo

  for target in $(all_targets); do
    path="$(cache_path "$target")"
    if [[ -d "$path" ]]; then
      echo "[OK] $target -> $path"
    else
      echo "[WARN] $target nao existe ainda -> $path"
    fi
  done
}

clean_target() {
  local target="$1"
  local path

  path="$(cache_path "$target")" || die "alvo desconhecido: $target"

  if [[ ! -d "$path" ]]; then
    echo "[SKIP] $target nao existe: $path"
    return 0
  fi

  echo "[CLEAN] $target profile=${RUNNER_CACHE_PROFILE} older-than=${OLDER_THAN_DAYS}d path=$path dry-run=$DRY_RUN"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    find "$path" -type f -mtime "+$OLDER_THAN_DAYS" -print
  else
    find "$path" -type f -mtime "+$OLDER_THAN_DAYS" -delete
    find "$path" -type d -empty -delete 2>/dev/null || true
  fi
}

ACTION="${1:-status}"
TARGET="all"

if [[ $# -gt 0 ]]; then
  shift
fi

if [[ $# -gt 0 && "$1" != --* ]]; then
  TARGET="$1"
  shift
fi

while (($#)); do
  case "$1" in
    --profile)
      CACHE_PROFILE="${2:-}"
      [[ -n "$CACHE_PROFILE" ]] || die "--profile exige valor"
      shift 2
      ;;
    --older-than)
      OLDER_THAN_DAYS="${2:-}"
      [[ "$OLDER_THAN_DAYS" =~ ^[0-9]+$ ]] || die "--older-than exige numero de dias"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "opcao desconhecida: $1"
      ;;
  esac
done

if [[ "$ACTION" == "help" || "$ACTION" == "-h" || "$ACTION" == "--help" ]]; then
  usage
  exit 0
fi

source_cache_env

case "$ACTION" in
  status)
    print_status
    ;;
  profiles)
    print_profiles
    ;;
  doctor)
    doctor
    ;;
  clean)
    if [[ "$TARGET" == "all" ]]; then
      for target in $(all_targets); do
        clean_target "$target"
      done
    else
      clean_target "$TARGET"
    fi
    ;;
  *)
    die "acao desconhecida: $ACTION"
    ;;
esac
