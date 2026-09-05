---
name: manage-local-github-runners
description: Manage the user's local GitHub Actions self-hosted runner platform from Codex. Use when the user asks to inspect, start, stop, restart, diagnose, validate, register, create, remove, or configure local runners for personal GitHub repositories, or asks whether a project's runner is healthy/available. Prefer the current repository when no target is specified. Support machine-local runner registries and on-demand systemd operation. Never expose registration tokens or perform destructive removal without explicit user intent.
---

# Manage Local GitHub Runners

Operate the user's shared local GitHub Actions runner installation safely and project-first.

This skill is for **personal/local runner administration**, not for editing GitHub Actions workflows unless the user explicitly asks for workflow changes.

## Platform location

Resolve the central installation in this order:

1. `$ACTIONS_RUNNERS_HOME`
2. `/home/alangomes/actions-runners`

```bash
RUNNERS_HOME="${ACTIONS_RUNNERS_HOME:-/home/alangomes/actions-runners}"
```

If `$RUNNERS_HOME/.env.local` exists, load it before resolving the registry:

```bash
if [[ -f "$RUNNERS_HOME/.env.local" ]]; then
  set -a
  source "$RUNNERS_HOME/.env.local"
  set +a
fi

RUNNERS_CONFIG="${RUNNERS_CONFIG:-$RUNNERS_HOME/runners.conf}"
RUNNER_BOOT_POLICY="${RUNNER_BOOT_POLICY:-on-demand}"
```

Do not assume runner definitions are versioned. Treat `RUNNERS_CONFIG` as machine-local state.

## Default operating model

The preferred policy is:

```text
systemd authority
+ boot disabled
+ runner started on demand
+ only runners needed by a project are started
```

Do not run `start all` unless the user explicitly requests the entire fleet.

When the user asks to work with "the runner" and a current Git repository exists, scope actions to runners mapped to that repository.

## Resolve the current repository

Use:

```bash
remote="$(git remote get-url origin 2>/dev/null || true)"
repo="$remote"
repo="${repo%.git}"
repo="${repo#git@github.com:}"
repo="${repo#ssh://git@github.com/}"
repo="${repo#https://github.com/}"
repo="${repo#http://github.com/}"
repo="${repo,,}"
```

A valid resolved repo must look like `owner/name`.

If no current repository can be resolved and the user did not name one, ask which repository to manage.

## Resolve runners mapped to a repository

Read `RUNNERS_CONFIG` rather than hard-coding runner names.

```bash
mapfile -t project_runners < <(
  awk -F'|' -v wanted="$repo" '
    /^[[:space:]]*#/ || NF < 5 { next }
    {
      name=$1
      mapped=$4
      enabled=$5

      gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", mapped)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", enabled)

      if (tolower(mapped) == tolower(wanted) && tolower(enabled) != "false") {
        print name
      }
    }
  ' "$RUNNERS_CONFIG"
)
```

Never infer that a group covers a repository if the registry says otherwise.

# Common operations

## Inventory

For a fleet overview:

```bash
"$RUNNERS_HOME/runners.sh" list
"$RUNNERS_HOME/runners.sh" groups
"$RUNNERS_HOME/runner-services.sh" plan all
```

Use fleet-wide inspection freely because it is read-only.

## Check whether runners work

For a named runner:

```bash
"$RUNNERS_HOME/runners.sh" status "$runner"
"$RUNNERS_HOME/runners.sh" health "$runner"
"$RUNNERS_HOME/runners.sh" doctor "$runner"
```

For all runners mapped to the current repo, run those commands one runner at a time.

Interpret systemd on-demand states correctly:

- `active` + boot disabled: healthy and currently available;
- `inactive` + boot disabled: healthy idle runner under on-demand policy;
- `failed`: unhealthy;
- registration-deleted evidence in logs: stale remote registration, not a systemd failure.

Do not call an on-demand idle runner broken merely because it is inactive.

## Start runners for the current project

```bash
for runner in "${project_runners[@]}"; do
  "$RUNNERS_HOME/runners.sh" start "$runner"
done
```

Then validate:

```bash
for runner in "${project_runners[@]}"; do
  "$RUNNERS_HOME/runners.sh" status "$runner"
  "$RUNNERS_HOME/runners.sh" health "$runner"
done
```

A successful start command is insufficient if the service dies seconds later.

## Stop runners for the current project

When the user asks to release resources:

```bash
for runner in "${project_runners[@]}"; do
  "$RUNNERS_HOME/runners.sh" stop "$runner"
done
```

Stopping an on-demand runner is normal and should not be treated as disabling the runner registration.

## Switch boot policy

If supported by the installed `runner-services.sh`:

```bash
"$RUNNERS_HOME/runner-services.sh" on-demand "$runner"
"$RUNNERS_HOME/runner-services.sh" autostart "$runner"
```

Use `on-demand` by default for personal runners unless the user explicitly wants a runner always online.

Do not call `systemctl enable` or `disable` directly when the platform CLI exposes the operation.

# Register a runner for a personal repository

Use this flow when the user asks to create/cadastrar/adicionar a local runner for a personal GitHub project.

## 1. Resolve and validate the repository

Accept either:

- the current Git repository; or
- an explicit `owner/repo`.

Verify it exists:

```bash
gh repo view "$repo" --json nameWithOwner,viewerPermission
```

For automatic registration, require administrative permission sufficient to manage Actions runners.

Do not create runners for an unrelated organization or repository merely because credentials permit it unless the user explicitly requested that target.

## 2. Infer the technical profile

Inspect repository files before choosing a profile.

Suggested mapping:

- `pyproject.toml`, `requirements.txt`, `poetry.lock` -> `python`
- `pubspec.yaml` -> `flutter`
- `package.json` -> `node`
- `pom.xml`, `build.gradle*` -> `java`
- `go.mod` -> `go`
- `*.csproj`, `*.sln` -> `dotnet`
- otherwise -> `generic`

If multiple stacks are present, choose the profile needed by the GitHub Actions workflows rather than guessing from the largest source tree.

## 3. Build functional labels

Always include:

```text
local-runner
```

Add stack and project labels when useful, for example:

```text
python,my-project,local-runner
node,my-web,local-runner
flutter,android,my-app,local-runner
```

Do not add the final instance name manually. `configure-runner.sh` adds it.

## 4. Obtain a short-lived registration token

Prefer the authenticated GitHub CLI:

```bash
token="$(gh api --method POST "repos/$repo/actions/runners/registration-token" --jq .token)"
```

Treat `token` as secret:

- never print it;
- never include it in the final response;
- never write it to a committed file;
- unset it after configuration.

If the API call is unauthorized, ask the user for the normal GitHub `config.sh --url ... --token ...` registration line instead of inventing credentials.

## 5. Configure the runner

Use the platform script.

```bash
github_line="./config.sh --url https://github.com/$repo --token $token"

"$RUNNERS_HOME/configure-runner.sh" \
  --github-line "$github_line" \
  --labels "$labels" \
  --profile "$profile" \
  --group "$group"

unset token github_line
```

Capture the final local runner name from the script output.

Do not manually edit the runner registry when `configure-runner.sh` can update it.

## 6. Install the systemd service

```bash
"$RUNNERS_HOME/runner-services.sh" migrate "$runner_name"
```

Under `RUNNER_BOOT_POLICY=on-demand`, the desired end state is an installed service with boot disabled and the runner idle until needed.

If the installed platform predates on-demand support, report that fact instead of using hidden direct-systemd workarounds.

## 7. Validate registration and runtime

```bash
"$RUNNERS_HOME/runners.sh" doctor "$runner_name"
"$RUNNERS_HOME/runners.sh" health "$runner_name"
"$RUNNERS_HOME/runner-services.sh" plan "$runner_name"
```

Optionally start it to prove the GitHub session:

```bash
"$RUNNERS_HOME/runners.sh" start "$runner_name"
"$RUNNERS_HOME/runners.sh" status "$runner_name"
```

If the user wants on-demand idle state after validation:

```bash
"$RUNNERS_HOME/runners.sh" stop "$runner_name"
```

# Diagnose failures

## Registration deleted remotely

Inspect:

```bash
"$RUNNERS_HOME/runners.sh" logs "$runner" | tail -80
```

If logs contain:

```text
The runner registration has been deleted from the server
```

classify it as a stale GitHub registration.

Do not repeatedly restart it.

Offer either:

- re-register the runner; or
- remove the stale local instance if it is no longer needed.

Removal is destructive and requires explicit user intent.

## Duplicate session

If logs show a session conflict, first confirm there is not another service/process using the same runner directory or registration. Do not kill unrelated runner processes.

## Toolchain/cache failure

Use:

```bash
"$RUNNERS_HOME/cache.sh" profiles
"$RUNNERS_HOME/cache.sh" doctor --profile "$profile"
```

Preserve durable caches outside `_work`.

# Remove a runner

Only when the user explicitly asks to remove/delete a runner:

1. show the resolved runner name, repo and path;
2. stop it;
3. uninstall the systemd service using `runner-services.sh uninstall`;
4. remove its registry entry only after confirming the target;
5. remove the local directory only if the user requested full local removal;
6. do not delete another runner for the same repository.

Do not infer deletion merely because a runner is idle.

# Reporting

Keep routine output compact:

```text
Local runner:
- repo: owner/project
- runner: project
- policy: on-demand
- state: active | idle | failed
- boot: disabled
- registration: healthy | stale
```

For new registration also report:

- runner local name;
- GitHub runner name;
- profile;
- labels excluding any secret;
- registry path;
- systemd/on-demand state.

# Prohibitions

- Never expose runner registration tokens.
- Never commit the machine-local runner registry.
- Never use `start all` unless explicitly requested.
- Never enable all runners at boot by default.
- Never reconfigure an existing runner without explicit intent.
- Never delete a runner because it is merely inactive under on-demand policy.
- Never edit unrelated repository workflows while managing local runners.
- Never claim GitHub registration health solely from a local process being alive.
