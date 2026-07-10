#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import signal
import subprocess
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

BASE_DIR = Path(__file__).resolve().parent
CONFIG_PATH = BASE_DIR / "runners.conf"
PID_DIR = BASE_DIR / ".runner-pids"
LOG_DIR = BASE_DIR / ".runner-logs"
RUNNERS_SH = BASE_DIR / "runners.sh"

HOST = "127.0.0.1"
PORT = int(os.environ.get("RUNNERS_DASHBOARD_PORT", "8765"))


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
      --muted: #697386;
      --line: #d9dee7;
      --ok: #137a46;
      --stop: #9a3412;
      --blue: #2563eb;
      --red: #b42318;
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

    h1 {
      margin: 0;
      font-size: 18px;
      font-weight: 650;
      letter-spacing: 0;
    }

    main {
      display: grid;
      grid-template-columns: minmax(280px, 420px) minmax(0, 1fr);
      gap: 16px;
      padding: 16px 24px 24px;
      min-height: calc(100vh - 66px);
    }

    .toolbar {
      display: flex;
      align-items: center;
      gap: 8px;
      flex-wrap: wrap;
    }

    button, select {
      border: 1px solid var(--line);
      background: var(--panel);
      color: var(--text);
      border-radius: 6px;
      height: 34px;
      padding: 0 11px;
      font: inherit;
      cursor: pointer;
      box-shadow: var(--shadow);
    }

    button:hover, select:hover { border-color: #aab4c3; }
    button.primary { background: var(--blue); border-color: var(--blue); color: #fff; }
    button.danger { color: var(--red); }
    button:disabled { opacity: .55; cursor: not-allowed; }

    .panel {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      box-shadow: var(--shadow);
      min-width: 0;
    }

    .runner-list {
      display: flex;
      flex-direction: column;
      overflow: hidden;
    }

    .runner-row {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      gap: 12px;
      padding: 13px 14px;
      border-bottom: 1px solid var(--line);
      cursor: pointer;
    }

    .runner-row:last-child { border-bottom: 0; }
    .runner-row.active { background: #edf4ff; }

    .runner-name {
      font-weight: 650;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    .runner-path {
      margin-top: 3px;
      color: var(--muted);
      font-size: 12px;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    .status {
      align-self: start;
      border-radius: 999px;
      padding: 3px 8px;
      font-size: 12px;
      border: 1px solid var(--line);
      white-space: nowrap;
    }

    .status.running {
      color: var(--ok);
      background: #ecfdf3;
      border-color: #abefc6;
    }

    .status.stopped {
      color: var(--stop);
      background: #fff6ed;
      border-color: #fedf89;
    }

    .detail {
      display: grid;
      grid-template-rows: auto auto minmax(240px, 1fr);
      min-width: 0;
    }

    .detail-head {
      padding: 14px;
      border-bottom: 1px solid var(--line);
      display: flex;
      justify-content: space-between;
      align-items: flex-start;
      gap: 14px;
    }

    .detail-title {
      min-width: 0;
    }

    .detail-title strong {
      display: block;
      font-size: 16px;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    .detail-title span {
      display: block;
      color: var(--muted);
      margin-top: 3px;
      font-size: 12px;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

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
      border-radius: 0 0 8px 8px;
    }

    .empty {
      padding: 24px;
      color: var(--muted);
    }

    @media (max-width: 860px) {
      header { align-items: flex-start; flex-direction: column; }
      main { grid-template-columns: 1fr; padding: 12px; }
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
    <section class="panel runner-list" id="runnerList"></section>
    <section class="panel detail">
      <div class="detail-head">
        <div class="detail-title">
          <strong id="selectedName">Nenhum runner selecionado</strong>
          <span id="selectedPath"></span>
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
      <div class="output" id="commandOutput"></div>
      <pre id="logOutput">Selecione um runner para ver o log.</pre>
    </section>
  </main>

  <script>
    let runners = [];
    let selected = null;
    let busy = false;

    const runnerList = document.getElementById('runnerList');
    const selectedName = document.getElementById('selectedName');
    const selectedPath = document.getElementById('selectedPath');
    const commandOutput = document.getElementById('commandOutput');
    const logOutput = document.getElementById('logOutput');
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

    function renderList() {
      runnerList.innerHTML = '';
      if (runners.length === 0) {
        runnerList.innerHTML = '<div class="empty">Nenhum runner em runners.conf.</div>';
        return;
      }

      for (const runner of runners) {
        const row = document.createElement('button');
        row.className = `runner-row ${selected === runner.name ? 'active' : ''}`;
        row.type = 'button';
        row.onclick = () => selectRunner(runner.name);
        row.innerHTML = `
          <div>
            <div class="runner-name"></div>
            <div class="runner-path"></div>
          </div>
          <span class="status ${runner.running ? 'running' : 'stopped'}">${runner.running ? 'rodando' : 'parado'}</span>
        `;
        row.querySelector('.runner-name').textContent = runner.name;
        row.querySelector('.runner-path').textContent = runner.path;
        runnerList.appendChild(row);
      }
    }

    function renderSelected() {
      const runner = runners.find(item => item.name === selected);
      if (!runner) {
        selectedName.textContent = 'Nenhum runner selecionado';
        selectedPath.textContent = '';
        logOutput.textContent = 'Selecione um runner para ver o log.';
        return;
      }

      selectedName.textContent = `${runner.name} · ${runner.running ? 'rodando' : 'parado'}`;
      selectedPath.textContent = runner.path;
    }

    async function loadStatus() {
      const data = await requestJson('/api/status');
      runners = data.runners;
      if (!selected && runners.length > 0) selected = runners[0].name;
      if (selected && !runners.some(item => item.name === selected)) selected = runners[0]?.name || null;
      renderList();
      renderSelected();
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
        name, path = line.split("|", 1)
        name = name.strip()
        path = path.strip()
        if not name or not path:
            continue

        pid = read_pid(name)
        running = is_running(pid)
        runners.append(
            {
                "name": name,
                "path": path,
                "pid": pid if running else None,
                "running": running,
                "logPath": str(LOG_DIR / f"{name}.log"),
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


def tail_file(path: Path, lines: int) -> str:
    if not path.exists():
        return ""
    data = path.read_text(encoding="utf-8", errors="replace").splitlines()
    return "\n".join(data[-lines:])


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
        timeout=30,
        check=False,
    )


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

        if parsed.path == "/api/status":
            self.send_json({"ok": True, "runners": read_runners()})
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
            self.send_json({"ok": False, "error": str(exc)}, HTTPStatus.BAD_REQUEST)


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
