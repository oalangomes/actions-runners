#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import signal
import shutil
import socket
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
ERROR_RE = re.compile(
    r"error|fatal|unauthorized|forbidden|denied|failed|cannot|exception|segmentation fault|already exists",
    re.I,
)

INDEX_HTML = r"""<!doctype html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Central de Runners</title>
  <style>
    :root{--bg:#f5f7fb;--panel:#fff;--text:#152033;--muted:#667085;--line:#d0d5dd;--ok:#067647;--warn:#b54708;--critical:#b42318;--blue:#175cd3;--soft:#eff4ff}
    *{box-sizing:border-box} body{margin:0;background:var(--bg);color:var(--text);font:14px Inter,system-ui,-apple-system,"Segoe UI",sans-serif}
    header{display:flex;justify-content:space-between;align-items:center;gap:12px;padding:16px 22px;background:var(--panel);border-bottom:1px solid var(--line);position:sticky;top:0;z-index:3}
    h1,h2,h3{margin:0} h1{font-size:19px} h2{font-size:15px} h3{font-size:14px}
    main{padding:16px 22px 28px}.toolbar{display:flex;gap:8px;flex-wrap:wrap;align-items:center}
    button,select{border:1px solid var(--line);background:var(--panel);border-radius:7px;min-height:34px;padding:0 11px;cursor:pointer;font:inherit}
    button.primary{background:var(--blue);border-color:var(--blue);color:#fff}button.danger{color:var(--critical)}button:disabled{opacity:.55;cursor:not-allowed}
    .metrics{display:grid;grid-template-columns:repeat(7,minmax(110px,1fr));gap:10px;margin-bottom:14px}.metric-card,.panel,.group-card{background:var(--panel);border:1px solid var(--line);border-radius:10px;box-shadow:0 1px 2px rgba(16,24,40,.05)}
    .metric-card{padding:11px}.metric{font-size:22px;font-weight:760}.label{color:var(--muted);font-size:12px;margin-top:3px}
    .layout{display:grid;grid-template-columns:minmax(330px,430px) minmax(0,1fr);gap:14px}.stack{display:flex;flex-direction:column;gap:14px}.panel-head{padding:12px 14px;border-bottom:1px solid var(--line);display:flex;justify-content:space-between;gap:10px;align-items:center}
    .group-grid{padding:10px;display:grid;grid-template-columns:1fr;gap:8px}.group-card{padding:10px}.group-top{display:flex;justify-content:space-between;gap:8px}.group-actions{display:flex;gap:5px;margin-top:8px}.group-actions button{min-height:29px;padding:0 8px;font-size:12px}
    .runner-row{width:100%;display:grid;grid-template-columns:minmax(0,1fr) auto;gap:10px;padding:12px 14px;border:0;border-bottom:1px solid var(--line);border-radius:0;text-align:left}.runner-row.active{background:var(--soft)}
    .runner-name{font-weight:700}.runner-meta,.runner-path{margin-top:3px;color:var(--muted);font-size:12px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
    .status,.pill{border-radius:999px;padding:3px 8px;font-size:12px;border:1px solid var(--line);white-space:nowrap}.status.running,.pill.ok{color:var(--ok);background:#ecfdf3;border-color:#abefc6}.status.stopped,.pill.warn{color:var(--warn);background:#fffaeb;border-color:#fedf89}.status.disabled,.pill.info{color:var(--blue);background:#eff8ff;border-color:#b2ddff}.pill.critical{color:var(--critical);background:#fef3f2;border-color:#fecdca}
    .detail-head,.alerts,.cache,.recommendations,.output{padding:12px 14px;border-bottom:1px solid var(--line)}.detail-head{display:flex;justify-content:space-between;gap:14px;align-items:flex-start}.detail-title strong{display:block;font-size:16px}.detail-title span{display:block;color:var(--muted);margin-top:3px;font-size:12px}.pill{display:inline-flex;margin:5px 4px 0 0}
    ul{margin:8px 0 0;padding-left:20px}.cache table{width:100%;border-collapse:collapse;font-size:12px}.cache th,.cache td{text-align:left;padding:4px 6px;border-bottom:1px solid #eaecf0}
    pre{margin:0;padding:14px;min-height:320px;max-height:58vh;overflow:auto;background:#101828;color:#e4e7ec;font:12px/1.5 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}.empty{padding:20px;color:var(--muted)}
    @media(max-width:1150px){.metrics{grid-template-columns:repeat(4,minmax(110px,1fr))}.layout{grid-template-columns:1fr}}
    @media(max-width:700px){header{align-items:flex-start;flex-direction:column}main{padding:12px}.metrics{grid-template-columns:repeat(2,minmax(0,1fr))}.detail-head{flex-direction:column}}
  </style>
</head>
<body>
<header><div><h1>Central de Runners</h1><div class="label" id="hostLabel"></div></div><div class="toolbar"><button id="refresh">Atualizar</button><button id="startAll" class="primary">Subir todos</button><button id="stopAll" class="danger">Parar todos</button></div></header>
<main>
  <div class="metrics">
    <div class="metric-card"><div class="metric" id="mHealth">-</div><div class="label">saúde</div></div>
    <div class="metric-card"><div class="metric" id="mRunning">0</div><div class="label">rodando</div></div>
    <div class="metric-card"><div class="metric" id="mStopped">0</div><div class="label">parados</div></div>
    <div class="metric-card"><div class="metric" id="mGroups">0</div><div class="label">grupos</div></div>
    <div class="metric-card"><div class="metric" id="mMemory">-</div><div class="label">RAM usada</div></div>
    <div class="metric-card"><div class="metric" id="mDisk">-</div><div class="label">disco livre</div></div>
    <div class="metric-card"><div class="metric" id="mLoad">-</div><div class="label">load 1 min</div></div>
  </div>
  <div class="layout">
    <section class="stack">
      <div class="panel"><div class="panel-head"><h2>Grupos</h2><span class="label">controle por domínio</span></div><div class="group-grid" id="groupGrid"></div></div>
      <div class="panel"><div class="panel-head"><h2>Runners</h2><select id="groupFilter"><option value="all">Todos os grupos</option></select></div><div id="runnerList"></div></div>
    </section>
    <section class="panel">
      <div class="recommendations"><h3>Recomendações automáticas</h3><div id="recommendationOutput"></div></div>
      <div class="detail-head"><div class="detail-title"><strong id="selectedName">Nenhum runner selecionado</strong><span id="selectedPath"></span><div id="selectedPills"></div></div><div class="toolbar"><select id="logLines"><option value="200">200 linhas</option><option value="1000" selected>1000 linhas</option><option value="3000">3000 linhas</option><option value="5000">5000 linhas</option></select><select id="logSource"><option value="all" selected>Todos logs</option><option value="run">Execução</option><option value="diag">Diagnóstico</option></select><button id="startOne" class="primary">Start</button><button id="restartOne">Restart</button><button id="stopOne" class="danger">Stop</button></div></div>
      <div class="alerts"><h3>Alertas</h3><div id="alertOutput"></div></div>
      <div class="cache"><h3>Cache local</h3><div id="cacheOutput"></div></div>
      <div class="output label" id="commandOutput"></div>
      <pre id="logOutput">Selecione um runner para ver o log.</pre>
    </section>
  </div>
</main>
<script>
let state={runners:[],groups:[],summary:{},alerts:[],cache:[],system:{},recommendations:[]};let selected=null;let busy=false;const $=id=>document.getElementById(id);
async function requestJson(url,options){const r=await fetch(url,options);const d=await r.json();if(!r.ok||d.ok===false)throw new Error(d.error||d.output||`HTTP ${r.status}`);return d}
function setBusy(v){busy=v;document.querySelectorAll('button').forEach(b=>b.disabled=v)}
function pill(text,kind='info'){const s=document.createElement('span');s.className=`pill ${kind}`;s.textContent=text;return s}
function renderMetrics(){const s=state.summary||{},sys=state.system||{};$('mHealth').textContent=`${s.healthScore??0}%`;$('mRunning').textContent=s.running||0;$('mStopped').textContent=s.stopped||0;$('mGroups').textContent=state.groups?.length||0;$('mMemory').textContent=sys.memoryUsedPercent!=null?`${sys.memoryUsedPercent}%`:'-';$('mDisk').textContent=s.diskFreePercent!=null?`${s.diskFreePercent}%`:'-';$('mLoad').textContent=sys.load1??'-';$('hostLabel').textContent=`${sys.hostname||''} · uptime ${sys.uptimeHuman||'-'} · ${sys.cpuCount||'?'} CPUs`}
function renderGroupFilter(){const f=$('groupFilter'),current=f.value||'all';f.innerHTML='<option value="all">Todos os grupos</option>';for(const g of state.groups||[]){const o=document.createElement('option');o.value=g.name;o.textContent=`${g.name} (${g.running}/${g.enabled})`;f.appendChild(o)}f.value=[...f.options].some(o=>o.value===current)?current:'all'}
function renderGroups(){const grid=$('groupGrid');grid.innerHTML='';if(!state.groups?.length){grid.innerHTML='<div class="empty">Nenhum grupo configurado.</div>';return}for(const g of state.groups){const card=document.createElement('div');card.className='group-card';const top=document.createElement('div');top.className='group-top';const title=document.createElement('strong');title.textContent=g.name;const stats=document.createElement('span');stats.className=`status ${g.running>0?'running':'stopped'}`;stats.textContent=`${g.running}/${g.enabled} online`;top.append(title,stats);const meta=document.createElement('div');meta.className='label';meta.textContent=`total ${g.total} · parados ${g.stopped} · alertas ${g.alerts}`;const actions=document.createElement('div');actions.className='group-actions';for(const [label,action,cls] of [['Subir','start','primary'],['Reiniciar','restart',''],['Parar','stop','danger']]){const b=document.createElement('button');b.textContent=label;b.className=cls;b.onclick=()=>runAction(action,`group:${g.name}`);actions.appendChild(b)}card.append(top,meta,actions);grid.appendChild(card)}}
function visibleRunners(){const group=$('groupFilter').value||'all';return (state.runners||[]).filter(r=>group==='all'||r.group===group)}
function renderList(){const list=$('runnerList');list.innerHTML='';const runners=visibleRunners();if(!runners.length){list.innerHTML='<div class="empty">Nenhum runner nesse grupo.</div>';return}for(const runner of runners){const status=runner.enabled===false?'disabled':(runner.running?'running':'stopped');const row=document.createElement('button');row.className=`runner-row ${selected===runner.name?'active':''}`;row.type='button';row.onclick=()=>selectRunner(runner.name);row.innerHTML=`<div><div class="runner-name"></div><div class="runner-meta"></div><div class="runner-path"></div></div><span class="status ${status}">${status==='running'?'rodando':status==='disabled'?'desabilitado':'parado'}</span>`;row.querySelector('.runner-name').textContent=runner.name;row.querySelector('.runner-meta').textContent=`${runner.group} · ${runner.profile||'generic'} · ${runner.repo||'sem repo'} · pid ${runner.pid||runner.detectedPids?.[0]||'-'}`;row.querySelector('.runner-path').textContent=runner.path;list.appendChild(row)}}
function renderSelected(){const runner=state.runners.find(i=>i.name===selected),pills=$('selectedPills');pills.innerHTML='';if(!runner){$('selectedName').textContent='Nenhum runner selecionado';$('selectedPath').textContent='';$('logOutput').textContent='Selecione um runner para ver o log.';return}$('selectedName').textContent=`${runner.name} · ${runner.running?'rodando':runner.enabled===false?'desabilitado':'parado'}`;$('selectedPath').textContent=runner.path;pills.appendChild(pill(`grupo: ${runner.group}`));pills.appendChild(pill(`profile: ${runner.profile||'generic'}`));if(runner.repo)pills.appendChild(pill(`repo: ${runner.repo}`));if(runner.uptimeSeconds)pills.appendChild(pill(`uptime: ${Math.round(runner.uptimeSeconds/60)} min`,'ok'));if(runner.detectedPids?.length>1)pills.appendChild(pill(`processos: ${runner.detectedPids.length}`,'warn'));if(runner.recentError)pills.appendChild(pill('erro recente','warn'))}
function renderItems(target,items,empty){const out=$(target);if(!items?.length){out.innerHTML=`<div class="label">${empty}</div>`;return}const ul=document.createElement('ul');for(const item of items){const li=document.createElement('li');if(item.severity)li.appendChild(pill(item.severity,item.severity==='critical'?'critical':item.severity==='warning'?'warn':'info'));li.appendChild(document.createTextNode(` ${item.message||item}`));ul.appendChild(li)}out.innerHTML='';out.appendChild(ul)}
function renderCache(){const out=$('cacheOutput');if(!state.cache?.length){out.innerHTML='<div class="label">Sem dados de cache.</div>';return}const total=state.cache.find(i=>i.name==='total');const rows=state.cache.filter(i=>i.name!=='total').sort((a,b)=>(b.bytes||0)-(a.bytes||0)).slice(0,10).map(i=>`<tr><td>${i.name}</td><td>${i.human}</td><td>${i.path}</td></tr>`).join('');out.innerHTML=`<div class="label">Total: ${total?total.human:'-'}</div><table><thead><tr><th>cache</th><th>size</th><th>path</th></tr></thead><tbody>${rows}</tbody></table>`}
async function loadStatus(){state=await requestJson('/api/status');if(!selected&&state.runners.length)selected=state.runners[0].name;if(selected&&!state.runners.some(i=>i.name===selected))selected=state.runners[0]?.name||null;renderMetrics();renderGroupFilter();renderGroups();renderList();renderSelected();renderItems('alertOutput',state.alerts,'Nenhum alerta ativo.');renderItems('recommendationOutput',state.recommendations,'Nenhuma recomendação agora.');renderCache();if(selected)await loadLog()}
async function loadLog(){if(!selected)return;const data=await requestJson(`/api/log?runner=${encodeURIComponent(selected)}&lines=${$('logLines').value||1000}&source=${$('logSource').value||'all'}`);$('logOutput').textContent=data.log||'Sem log ainda.';$('logOutput').scrollTop=$('logOutput').scrollHeight}
async function selectRunner(name){selected=name;renderList();renderSelected();await loadLog()}
async function runAction(action,target){setBusy(true);$('commandOutput').textContent=`Executando: ${action} ${target}`;try{const d=await requestJson('/api/action',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action,target})});$('commandOutput').textContent=d.output||'Comando executado.'}catch(e){$('commandOutput').textContent=e.message}finally{await loadStatus().catch(e=>$('commandOutput').textContent=e.message);setBusy(false)}}
$('refresh').onclick=()=>loadStatus();$('startAll').onclick=()=>runAction('start','all');$('stopAll').onclick=()=>runAction('stop','all');$('startOne').onclick=()=>selected&&runAction('start',selected);$('stopOne').onclick=()=>selected&&runAction('stop',selected);$('restartOne').onclick=()=>selected&&runAction('restart',selected);$('logLines').onchange=()=>loadLog();$('logSource').onchange=()=>loadLog();$('groupFilter').onchange=()=>renderList();
loadStatus().catch(e=>$('commandOutput').textContent=e.message);setInterval(()=>{if(!busy)loadStatus().catch(e=>$('commandOutput').textContent=e.message)},5000);
</script>
</body>
</html>"""


def human_bytes(num: int) -> str:
    units = ["B", "KB", "MB", "GB", "TB"]
    value = float(num)
    for unit in units:
        if value < 1024 or unit == units[-1]:
            return f"{value:.1f} {unit}" if unit != "B" else f"{int(value)} {unit}"
        value /= 1024
    return f"{num} B"


def human_duration(seconds: int) -> str:
    days, rest = divmod(max(0, seconds), 86400)
    hours, rest = divmod(rest, 3600)
    minutes = rest // 60
    if days:
        return f"{days}d {hours}h"
    if hours:
        return f"{hours}h {minutes}m"
    return f"{minutes}m"


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
    return value.strip().lower() in {"true", "1", "yes", "y", "sim"}


def normalize_slug(value: str) -> str:
    normalized = re.sub(r"[^a-z0-9._-]+", "-", value.strip().lower()).strip("-")
    return normalized or "generic"


def infer_group(name: str, repo: str) -> str:
    value = f"{name},{repo}".lower()
    if "agentsorch" in value:
        return "agentsorch"
    if "neurotrack" in value or "docsneurotrack" in value:
        return "neurotrack"
    if "ea-fc" in value or "sheffield" in value:
        return "ea-fc"
    if "roboapostas" in value or "robo-apostas" in value or "apostas" in value:
        return "roboapostas"
    return normalize_slug(repo.rsplit("/", 1)[-1] or name)


def read_pid(name: str) -> int | None:
    try:
        return int((PID_DIR / f"{name}.pid").read_text(encoding="utf-8").strip())
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


def process_pids_by_path(path: str) -> list[int]:
    result: list[int] = []
    proc = Path("/proc")
    if not proc.exists():
        return result
    for pid_dir in proc.iterdir():
        if not pid_dir.name.isdigit():
            continue
        try:
            cmdline = (pid_dir / "cmdline").read_bytes().replace(b"\x00", b" ").decode("utf-8", "replace")
        except OSError:
            continue
        if path in cmdline and any(token in cmdline for token in ("run.sh", "Runner.Listener", "Runner.Worker")):
            result.append(int(pid_dir.name))
    return sorted(set(result))


def process_uptime_seconds(pid: int | None) -> int | None:
    if not pid:
        return None
    try:
        started = (Path("/proc") / str(pid)).stat().st_ctime
    except OSError:
        return None
    return max(0, int(time.time() - started))


def tail_file(path: Path, lines: int) -> str:
    if not path.exists():
        return ""
    return "\n".join(path.read_text(encoding="utf-8", errors="replace").splitlines()[-lines:])


def log_has_recent_error(path: Path) -> bool:
    content = tail_file(path, 200)
    return bool(content and ERROR_RE.search(content))


def read_runners() -> list[dict[str, object]]:
    runners: list[dict[str, object]] = []
    if not CONFIG_PATH.exists():
        return runners
    for raw_line in CONFIG_PATH.read_text(encoding="utf-8-sig").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "|" not in line:
            continue
        parts = [part.strip() for part in line.split("|")]
        name = parts[0] if len(parts) > 0 else ""
        path = parts[1] if len(parts) > 1 else ""
        profile = parts[2] if len(parts) > 2 and parts[2] else "generic"
        repo = parts[3] if len(parts) > 3 else ""
        enabled = parse_enabled(parts[4] if len(parts) > 4 else "true")
        group = normalize_slug(parts[5]) if len(parts) > 5 and parts[5] else infer_group(name, repo)
        if not name or not path:
            continue
        pid = read_pid(name)
        detected_pids = process_pids_by_path(path)
        active_pid = pid if is_running(pid) else (detected_pids[0] if detected_pids else None)
        running = active_pid is not None
        runner_path = Path(path)
        log_path = LOG_DIR / f"{name}.log"
        runners.append(
            {
                "name": name,
                "path": path,
                "profile": profile,
                "repo": repo,
                "group": group,
                "enabled": enabled,
                "pid": active_pid,
                "pidRaw": pid,
                "detectedPids": detected_pids,
                "running": running,
                "uptimeSeconds": process_uptime_seconds(active_pid),
                "logPath": str(log_path),
                "recentError": log_has_recent_error(log_path),
                "hasStalePid": pid is not None and not is_running(pid) and not detected_pids,
                "hasRunSh": (runner_path / "run.sh").exists(),
                "hasRunnerFile": (runner_path / ".runner").exists(),
            }
        )
    return runners


def runner_names() -> set[str]:
    return {str(runner["name"]) for runner in read_runners()}


def group_names() -> set[str]:
    return {str(runner["group"]) for runner in read_runners()}


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
    paths: dict[str, Path] = {
        "tools": CACHE_ROOT / "tools",
        "tool-cache": CACHE_ROOT / "tools" / "tool-cache",
        "shared": CACHE_ROOT / "shared",
        "logs": LOG_DIR,
    }
    stacks_dir = CACHE_ROOT / "stacks"
    if stacks_dir.exists():
        for profile_dir in sorted(path for path in stacks_dir.iterdir() if path.is_dir()):
            paths[f"stack:{profile_dir.name}"] = profile_dir
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


def system_summary() -> dict[str, object]:
    load1 = load5 = load15 = 0.0
    try:
        load1, load5, load15 = os.getloadavg()
    except OSError:
        pass
    memory_total = memory_available = 0
    try:
        values: dict[str, int] = {}
        for line in Path("/proc/meminfo").read_text(encoding="utf-8").splitlines():
            key, value = line.split(":", 1)
            values[key] = int(value.strip().split()[0]) * 1024
        memory_total = values.get("MemTotal", 0)
        memory_available = values.get("MemAvailable", 0)
    except (OSError, ValueError):
        pass
    uptime_seconds = 0
    try:
        uptime_seconds = int(float(Path("/proc/uptime").read_text(encoding="utf-8").split()[0]))
    except (OSError, ValueError, IndexError):
        pass
    used_percent = round(((memory_total - memory_available) / memory_total) * 100) if memory_total else None
    return {
        "hostname": socket.gethostname(),
        "cpuCount": os.cpu_count(),
        "load1": round(load1, 2),
        "load5": round(load5, 2),
        "load15": round(load15, 2),
        "memoryTotalBytes": memory_total,
        "memoryAvailableBytes": memory_available,
        "memoryUsedPercent": used_percent,
        "uptimeSeconds": uptime_seconds,
        "uptimeHuman": human_duration(uptime_seconds),
    }


def build_alerts(
    runners: list[dict[str, object]], cache: list[dict[str, object]], disk: dict[str, object], system: dict[str, object]
) -> list[dict[str, str]]:
    alerts: list[dict[str, str]] = []
    if int(disk["freePercent"]) < 10:
        alerts.append({"severity": "critical", "message": f"Disco crítico: {disk['freePercent']}% livre ({disk['freeHuman']})"})
    elif int(disk["freePercent"]) < 15:
        alerts.append({"severity": "warning", "message": f"Disco baixo: {disk['freePercent']}% livre ({disk['freeHuman']})"})
    memory_used = system.get("memoryUsedPercent")
    if isinstance(memory_used, int) and memory_used >= 90:
        alerts.append({"severity": "critical", "message": f"RAM crítica: {memory_used}% usada"})
    elif isinstance(memory_used, int) and memory_used >= 80:
        alerts.append({"severity": "warning", "message": f"RAM alta: {memory_used}% usada"})
    cpu_count = int(system.get("cpuCount") or 1)
    if float(system.get("load1") or 0) > cpu_count * 1.5:
        alerts.append({"severity": "warning", "message": f"Carga alta: load {system['load1']} para {cpu_count} CPUs"})
    total_cache = next((item for item in cache if item["name"] == "total"), None)
    if total_cache and int(total_cache["bytes"]) > 50 * 1024**3:
        alerts.append({"severity": "warning", "message": f"Cache local acima de 50 GB: {total_cache['human']}"})
    for runner in runners:
        name = str(runner["name"])
        if runner["enabled"] is False:
            alerts.append({"severity": "info", "message": f"{name} está desabilitado"})
            continue
        if runner["hasStalePid"]:
            alerts.append({"severity": "warning", "message": f"{name} tem PID órfão/stale"})
        if not runner["running"]:
            alerts.append({"severity": "warning", "message": f"{name} está parado"})
        if not runner["hasRunSh"]:
            alerts.append({"severity": "critical", "message": f"{name} não tem run.sh"})
        if not runner["hasRunnerFile"]:
            alerts.append({"severity": "warning", "message": f"{name} não tem arquivo .runner"})
        if len(runner.get("detectedPids", [])) > 1:
            alerts.append({"severity": "warning", "message": f"{name} tem múltiplos processos detectados"})
        if runner["recentError"]:
            alerts.append({"severity": "warning", "message": f"{name} tem erro recente nos logs"})
    return alerts


def group_summary(runners: list[dict[str, object]], alerts: list[dict[str, str]]) -> list[dict[str, object]]:
    result: list[dict[str, object]] = []
    for group in sorted({str(runner["group"]) for runner in runners}):
        members = [runner for runner in runners if runner["group"] == group]
        enabled = [runner for runner in members if runner["enabled"] is not False]
        running = [runner for runner in enabled if runner["running"]]
        alert_count = sum(1 for alert in alerts if any(str(member["name"]) in alert["message"] for member in members))
        result.append(
            {
                "name": group,
                "total": len(members),
                "enabled": len(enabled),
                "running": len(running),
                "stopped": len(enabled) - len(running),
                "alerts": alert_count,
            }
        )
    return result


def health_score(alerts: list[dict[str, str]]) -> int:
    score = 100
    for alert in alerts:
        score -= {"critical": 20, "warning": 7, "info": 1}.get(alert["severity"], 2)
    return max(0, score)


def build_recommendations(
    runners: list[dict[str, object]], groups: list[dict[str, object]], cache: list[dict[str, object]], system: dict[str, object]
) -> list[dict[str, str]]:
    recommendations: list[dict[str, str]] = []
    for group in groups:
        if int(group["enabled"]) > 0 and int(group["running"]) == 0:
            recommendations.append({"severity": "warning", "message": f"Subir group:{group['name']}: nenhum runner online"})
        elif int(group["enabled"]) >= 2 and int(group["running"]) == 1:
            recommendations.append({"severity": "info", "message": f"O grupo {group['name']} possui capacidade de paralelismo ociosa"})
    if any(len(runner.get("detectedPids", [])) > 1 for runner in runners):
        recommendations.append({"severity": "warning", "message": "Reiniciar runners com processos duplicados antes de novos jobs"})
    total_cache = next((item for item in cache if item["name"] == "total"), None)
    if total_cache and int(total_cache["bytes"]) == 0:
        recommendations.append({"severity": "info", "message": "Executar prewarm-cache.sh: cache persistente ainda está vazio"})
    cpu_count = int(system.get("cpuCount") or 1)
    running = sum(1 for runner in runners if runner["running"])
    if running > cpu_count:
        recommendations.append({"severity": "warning", "message": "Há mais runners online que CPUs; limite concorrência para evitar thrashing"})
    if not recommendations:
        recommendations.append({"severity": "info", "message": "Central saudável; acompanhar fila, temperatura e uso de disco"})
    return recommendations


def summary(runners: list[dict[str, object]], disk: dict[str, object], alerts: list[dict[str, str]]) -> dict[str, object]:
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
        "healthScore": health_score(alerts),
    }


def run_runner_action(action: str, target: str) -> subprocess.CompletedProcess[str]:
    if action not in {"start", "stop", "restart"}:
        raise ValueError(f"acao nao permitida: {action}")
    if target == "all":
        pass
    elif target.startswith("group:"):
        group = normalize_slug(target.split(":", 1)[1])
        if group not in group_names():
            raise ValueError(f"grupo desconhecido: {group}")
        target = f"group:{group}"
    elif target not in runner_names():
        raise ValueError(f"runner desconhecido: {target}")
    return subprocess.run(
        [str(RUNNERS_SH), action, target],
        cwd=str(BASE_DIR),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
        check=False,
    )


def status_payload() -> dict[str, object]:
    runners = read_runners()
    cache = cache_items()
    disk = disk_summary()
    system = system_summary()
    alerts = build_alerts(runners, cache, disk, system)
    groups = group_summary(runners, alerts)
    return {
        "ok": True,
        "runners": runners,
        "groups": groups,
        "cache": cache,
        "disk": disk,
        "system": system,
        "alerts": alerts,
        "recommendations": build_recommendations(runners, groups, cache, system),
        "summary": summary(runners, disk, alerts),
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
            result = run_runner_action(str(payload.get("action", "")), str(payload.get("target", "")))
            self.send_json(
                {"ok": result.returncode == 0, "returncode": result.returncode, "output": result.stdout.strip()},
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
