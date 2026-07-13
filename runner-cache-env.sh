#!/usr/bin/env bash

# Shared cache locations for self-hosted runner jobs.
#
# The runner workspace (_work) stays disposable and isolated per runner.
# Durable caches live outside _work under .runner-cache, with:
# - shared tool caches used by setup actions;
# - stack/profile caches used by package managers and build tools.

CACHE_ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER_CACHE_ROOT="${RUNNER_CACHE_ROOT:-$CACHE_ENV_DIR/.runner-cache}"

profile_raw="${LOCAL_RUNNER_PROFILE:-${RUNNER_CACHE_PROFILE:-shared}}"
RUNNER_CACHE_PROFILE="$(printf '%s' "$profile_raw" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._-' '-')"
[[ -n "$RUNNER_CACHE_PROFILE" ]] || RUNNER_CACHE_PROFILE="shared"

RUNNER_SHARED_CACHE_ROOT="${RUNNER_SHARED_CACHE_ROOT:-$RUNNER_CACHE_ROOT/shared}"
RUNNER_STACK_CACHE_ROOT="${RUNNER_STACK_CACHE_ROOT:-$RUNNER_CACHE_ROOT/stacks/$RUNNER_CACHE_PROFILE}"
RUNNER_TOOLS_CACHE_ROOT="${RUNNER_TOOLS_CACHE_ROOT:-$RUNNER_CACHE_ROOT/tools}"

export RUNNER_CACHE_ROOT
export RUNNER_CACHE_PROFILE
export RUNNER_SHARED_CACHE_ROOT
export RUNNER_STACK_CACHE_ROOT
export RUNNER_TOOLS_CACHE_ROOT

export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$RUNNER_STACK_CACHE_ROOT/xdg}"
export RUNNER_TOOL_CACHE="${RUNNER_TOOL_CACHE:-$RUNNER_TOOLS_CACHE_ROOT/tool-cache}"
export AGENT_TOOLSDIRECTORY="${AGENT_TOOLSDIRECTORY:-$RUNNER_TOOL_CACHE}"

export npm_config_cache="${npm_config_cache:-$RUNNER_STACK_CACHE_ROOT/npm}"
export NPM_CONFIG_CACHE="${NPM_CONFIG_CACHE:-$npm_config_cache}"
export COREPACK_HOME="${COREPACK_HOME:-$RUNNER_STACK_CACHE_ROOT/corepack}"
export PNPM_HOME="${PNPM_HOME:-$RUNNER_STACK_CACHE_ROOT/pnpm/home}"
export PNPM_STORE_PATH="${PNPM_STORE_PATH:-$RUNNER_STACK_CACHE_ROOT/pnpm/store}"
export YARN_CACHE_FOLDER="${YARN_CACHE_FOLDER:-$RUNNER_STACK_CACHE_ROOT/yarn}"

export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$RUNNER_STACK_CACHE_ROOT/gradle}"
export MAVEN_OPTS="${MAVEN_OPTS:-} -Dmaven.repo.local=$RUNNER_STACK_CACHE_ROOT/maven/repository"
export PIP_CACHE_DIR="${PIP_CACHE_DIR:-$RUNNER_STACK_CACHE_ROOT/pip}"
export PIPX_HOME="${PIPX_HOME:-$RUNNER_STACK_CACHE_ROOT/pipx/home}"
export PIPX_BIN_DIR="${PIPX_BIN_DIR:-$RUNNER_STACK_CACHE_ROOT/pipx/bin}"

export PUB_CACHE="${PUB_CACHE:-$RUNNER_STACK_CACHE_ROOT/pub}"
export CARGO_HOME="${CARGO_HOME:-$RUNNER_STACK_CACHE_ROOT/cargo}"
export GOPATH="${GOPATH:-$RUNNER_STACK_CACHE_ROOT/go}"
export GOMODCACHE="${GOMODCACHE:-$GOPATH/pkg/mod}"
export GOCACHE="${GOCACHE:-$RUNNER_STACK_CACHE_ROOT/go-build}"
export DOTNET_CLI_HOME="${DOTNET_CLI_HOME:-$RUNNER_STACK_CACHE_ROOT/dotnet}"
export NUGET_PACKAGES="${NUGET_PACKAGES:-$RUNNER_STACK_CACHE_ROOT/nuget/packages}"
export COMPOSER_CACHE_DIR="${COMPOSER_CACHE_DIR:-$RUNNER_STACK_CACHE_ROOT/composer}"
export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-$RUNNER_STACK_CACHE_ROOT/playwright}"

# WSL can leak Windows PATH entries into Linux runner jobs and slow command lookup
# or accidentally select .exe tools. Keep strict Linux PATH by default, but allow
# opt-out with RUNNER_STRICT_LINUX_PATH=0.
if [[ "${RUNNER_STRICT_LINUX_PATH:-1}" == "1" ]]; then
  cleaned_path=""
  old_ifs="$IFS"
  IFS=":"
  for path_entry in $PATH; do
    case "$path_entry" in
      /mnt/c/*|*.exe/*) continue ;;
    esac

    if [[ -z "$cleaned_path" ]]; then
      cleaned_path="$path_entry"
    else
      cleaned_path="$cleaned_path:$path_entry"
    fi
  done
  IFS="$old_ifs"
  export PATH="$cleaned_path"
fi

for extra_path in "$PNPM_HOME" "$PIPX_BIN_DIR" "$CARGO_HOME/bin" "$GOPATH/bin"; do
  case ":$PATH:" in
    *":$extra_path:"*) ;;
    *) export PATH="$extra_path:$PATH" ;;
  esac
done

mkdir -p \
  "$RUNNER_CACHE_ROOT" \
  "$RUNNER_SHARED_CACHE_ROOT" \
  "$RUNNER_STACK_CACHE_ROOT" \
  "$RUNNER_TOOLS_CACHE_ROOT" \
  "$XDG_CACHE_HOME" \
  "$RUNNER_TOOL_CACHE" \
  "$npm_config_cache" \
  "$COREPACK_HOME" \
  "$PNPM_HOME" \
  "$PNPM_STORE_PATH" \
  "$YARN_CACHE_FOLDER" \
  "$GRADLE_USER_HOME" \
  "$RUNNER_STACK_CACHE_ROOT/maven/repository" \
  "$PIP_CACHE_DIR" \
  "$PIPX_HOME" \
  "$PIPX_BIN_DIR" \
  "$PUB_CACHE" \
  "$CARGO_HOME" \
  "$GOMODCACHE" \
  "$GOCACHE" \
  "$DOTNET_CLI_HOME" \
  "$NUGET_PACKAGES" \
  "$COMPOSER_CACHE_DIR" \
  "$PLAYWRIGHT_BROWSERS_PATH"
