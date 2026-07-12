#!/usr/bin/env bash

# Shared cache locations for self-hosted runner jobs.
# These paths live outside each runner's _work folder so dependency downloads
# survive checkouts, cleanups and runner restarts.

RUNNER_CACHE_ROOT="${RUNNER_CACHE_ROOT:-/home/alangomes/actions-runners/.runner-cache}"

export RUNNER_CACHE_ROOT
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$RUNNER_CACHE_ROOT/xdg}"
export RUNNER_TOOL_CACHE="${RUNNER_TOOL_CACHE:-$RUNNER_CACHE_ROOT/tool-cache}"
export AGENT_TOOLSDIRECTORY="${AGENT_TOOLSDIRECTORY:-$RUNNER_TOOL_CACHE}"

export npm_config_cache="${npm_config_cache:-$RUNNER_CACHE_ROOT/npm}"
export NPM_CONFIG_CACHE="${NPM_CONFIG_CACHE:-$npm_config_cache}"
export PNPM_HOME="${PNPM_HOME:-$RUNNER_CACHE_ROOT/pnpm/home}"
export PNPM_STORE_PATH="${PNPM_STORE_PATH:-$RUNNER_CACHE_ROOT/pnpm/store}"
export YARN_CACHE_FOLDER="${YARN_CACHE_FOLDER:-$RUNNER_CACHE_ROOT/yarn}"

export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$RUNNER_CACHE_ROOT/gradle}"
export MAVEN_OPTS="${MAVEN_OPTS:-} -Dmaven.repo.local=$RUNNER_CACHE_ROOT/maven/repository"
export PIP_CACHE_DIR="${PIP_CACHE_DIR:-$RUNNER_CACHE_ROOT/pip}"
export PIPX_HOME="${PIPX_HOME:-$RUNNER_CACHE_ROOT/pipx/home}"
export PIPX_BIN_DIR="${PIPX_BIN_DIR:-$RUNNER_CACHE_ROOT/pipx/bin}"

export PUB_CACHE="${PUB_CACHE:-$RUNNER_CACHE_ROOT/pub}"
export CARGO_HOME="${CARGO_HOME:-$RUNNER_CACHE_ROOT/cargo}"
export GOPATH="${GOPATH:-$RUNNER_CACHE_ROOT/go}"
export GOMODCACHE="${GOMODCACHE:-$GOPATH/pkg/mod}"
export GOCACHE="${GOCACHE:-$RUNNER_CACHE_ROOT/go-build}"
export DOTNET_CLI_HOME="${DOTNET_CLI_HOME:-$RUNNER_CACHE_ROOT/dotnet}"
export NUGET_PACKAGES="${NUGET_PACKAGES:-$RUNNER_CACHE_ROOT/nuget/packages}"

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

case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

case ":$PATH:" in
  *":$PIPX_BIN_DIR:"*) ;;
  *) export PATH="$PIPX_BIN_DIR:$PATH" ;;
esac

mkdir -p \
  "$RUNNER_CACHE_ROOT" \
  "$XDG_CACHE_HOME" \
  "$RUNNER_TOOL_CACHE" \
  "$npm_config_cache" \
  "$PNPM_HOME" \
  "$PNPM_STORE_PATH" \
  "$YARN_CACHE_FOLDER" \
  "$GRADLE_USER_HOME" \
  "$RUNNER_CACHE_ROOT/maven/repository" \
  "$PIP_CACHE_DIR" \
  "$PIPX_HOME" \
  "$PIPX_BIN_DIR" \
  "$PUB_CACHE" \
  "$CARGO_HOME" \
  "$GOMODCACHE" \
  "$GOCACHE" \
  "$DOTNET_CLI_HOME" \
  "$NUGET_PACKAGES"
