#!/usr/bin/env python3
from __future__ import annotations

import html
import json
import os
import re
import signal
import shutil
import subprocess
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

BASE_DIR = Path(__file__).resolve().parent
CONFIG_PATH = BASE_DIR / "runners.conf"
PID_DIR = BASE_DIR / ".runner-pids"
LOG_DIR = BASE_DIR / ".runner-logs"
CACHE_ROOT = Path(os.environ.get("RUNNER_CACHE_ROOT", BASE_DIR / ".runner-cache"))
RUNNERS_SH = BASE_DIR / "runners.sh"

HOST = os.environ.get("RUNNERS_DASHBOARD_HOST", "127.0.0.1")
PORT = int(os.environ.get("RUNNERS_DASHBOARD_PORT", "8765"))
ERROR_RE = re.compile(r"error|fatal|unauthorized|forbidden|denied|failed|cannot|exception|segmentation fault", re.I)


INDEX_HTML = r"""<!doctype html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Local Runners</title>
  <style>
    :root {
      color-scheme: light;
      --bg: #f6f7f9;
      --panel: #ffffff;
      --text: #1d2430;
      --muted: #667085;
      --line: #d0d5dd;
      --ok: #067647;
      --warn: #b54708;
      --critical: #b42318;
      --info: #175cd3;
      --blue: #2563eb;
      --shadow: 0 1px 2px rgba(16, 24, 40, .06);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: var(--bg);
      color: var(--text);
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      font-size: 14px;
    }
    header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
      padding: 18px 24px;
      background: var(--panel);
      border-bottom: 1px solid var(--line);
    }
    h1 { margin: 0; font-size: 18px; font-weight: 700; }
    main {
      display: grid;
      grid-template-columns: minmax(320px, 450px) minmax(0, 1fr);
      gap: 16px;
      padding: 16px 24px 24px;
    }
    .toolbar { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
    button, select {
      border: 1px solid var(--line);
      background: var(--panel);
      color: var(--text);
      border-radius: 6px;
      min-height: 34px;
      padding: 0 11px;
      font: inherit;
      cursor: pointer;
      box-shadow: var(--shadow);
    }
    button:hover, select:hover { border-color: #98a2b3; }
    button.primary { background: var(--blue); border-color: var(--blue); color: #fff; }
    button.danger { color: var(--critical); }
    button:disabled { opacity: .55; cursor: not-allowed; }
    .summary {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 10px;
      margin-bottom: 16px;
    }
    .card {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 10px;
      padding: 12px;
      box-shadow: var(--shadow);
    }
    .metric { font-size: 22px; font-weight: 750; }
    .label { color: var(--muted); font-size: 12px; margin-top: 3px; }
    .panel {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 10px;
      box-shadow: var(--shadow);
      min-width: 0;
      overflow: hidden;
    }
    .runner-list { display: flex; flex-direction: column; }
    .runner-row {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      gap: 12px;
      padding: 13px 14px;
      border-bottom: 1px solid var(--line);
      cursor: pointer;
      text-align: left;
      width: 100%;
      border-radius: 0;
      box-shadow: none;
    }
    .runner-row:last-child { border-bottom: 0; }
    .runner-row.active { background: #eff6ff; }
    .runner-name { font-weight: 700; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .runner-meta, .runner-path { margin-top: 3px; color: var(--muted); font-size: 12px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .status {
      align-self: start;
      border-radius: 999px;
      padding: 3px 8px;
      font-size: 12px;
      border: 1px solid var(--line);
      white-space: nowrap;
    }
    .status.running, .pill.ok { color: var(--ok); background: #ecfdf3; border-color: #abefc6; }
    .status.stopped, .pill.warn { color: var(--warn); background: #fffaeb; border-color: #fedf89; }
    .status.disabled, .pill.info { color: var(--info); background: #eff8ff; border-color: #b2ddff; }
    .pill.critical { color: var(--critical); background: #fef3f2; border-color: #fecdca; }
    .pill {
      display: inline-flex;
      align-items: center;
      gap: 4px;
      border: 1px solid var(--line);
      border-radius: 999px;
      padding: 2px 8px;
      font-size: 12px;
      margin: 2px 4px 2px 0;
    }
    .detail { display: grid; grid-template-rows: auto auto auto minmax(260px, 1fr); min-width: 0; }
    .detail-head {
      padding: 14px;
      border-bottom: 1px solid var(--line);
      display: flex;
      justify-content: space-between;
      align-items: flex-start;
      gap: 14px;
    }
    .detail-title { min-width: 0; }
    .detail-title strong { display: block; font-size: 16px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .detail-title span { display: block; color: var(--muted); margin-top: 3px; font-size: 12px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .alerts, .cache { padding: 12px 14px; border-bottom: 1px solid var(--line); }
    .alerts ul { margin: 8px 0 0; padding-left: 18px; }
    .alerts li { margin: 4px 0; }
    .cache table { width: 100%; border-collapse: collapse; font-size: 12px; }
    .cache th, .cache td { text-align: left; padding: 4px 6px; border-bottom: 1px solid #eaecf0; }
    .output {
      padding: 10px 14px;
      min-height: 38px;
      color: var(--muted);
      border-bottom: 1px solid var(--line);
      white-space: pre-wrap;
    }
    pre {
      margin: 0;
      padding: 14px;
      background: #101828;
      color: #e4e7ec;
      overflow: auto;
      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace;
      font-size: 12px;
      line-height: 1.5;
      border-radius: 0 0 10px 10px;
    }
    .empty { padding: 24px; color: var(--muted); }
    @media (max-width: 980px) {
      header { align-items: flex-start; flex-direction: column; }
      main { grid-template-columns: 1fr; padding: 12px; }
      .summary { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .detail-head { flex-direction: column; }
    }
  </style>
</head>
<body>
  <header>
    <h1>Local GitHub Actions Runners</h1>
    <div class="toolbar">
      <button id="refresh">Atualizar</button>
      <button id="startAll" class="primary">Start all</button>
      <button id="stopAll" class="danger">Stop all</button>
    </div>
  </header>
  <main>
    <section>
      <div class="summary">
        <div class="card"><div class="metric" id="metricRunning">0</div><div class="label">rodando</div></div>
        <div class="card"><div class="metric" id="metricStopped">0</div><div class="label">parados</div></div>
        <div class="card"><div class="metric" id="metricAlerts">0</div><div class="label">alertas</div></div>
        <div class="card"><div class="metric" id="metricDisk">-</div><div class="label">disco livre</div></div>
      </div>
      <div class="panel runner-list" id="runnerList"></div>
    </section>
    <section class="panel detail">
      <div class="detail-head">
        <div class="detail-title">
          <strong id="selectedName">Nenhum runner selecionado</strong>
          <span id="selectedPath"></span>
          <div id="selectedPills"></div>
        </div>
        <div class="toolbar">
          <select id="logLines" title="Quantidade de linhas de log">
            <option value="200">200 linhas</option>
            <option value="1000" selected>1000 linhas</option>
            <option value="3000">3000 linhas</option>
            <option value="5000">5000 linhas</option>
          </select>
          <select id="logSource" title="Fonte dos logs">
            <option value="all" selected>Todos logs</option>
            <option value="run">Execução</option>
            <option value="diag">Diagnóstico</option>
          </select>
          <button id="startOne" class="primary">Start</button>
          <button id="restartOne">Restart</button>
          <button id="stopOne" class="danger">Stop</button>
        </div>
      </div>
      <div class="alerts">
        <strong>Alertas</strong>
        <div id="alertOutput"></div>
      </div>
      <div class="cache">
        <strong>Cache local</strong>
        <div id="cacheOutput"></div>
      </div>
      <div class="output" id="commandOutput"></div>
      <pre id="logOutput">Selecione um runner para ver o log.</pre>
    </section>
  </main>

  <script>
    let state = { runners: [], summary: {}, alerts: [], cache: [] };
    let selected = null;
    let busy = false;

    const runnerList = document.getElementById('runnerList');
    const selectedName = document.getElementById('selectedName');
    const selectedPath = document.getElementById('selectedPath');
    const selectedPills = document.getElementById('selectedPills');
    const commandOutput = document.getElementById('commandOutput');
    const logOutput = document.getElementById('logOutput');
    const alertOutput = document.getElementById('alertOutput');
    const cacheOutput = document.getElementById('cacheOutput');
    const logLines = document.getElementById('logLines');
    const logSource = document.getElementById('logSource');

    async function requestJson(url, options) {
      const response = await fetch(url, options);
      const data = await response.json();
      if (!response.ok || data.ok === false) {
        throw new Error(data.error || data.output || `HTTP ${response.status}`);
      }
      return data;
    }

    function setBusy(value) {
      busy = value;
      document.querySelectorAll('button').forEach(button => button.disabled = value);
    }

    function pill(text, kind = 'info') {
      const span = document.createElement('span');
      span.className = `pill ${kind}`;
      span.textContent = text;
      return span;
    }

    function renderSummary() {
      document.getElementById('metricRunning').textContent = state.summary.running || 0;
      document.getElementById('metricStopped').textContent = state.summary.stopped || 0;
      document.getElementById('metricAlerts').textContent = state.alerts?.length || 0;
      document.getElementById('metricDisk').textContent = state.summary.diskFreePercent != null ? `${state.summary.diskFreePercent}%` : '-';
    }

    function renderList() {
      runnerList.innerHTML = '';
      if (!state.runners || state.runners.length === 0) {
        runnerList.innerHTML = '<div class="empty">Nenhum runner em runners.conf.</div>';
        return;
      }

      for (const runner of state.runners) {
        const row = document.createElement('button');
        const status = runner.enabled === false ? 'disabled' : (runner.running ? 'running' : 'stopped');
        row.className = `runner-row ${selected === runner.name ? 'active' : ''}`;
        row.type = 'button';
        row.onclick = () => selectRunner(runner.name);
        row.innerHTML = `
          <div>
            <div class="runner-name"></div>
            <div class="runner-meta"></div>
            <div class="runner-path"></div>
          </div>
          <span class="status ${status}">${status === 'running' ? 'rodando' : status === 'disabled' ? 'desabilitado' : 'parado'}</span>
        `;
        row.querySelector('.runner-name').textContent = runner.name;
        row.querySelector('.runner-meta').textContent = `${runner.profile || 'generic'} · ${runner.repo || 'sem repo'} · pid ${runner.pid || '-'}`;
        row.querySelector('.runner-path').textContent = runner.path;
        runnerList.appendChild(row);
      }
    }

    function renderSelected() {
      const runner = state.runners.find(item => item.name === selected);
      selectedPills.innerHTML = '';
      if (!runner) {
        selectedName.textContent = 'Nenhum runner selecionado';
        selectedPath.textContent = '';
        logOutput.textContent = 'Selecione um runner para ver o log.';
        return;
      }

      selectedName.textContent = `${runner.name} · ${runner.running ? 'rodando' : runner.enabled === false ? 'desabilitado' : 'parado'}`;
      selectedPath.textContent = runner.path;
      selectedPills.appendChild(pill(`profile: ${runner.profile || 'generic'}`));
      if (runner.repo) selectedPills.appendChild(pill(`repo: ${runner.repo}`));
      if (runner.uptimeSeconds) selectedPills.appendChild(pill(`uptime: ${Math.round(runner.uptimeSeconds / 60)} min`, 'ok'));
      if (runner.recentError) selectedPills.appendChild(pill('erro recente', 'warn'));
    }

    function renderAlerts() {
      if (!state.alerts || state.alerts.length === 0) {
        alertOutput.innerHTML = '<div class="label">Nenhum alerta ativo.</div>';
        return;
      }
      const ul = document.createElement('ul');
      for (const alert of state.alerts) {
        const li = document.createElement('li');
        li.appendChild(pill(alert.severity, alert.severity === 'critical' ? 'critical' : alert.severity === 'warning' ? 'warn' : 'info'));
        li.appendChild(document.createTextNode(` ${alert.message}`));
        ul.appendChild(li);
      }
      alertOutput.innerHTML = '';
      alertOutput.appendChild(ul);
    }

    function renderCache() {
      if (!state.cache || state.cache.length === 0) {
        cacheOutput.innerHTML = '<div class="label">Sem dados de cache.</div>';
        return;
      }
      const rows = state.cache
        .filter(item => item.name !== 'total')
        .sort((a, b) => (b.bytes || 0) - (a.bytes || 0))
        .slice(0, 8)
        .map(item => `<tr><td>${item.name}</td><td>${item.human}</td><td>${item.path}</td></tr>`)
        .join('');
      const total = state.cache.find(item => item.name === 'total');
      cacheOutput.innerHTML = `
        <div class="label">Total: ${total ? total.human : '-'}</div>
        <table><thead><tr><th>cache</th><th>size</th><th>path</th></tr></thead><tbody>${rows}</tbody></table>
      `;
    }

    async function loadStatus() {
      state = await requestJson('/api/status');
      if (!selected && state.runners.length > 0) selected = state.runners[0].name;
      if (selected && !state.runners.some(item => item.name === selected)) selected = state.runners[0]?.name || null;
      renderSummary();
      renderList();
      renderSelected();
      renderAlerts();
      renderCache();
      if (selected) await loadLog();
    }

    async function loadLog() {
      if (!selected) return;
      const lines = logLines.value || '1000';
      const source = logSource.value || 'all';
      const data = await requestJson(`/api/log?runner=${encodeURIComponent(selected)}&lines=${encodeURIComponent(lines)}&source=${encodeURIComponent(source)}`);
      logOutput.textContent = data.log || 'Sem log ainda.';
      logOutput.scrollTop = logOutput.scrollHeight;
    }

    async function selectRunner(name) {
      selected = name;
      renderList();
      renderSelected();
      await loadLog();
    }

    async function runAction(action, target) {
      setBusy(true);
      commandOutput.textContent = `Executando: ${action} ${target}`;
      try {
        const data = await requestJson('/api/action', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ action, target })
        });
        commandOutput.textContent = data.output || 'Comando executado.';
      } catch (error) {
        commandOutput.textContent = error.message;
      } finally {
        await loadStatus().catch(error => commandOutput.textContent = error.message);
        setBusy(false);
      }
    }

    document.getElementById('refresh').onclick = () => loadStatus();
    document.getElementById('startAll').onclick = () => runAction('start', 'all');
    document.getElementById('stopAll').onclick = () => runAction('stop', 'all');
    document.getElementById('startOne').onclick = () => selected && runAction('start', selected);
    document.getElementById('stopOne').onclick = () => selected && runAction('stop', selected);
    document.getElementById('restartOne').onclick = () => selected && runAction('restart', selected);
    logLines.onchange = () => loadLog();
    logSource.onchange = () => loadLog();

    loadStatus().catch(error => commandOutput.textContent = error.message);
    setInterval(() => {
      if (!busy) loadStatus().catch(error => commandOutput.textContent = error.message);
    }, 5000);
  </script>
</body>
</html>
"""


def human_bytes(num: int) -> str:
    units = ["B", "KB", "MB", "GB", "TB"]
    value = float(num)
    for unit in units:
        if value < 1024 or unit == units[-1]:
            return f"{value:.1f} {unit}" if unit != "B" else f"{int(value)} {unit}"
        value /= 1024
    return f"{num} B"


def dir_size(path: Path) -> int:
    if not path.exists():
        return 0
    if path.is_file():
        return path.stat().st_size
    total = 0
    for root, dirs, files in os.walk(path):
        root_path = Path(root)
        dirs[:] = [name for name in dirs if not (root_path / name).is_symlink()]
        for filename in files:
            file_path = root_path / filename
            try:
                if not file_path.is_symlink():
                    total += file_path.stat().st_size
            except OSError:
                continue
    return total


def parse_enabled(value: str) -> bool:
    return value.strip().lower() not in {"false", "0", "no", "n", "nao", "não"}


def read_runners() -> list[dict[str, object]]:
    runners: list[dict[str, object]] = []
    if not CONFIG_PATH.exists():
        return runners

    for raw_line in CONFIG_PATH.read_text(encoding="utf-8-sig").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "|" not in line:
            continue

        parts = [part.strip() for part in line.split("|")]
        name = parts[0] if len(parts) > 0 else ""
        path = parts[1] if len(parts) > 1 else ""
        profile = parts[2] if len(parts) > 2 and parts[2] else "generic"
        repo = parts[3] if len(parts) > 3 else ""
        enabled = parse_enabled(parts[4] if len(parts) > 4 else "true")

        if not name or not path:
            continue

        pid = read_pid(name)
        running = is_running(pid)
        runner_path = Path(path)
        log_path = LOG_DIR / f"{name}.log"

        runners.append(
            {
                "name": name,
                "path": path,
                "profile": profile,
                "repo": repo,
                "enabled": enabled,
                "pid": pid if running else None,
                "pidRaw": pid,
                "running": running,
                "uptimeSeconds": process_uptime_seconds(pid) if running else None,
                "logPath": str(log_path),
                "recentError": log_has_recent_error(log_path),
                "hasStalePid": pid is not None and not running,
                "hasRunSh": (runner_path / "run.sh").exists(),
                "hasRunnerFile": (runner_path / ".runner").exists(),
            }
        )

    return runners


def runner_names() -> set[str]:
    return {str(runner["name"]) for runner in read_runners()}


def read_pid(name: str) -> int | None:
    pid_path = PID_DIR / f"{name}.pid"
    try:
        value = pid_path.read_text(encoding="utf-8").strip()
        return int(value)
    except (FileNotFoundError, ValueError):
        return None


def is_running(pid: int | None) -> bool:
    if not pid:
        return False
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def process_uptime_seconds(pid: int | None) -> int | None:
    if not pid:
        return None
    proc_path = Path("/proc") / str(pid)
    try:
        started = proc_path.stat().st_ctime
    except OSError:
        return None
    return max(0, int(time.time() - started))


def tail_file(path: Path, lines: int) -> str:
    if not path.exists():
        return ""
    data = path.read_text(encoding="utf-8", errors="replace").splitlines()
    return "\n".join(data[-lines:])


def log_has_recent_error(path: Path) -> bool:
    content = tail_file(path, 200)
    return bool(content and ERROR_RE.search(content))


def recent_diag_files(runner_path: Path, limit: int = 8) -> list[Path]:
    diag_dir = runner_path / "_diag"
    if not diag_dir.exists():
        return []

    files = [path for path in diag_dir.glob("*.log") if path.is_file()]
    files.sort(key=lambda path: path.stat().st_mtime, reverse=True)
    return files[:limit]


def read_runner_log(name: str, source: str, lines: int) -> str:
    runners = {str(runner["name"]): runner for runner in read_runners()}
    runner = runners.get(name)
    if not runner:
        raise ValueError(f"runner desconhecido: {name}")

    chunks: list[str] = []
    run_log = LOG_DIR / f"{name}.log"
    runner_path = Path(str(runner["path"]))

    if source in {"run", "all"}:
        content = tail_file(run_log, lines)
        if content:
            chunks.append(f"===== execução: {run_log} =====\n{content}")

    if source in {"diag", "all"}:
        per_file_lines = max(lines // 4, 120) if source == "all" else lines
        for diag_file in reversed(recent_diag_files(runner_path)):
            content = tail_file(diag_file, per_file_lines)
            if content:
                chunks.append(f"===== diagnóstico: {diag_file} =====\n{content}")

    return "\n\n".join(chunks)


def cache_items() -> list[dict[str, object]]:
    paths = {
        "tool-cache": CACHE_ROOT / "tool-cache",
        "npm": CACHE_ROOT / "npm",
        "pnpm": CACHE_ROOT / "pnpm",
        "yarn": CACHE_ROOT / "yarn",
        "gradle": CACHE_ROOT / "gradle",
        "maven": CACHE_ROOT / "maven",
        "pip": CACHE_ROOT / "pip",
        "pub": CACHE_ROOT / "pub",
        "cargo": CACHE_ROOT / "cargo",
        "go": CACHE_ROOT / "go",
        "dotnet": CACHE_ROOT / "dotnet",
        "nuget": CACHE_ROOT / "nuget",
        "playwright": CACHE_ROOT / "playwright",
        "logs": LOG_DIR,
    }
    items = []
    for name, path in paths.items():
        size = dir_size(path)
        items.append({"name": name, "path": str(path), "bytes": size, "human": human_bytes(size)})
    total = dir_size(CACHE_ROOT)
    items.append({"name": "total", "path": str(CACHE_ROOT), "bytes": total, "human": human_bytes(total)})
    return items


def disk_summary() -> dict[str, object]:
    usage = shutil.disk_usage(BASE_DIR)
    free_percent = round((usage.free / usage.total) * 100)
    return {
        "totalBytes": usage.total,
        "usedBytes": usage.used,
        "freeBytes": usage.free,
        "freePercent": free_percent,
        "freeHuman": human_bytes(usage.free),
    }


def build_alerts(runners: list[dict[str, object]], cache: list[dict[str, object]], disk: dict[str, object]) -> list[dict[str, str]]:
    alerts: list[dict[str, str]] = []

    if int(disk["freePercent"]) < 10:
        alerts.append({"severity": "critical", "message": f"Disco crítico: apenas {disk['freePercent']}% livre ({disk['freeHuman']})"})
    elif int(disk["freePercent"]) < 15:
        alerts.append({"severity": "warning", "message": f"Disco baixo: {disk['freePercent']}% livre ({disk['freeHuman']})"})

    total_cache = next((item for item in cache if item["name"] == "total"), None)
    if total_cache and int(total_cache["bytes"]) > 50 * 1024**3:
        alerts.append({"severity": "warning", "message": f"Cache local acima de 50 GB: {total_cache['human']}"})

    for runner in runners:
        name = str(runner["name"])
        if runner["enabled"] is False:
            alerts.append({"severity": "info", "message": f"{name} está desabilitado no runners.conf"})
            continue

        if runner["hasStalePid"]:
            alerts.append({"severity": "warning", "message": f"{name} tem PID órfão/stale"})
        if not runner["running"]:
            alerts.append({"severity": "warning", "message": f"{name} está parado"})
        if not runner["hasRunSh"]:
            alerts.append({"severity": "critical", "message": f"{name} não tem run.sh"})
        if not runner["hasRunnerFile"]:
            alerts.append({"severity": "warning", "message": f"{name} não tem arquivo .runner"})
        if runner["recentError"]:
            alerts.append({"severity": "warning", "message": f"{name} tem erro recente nos logs"})

    return alerts


def summary(runners: list[dict[str, object]], disk: dict[str, object]) -> dict[str, object]:
    enabled = [runner for runner in runners if runner["enabled"] is not False]
    running = [runner for runner in enabled if runner["running"]]
    stopped = [runner for runner in enabled if not runner["running"]]
    disabled = [runner for runner in runners if runner["enabled"] is False]
    return {
        "total": len(runners),
        "enabled": len(enabled),
        "disabled": len(disabled),
        "running": len(running),
        "stopped": len(stopped),
        "diskFreePercent": disk["freePercent"],
        "diskFreeHuman": disk["freeHuman"],
    }


def run_runner_action(action: str, target: str) -> subprocess.CompletedProcess[str]:
    allowed_actions = {"start", "stop", "restart"}
    if action not in allowed_actions:
        raise ValueError(f"acao nao permitida: {action}")
    if target != "all" and target not in runner_names():
        raise ValueError(f"runner desconhecido: {target}")

    return subprocess.run(
        [str(RUNNERS_SH), action, target],
        cwd=str(BASE_DIR),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=45,
        check=False,
    )


def status_payload() -> dict[str, object]:
    runners = read_runners()
    cache = cache_items()
    disk = disk_summary()
    alerts = build_alerts(runners, cache, disk)
    return {
        "ok": True,
        "runners": runners,
        "cache": cache,
        "disk": disk,
        "alerts": alerts,
        "summary": summary(runners, disk),
    }


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args: object) -> None:
        return

    def send_json(self, data: dict[str, object], status: HTTPStatus = HTTPStatus.OK) -> None:
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/":
            body = INDEX_HTML.encode("utf-8")
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if parsed.path in {"/api/status", "/api/health"}:
            self.send_json(status_payload())
            return

        if parsed.path == "/api/log":
            params = parse_qs(parsed.query)
            name = params.get("runner", [""])[0]
            source = params.get("source", ["all"])[0]
            try:
                lines = min(max(int(params.get("lines", ["1000"])[0]), 1), 5000)
            except ValueError:
                lines = 1000
            if source not in {"run", "diag", "all"}:
                self.send_json({"ok": False, "error": f"fonte de log invalida: {source}"}, HTTPStatus.BAD_REQUEST)
                return
            try:
                self.send_json({"ok": True, "log": read_runner_log(name, source, lines)})
            except ValueError as exc:
                self.send_json({"ok": False, "error": str(exc)}, HTTPStatus.BAD_REQUEST)
            return

        self.send_json({"ok": False, "error": "nao encontrado"}, HTTPStatus.NOT_FOUND)

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path != "/api/action":
            self.send_json({"ok": False, "error": "nao encontrado"}, HTTPStatus.NOT_FOUND)
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            action = str(payload.get("action", ""))
            target = str(payload.get("target", ""))
            result = run_runner_action(action, target)
            self.send_json(
                {
                    "ok": result.returncode == 0,
                    "returncode": result.returncode,
                    "output": result.stdout.strip(),
                },
                HTTPStatus.OK if result.returncode == 0 else HTTPStatus.BAD_REQUEST,
            )
        except Exception as exc:
            self.send_json({"ok": False, "error": html.escape(str(exc))}, HTTPStatus.BAD_REQUEST)


def main() -> None:
    server = ThreadingHTTPServer((HOST, PORT), Handler)

    def shutdown(_signum: int, _frame: object) -> None:
        server.shutdown()

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    print(f"Dashboard: http://{HOST}:{PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
