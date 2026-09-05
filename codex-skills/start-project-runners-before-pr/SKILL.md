---
name: start-project-runners-before-pr
description: Ensure the local GitHub Actions self-hosted runners mapped to the current repository are running before Codex creates or opens a pull request. Use when Codex is about to run gh pr create, open/publish a PR, or otherwise hand off a branch for PR review from a local project that may use the shared actions-runners installation. Start only runners configured for the current repository, validate they remain healthy, and block PR creation if a configured required runner cannot stay active. Do not use for PR reviews, PR-body edits, or tasks that are not creating a new PR.
---

# Start Project Runners Before PR

Before creating a pull request, ensure the self-hosted runner capacity for the current repository is online.

The user's explicit instruction takes precedence. If the user explicitly asks to skip local runner startup, do not block the PR.

## Runner home

Resolve the central runner installation in this order:

1. `$ACTIONS_RUNNERS_HOME`
2. `/home/alangomes/actions-runners`

Use:

```bash
RUNNERS_HOME="${ACTIONS_RUNNERS_HOME:-/home/alangomes/actions-runners}"
```

Do not assume the current repository is the `actions-runners` repository.

## 1. Determine the current GitHub repository

Require a Git worktree and derive `owner/repo` from `origin`.

Preferred:

```bash
remote="$(git remote get-url origin)"
repo="$remote"

repo="${repo%.git}"
repo="${repo#git@github.com:}"
repo="${repo#ssh://git@github.com/}"
repo="${repo#https://github.com/}"
repo="${repo#http://github.com/}"
repo="${repo,,}"
```

If `origin` is not a GitHub repository, do not invent a mapping. Report that the runner preflight could not resolve a GitHub repo and continue only if the user explicitly wants to proceed.

## 2. Check whether this project expects self-hosted runners

Inspect the repository's workflow files for local/self-hosted routing:

```bash
grep -R -n -E 'self-hosted|local-runner' .github/workflows 2>/dev/null || true
```

If no workflow references self-hosted/local-runner, runner startup is not required. Continue with the normal PR flow.

If local/self-hosted routing is present, continue with the preflight below.

## 3. Validate the runner central

Require:

```bash
test -x "$RUNNERS_HOME/runners.sh"
test -f "$RUNNERS_HOME/runners.conf"
```

If either is missing, stop before PR creation and report the missing runner infrastructure.

Do not create, register, replace, delete, or reconfigure runners from this skill.

## 4. Find enabled runners for the current repo

Match the `repo` column in `runners.conf` case-insensitively and select only enabled runners.

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
  ' "$RUNNERS_HOME/runners.conf"
)
```

Never use `./runners.sh start all` from this skill.

If self-hosted workflows exist but no enabled runner maps to the repository, block PR creation and report that no runner is configured for the repo. Suggest the existing runner-creation workflow rather than creating one automatically.

## 5. Start only the project's configured runners

For every matching runner:

```bash
for runner in "${project_runners[@]}"; do
  "$RUNNERS_HOME/runners.sh" start "$runner"
done
```

Treat a non-zero result as a failed preflight.

Do not call `systemctl`, `svc.sh`, `run.sh`, `nohup`, or PID-management commands directly. The runner CLI is the authority.

## 6. Verify runners stayed active

A start command being accepted is not enough. A GitHub listener can connect and then exit because its remote registration was deleted.

After startup, validate each runner:

```bash
failed=0

for runner in "${project_runners[@]}"; do
  status="$("$RUNNERS_HOME/runners.sh" status "$runner" 2>&1 || true)"
  printf '%s\n' "$status"

  if ! grep -q '^\[OK\]' <<<"$status"; then
    failed=1
  fi

  if grep -q 'backend=systemd' <<<"$status" &&
     ! grep -q 'state=active' <<<"$status"; then
    failed=1
  fi
done

if (( failed )); then
  exit 1
fi
```

Then run health for the same runners:

```bash
for runner in "${project_runners[@]}"; do
  "$RUNNERS_HOME/runners.sh" health "$runner" || true
done
```

If health reports `CRITICAL`, block PR creation.

Warnings may be reported to the user but should not automatically block a PR unless they show that the runner cannot execute jobs.

## 7. Failure handling

If a runner becomes inactive immediately after start:

```bash
"$RUNNERS_HOME/runners.sh" logs "$runner"
```

Look specifically for:

```text
The runner registration has been deleted from the server
```

If found, report that the local service exists but the GitHub runner registration is dead. Do not reconfigure or remove it automatically.

If another runtime error appears, report the relevant evidence and stop before PR creation.

## 8. Continue the PR flow only after the preflight passes

Only after every enabled runner mapped to the current repository is active may Codex continue with the user's requested PR workflow, for example:

```bash
git push
gh pr create ...
```

Do not change the requested PR title, body, base branch, labels, reviewers, or merge strategy because of this skill.

## Success summary

Before opening the PR, keep the runner summary concise:

```text
Runner preflight:
- repo: oalangomes/example
- runners: example, example-2
- status: active
- PR gate: passed
```

If no self-hosted workflow is present:

```text
Runner preflight: not required for this repository.
```

## Prohibitions

- Do not start every runner globally.
- Do not create a runner or request a registration token.
- Do not edit `runners.conf`.
- Do not remove stale runners automatically.
- Do not bypass an inactive/critical configured runner and silently create the PR.
- Do not claim the runner is online based only on `systemctl start` or an accepted start command.
