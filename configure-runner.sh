#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITHUB_LINE=""
NAME=""
LABELS="local-runner"
RUNNER_TAR="actions-runner-linux-x64-2.335.1.tar.gz"
EXPECTED_SHA256="4ef2f25285f0ae4477f1fe1e346db76d2f3ebf03824e2ddd1973a2819bf6c8cf"
WORK_FOLDER="_work"
REPLACE=0

usage() {
  cat <<'EOF'
Uso:
  ./configure-runner.sh --github-line "<./config.sh --url ... --token ...>" [opcoes]

Opcoes:
  --github-line VALUE   linha copiada do GitHub com --url e --token
  --name VALUE          nome local do runner/pasta
  --labels VALUE        labels do runner
  --base-dir VALUE      diretorio base dos runners
  --runner-tar VALUE    arquivo .tar.gz do GitHub Actions Runner
  --expected-sha256 V   checksum esperado do tarball
  --work-folder VALUE   pasta de work do runner
  --replace             recria runner existente e usa --replace no config.sh
  -h, --help            mostra ajuda
EOF
}

die() {
  echo "ERRO: $*" >&2
  exit 1
}

step() {
  printf '\n==> %s\n' "$1"
}

repo_name() {
  local repo_url="${1%/}"
  basename "$repo_url" | tr '[:upper:]' '[:lower:]'
}

get_arg_value() {
  local key="$1"
  shift

  while (($#)); do
    if [[ "$1" == "$key" && $# -ge 2 ]]; then
      printf '%s\n' "$2"
      return 0
    fi
    shift
  done

  return 1
}

update_runners_conf() {
  local config_path="$1"
  local runner_name="$2"
  local runner_dir="$3"
  local tmp

  mkdir -p "$(dirname "$config_path")"
  [[ -f "$config_path" ]] || printf '# name|path\n' > "$config_path"

  tmp="$(mktemp)"
  awk -F '|' -v runner_name="$runner_name" '$1 != runner_name' "$config_path" > "$tmp"
  printf '%s|%s\n' "$runner_name" "$runner_dir" >> "$tmp"
  mv "$tmp" "$config_path"
}

while (($#)); do
  case "$1" in
    --github-line)
      GITHUB_LINE="${2:-}"
      shift 2
      ;;
    --name)
      NAME="${2:-}"
      shift 2
      ;;
    --labels)
      LABELS="${2:-}"
      shift 2
      ;;
    --base-dir)
      BASE_DIR="${2:-}"
      shift 2
      ;;
    --runner-tar)
      RUNNER_TAR="${2:-}"
      shift 2
      ;;
    --expected-sha256)
      EXPECTED_SHA256="${2:-}"
      shift 2
      ;;
    --work-folder)
      WORK_FOLDER="${2:-}"
      shift 2
      ;;
    --replace)
      REPLACE=1
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

[[ -n "$GITHUB_LINE" ]] || die "--github-line e obrigatorio"

step "Lendo linha copiada do GitHub"

clean_line="${GITHUB_LINE#"${GITHUB_LINE%%[![:space:]]*}"}"
clean_line="${clean_line#./config.sh }"
clean_line="${clean_line#config.sh }"

read -r -a parts <<< "$clean_line"
REPO_URL="$(get_arg_value --url "${parts[@]}" || true)"
TOKEN="$(get_arg_value --token "${parts[@]}" || true)"

[[ -n "$REPO_URL" ]] || die "nao encontrei --url na linha informada"
[[ -n "$TOKEN" ]] || die "nao encontrei --token na linha informada"

[[ -n "$NAME" ]] || NAME="$(repo_name "$REPO_URL")"

BASE_DIR="$(realpath -m "$BASE_DIR")"
TAR_PATH="$BASE_DIR/$RUNNER_TAR"
RUNNER_DIR="$BASE_DIR/$NAME"
CONFIG_PATH="$BASE_DIR/runners.conf"
MACHINE_NAME="$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)"
MACHINE_NAME="${MACHINE_NAME//[[:space:]]/-}"
[[ -n "$MACHINE_NAME" ]] || die "nao foi possivel identificar o nome da maquina"
RUNNER_GITHUB_NAME="$MACHINE_NAME-$NAME"

echo "Repo: $REPO_URL"
echo "Runner local: $NAME"
echo "Pasta: $RUNNER_DIR"
echo "Tarball: $TAR_PATH"
echo "Token: ****"

step "Validando tarball Linux"

[[ -f "$TAR_PATH" ]] || die "tarball nao encontrado em: $TAR_PATH"
actual_sha="$(sha256sum "$TAR_PATH" | awk '{print $1}')"
[[ "${actual_sha,,}" == "${EXPECTED_SHA256,,}" ]] || die "checksum diferente. esperado: $EXPECTED_SHA256 | obtido: $actual_sha"
echo "Checksum OK"

step "Criando pasta do runner"

mkdir -p "$BASE_DIR"
if [[ -d "$RUNNER_DIR" && "$REPLACE" -eq 1 ]]; then
  echo "Removendo pasta existente: $RUNNER_DIR"
  rm -rf "$RUNNER_DIR"
fi
mkdir -p "$RUNNER_DIR"

step "Extraindo tarball"

if [[ -x "$RUNNER_DIR/config.sh" ]]; then
  echo "Runner ja esta extraido em: $RUNNER_DIR"
else
  tar -xzf "$TAR_PATH" -C "$RUNNER_DIR"
  [[ -x "$RUNNER_DIR/config.sh" ]] || die "extracao falhou: config.sh nao encontrado em $RUNNER_DIR"
  echo "Extraido com sucesso em: $RUNNER_DIR"
fi

step "Atualizando runners.conf"

update_runners_conf "$CONFIG_PATH" "$NAME" "$RUNNER_DIR"
echo "Atualizado: $CONFIG_PATH"
echo "$NAME|$RUNNER_DIR"

step "Executando config.sh"

args=(
  --url "$REPO_URL"
  --token "$TOKEN"
  --name "$RUNNER_GITHUB_NAME"
  --labels "$LABELS"
  --work "$WORK_FOLDER"
  --unattended
)

if [[ "$REPLACE" -eq 1 ]]; then
  args+=(--replace)
fi

(cd "$RUNNER_DIR" && ./config.sh "${args[@]}")

step "Pronto"

echo "Runner configurado com sucesso."
echo "Nome no GitHub: $RUNNER_GITHUB_NAME"
echo "Labels: $LABELS"
echo
echo "Para subir esse runner:"
echo "  cd $BASE_DIR"
echo "  ./runners.sh start $NAME"
