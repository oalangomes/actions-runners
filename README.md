# GitHub Actions Local Runners

Setup **Linux-first** para executar GitHub Actions em runners self-hosted locais.

A ideia é usar uma máquina Linux para rodar jobs pesados — testes, builds Flutter/Android, Node/Web, Python e automações — reduzindo consumo de minutos/budget do GitHub Actions, sem perder o fluxo de PR/checks.

---

## Estrutura

```text
/home/alangomes/actions-runners/
├── README.md
├── actions-runner-linux-x64-2.335.1.tar.gz
├── configure-runner.sh
├── runners.sh
├── runner-cache-env.sh
├── cache.sh
├── prewarm-cache.sh
├── dashboard.py
├── runners.conf
├── templates/
├── .runner-logs/
├── .runner-pids/
├── .runner-cache/
│   ├── tools/
│   ├── shared/
│   └── stacks/
│       ├── flutter/
│       ├── node/
│       └── python/
├── agentsorch/
├── neurotrack-web/
└── neurotrack-app/
```

Cada subpasta de repo representa um runner registrado no GitHub. Os caches ficam fora do `_work` dos runners.

---

## Scripts principais

| Script | Função |
|---|---|
| `configure-runner.sh` | cria pasta, extrai o tarball, registra runner no GitHub e atualiza `runners.conf` |
| `runners.sh` | start/stop/restart/status/list/doctor/health/logs dos runners |
| `runner-cache-env.sh` | exporta caches persistentes por profile/stack fora do `_work` |
| `cache.sh` | mostra status e limpa caches/logs com `--dry-run` |
| `prewarm-cache.sh` | aquece caches e valida stacks antes dos workflows |
| `dashboard.py` | painel local com status, logs, saúde, cache e alertas |

---

## Configuração simples de runner

No GitHub:

```text
Settings → Actions → Runners → New self-hosted runner → Linux → x64
```

Copie a linha gerada:

```bash
./config.sh --url https://github.com/oalangomes/neurotrack-app --token TOKEN_GERADO_PELO_GITHUB
```

Execute:

```bash
cd /home/alangomes/actions-runners
chmod +x configure-runner.sh runners.sh cache.sh prewarm-cache.sh dashboard.py

./configure-runner.sh \
  --github-line "./config.sh --url https://github.com/oalangomes/neurotrack-app --token TOKEN_GERADO_PELO_GITHUB" \
  --labels "flutter,android,neurotrack-app,alan-runner"
```

Esse continua sendo o fluxo simples. O script infere o `profile` automaticamente a partir das labels/nome:

| Labels/nome | Profile inferido |
|---|---|
| `flutter`, `android` | `flutter` |
| `node`, `npm`, `pnpm`, `web` | `node` |
| `python`, `pytest`, `pip` | `python` |
| `java`, `maven`, `gradle` | `java` |
| `dotnet`, `nuget` | `dotnet` |
| `go`, `golang` | `go` |
| sem correspondência | `generic` |

Se quiser sobrescrever manualmente:

```bash
./configure-runner.sh \
  --github-line "./config.sh --url https://github.com/oalangomes/agentsorch --token TOKEN" \
  --labels "python,node,agentsorch,alan-runner" \
  --profile python
```

---

## `runners.conf`

Formato atual:

```properties
# name|path|profile|repo|enabled
neurotrack-app|/home/alangomes/actions-runners/neurotrack-app|flutter|oalangomes/neurotrack-app|true
neurotrack-web|/home/alangomes/actions-runners/neurotrack-web|node|oalangomes/neurotrack-web|true
agentsorch|/home/alangomes/actions-runners/agentsorch|python|oalangomes/agentsorch|true
```

Na prática, você **não precisa editar isso na mão**. O `configure-runner.sh` preenche.

Formato antigo também funciona:

```properties
neurotrack-app|/home/alangomes/actions-runners/neurotrack-app
```

Nesse caso, o perfil vira `generic`, repo fica vazio e `enabled=true`.

---

## Como fica a config de cada runner de repo?

Simples como antes.

### Neurotrack App

```bash
./configure-runner.sh \
  --github-line "./config.sh --url https://github.com/oalangomes/neurotrack-app --token TOKEN" \
  --labels "flutter,android,neurotrack-app,alan-runner"
```

Resultado no `runners.conf`:

```properties
neurotrack-app|/home/alangomes/actions-runners/neurotrack-app|flutter|oalangomes/neurotrack-app|true
```

Cache usado:

```text
/home/alangomes/actions-runners/.runner-cache/stacks/flutter/
```

### NeuroTrack Web

```bash
./configure-runner.sh \
  --github-line "./config.sh --url https://github.com/oalangomes/neurotrack-web --token TOKEN" \
  --labels "node,web,neurotrack-web,alan-runner"
```

Resultado:

```properties
neurotrack-web|/home/alangomes/actions-runners/neurotrack-web|node|oalangomes/neurotrack-web|true
```

Cache usado:

```text
/home/alangomes/actions-runners/.runner-cache/stacks/node/
```

### AgentsOrch

```bash
./configure-runner.sh \
  --github-line "./config.sh --url https://github.com/oalangomes/agentsorch --token TOKEN" \
  --labels "python,node,agentsorch,alan-runner" \
  --profile python
```

Resultado:

```properties
agentsorch|/home/alangomes/actions-runners/agentsorch|python|oalangomes/agentsorch|true
```

Cache usado:

```text
/home/alangomes/actions-runners/.runner-cache/stacks/python/
```

---

## Cache persistente

O `_work` continua sendo apenas workspace do GitHub Runner:

```text
/home/alangomes/actions-runners/neurotrack-app/_work/
```

Os caches duráveis ficam fora dele:

```text
/home/alangomes/actions-runners/.runner-cache/
├── tools/
│   └── tool-cache/
├── shared/
└── stacks/
    ├── flutter/
    ├── node/
    ├── python/
    ├── java/
    ├── go/
    └── dotnet/
```

### O que fica compartilhado

```text
.runner-cache/tools/tool-cache/
```

Usado por:

- `RUNNER_TOOL_CACHE`
- `AGENT_TOOLSDIRECTORY`
- actions de setup de ferramentas

### O que fica por profile/stack

```text
.runner-cache/stacks/<profile>/
```

Usado por:

- npm, pnpm, yarn;
- Gradle e Maven;
- pip e pipx;
- Pub/Flutter;
- Cargo/Rust;
- Go;
- .NET/NuGet;
- Playwright.

Isso evita misturar cache de Flutter com Node/Python, sem colocar cache dentro do `_work`.

---

## Operar runners

```bash
./runners.sh status
./runners.sh start all
./runners.sh start neurotrack-app
./runners.sh stop all
./runners.sh restart neurotrack-web
./runners.sh list
./runners.sh logs all
```

Validação por estrutura e stack:

```bash
./runners.sh doctor all
```

Alertas rápidos:

```bash
./runners.sh health all
```

---

## Proteção contra runner duplicado e erro `_diag/pages already exists`

O `runners.sh` evita iniciar uma segunda instância do mesmo runner quando ainda existe `run.sh`, `Runner.Listener` ou `Runner.Worker` vivo no diretório do runner.

Também inicia o runner em um process group próprio com `setsid` quando disponível. Assim, `stop` e `restart` encerram o grupo inteiro, não apenas o shell pai.

Antes de um novo start, se o runner estiver parado, o script arquiva arquivos antigos de:

```text
<runner>/_diag/pages/
```

em:

```text
<runner>/_diag/pages.archive.YYYYMMDDHHMMSS/
```

Isso reduz colisões como:

```text
The file '<runner>/_diag/pages/<id>.log' already exists.
```

Comandos úteis:

```bash
./runners.sh health agentsorch
./runners.sh stop agentsorch
./runners.sh start agentsorch
```

Se quiser desativar o arquivamento automático de `_diag/pages`:

```bash
RUNNER_ARCHIVE_DIAG_PAGES_ON_START=0 ./runners.sh start agentsorch
```

---

## Inspecionar e limpar cache

Listar profiles com cache criado:

```bash
./cache.sh profiles
```

Status por profile:

```bash
./cache.sh status --profile flutter
./cache.sh status --profile node
./cache.sh status --profile python
```

Validação por profile:

```bash
./cache.sh doctor --profile flutter
```

Limpeza segura:

```bash
./cache.sh clean all --profile flutter --older-than 30 --dry-run
./cache.sh clean gradle --profile flutter --older-than 45
./cache.sh clean logs --older-than 14
```

---

## Aquecer cache/setup

Antes de rodar workflows pesados:

```bash
./prewarm-cache.sh node
./prewarm-cache.sh python
./prewarm-cache.sh flutter
./prewarm-cache.sh all
```

Cada stack aquece o cache no profile correto:

```text
node    → .runner-cache/stacks/node/
python  → .runner-cache/stacks/python/
flutter → .runner-cache/stacks/flutter/
```

---

## Dashboard local

Subir painel:

```bash
./dashboard.py
```

Abrir:

```text
http://127.0.0.1:8765
```

O painel mostra:

- runners rodando/parados/desabilitados;
- profile, repo, PID e uptime;
- logs de execução e `_diag`;
- cards de resumo;
- cache local por categoria, incluindo `tools`, `shared` e `stack:<profile>`;
- alertas de runner parado, PID órfão, erro recente em log, disco baixo, cache grande e estrutura incompleta;
- botões de start/stop/restart.

---

## Templates de workflow

Modelos em:

```text
templates/
├── smart-runner-router.yml
├── flutter-self-hosted.yml
├── node-self-hosted.yml
└── python-self-hosted.yml
```

Copie o template desejado para o repo alvo em:

```text
.github/workflows/
```

### Contrato de labels

| Label | Comportamento |
|---|---|
| `Self --force` | força self-hosted |
| `Self` | tenta self-hosted; se indisponível, usa GitHub-hosted |
| `Self --skip` | pula self-hosted e usa GitHub-hosted |
| Sem label | default = `Self --force` |

---

## Segurança

Self-hosted runner executa código do workflow na sua máquina.

Boas práticas:

- não usar para PR externo não confiável;
- evitar rodar como root;
- usar labels específicas por repo/stack;
- manter `permissions: contents: read` nos workflows sempre que possível;
- deixar builds pesados em `workflow_dispatch` quando fizer sentido;
- usar `Self --skip` quando precisar garantir feedback pelo GitHub-hosted.

---

## Troubleshooting

### `Waiting for a runner to pick up this job...`

```bash
./runners.sh status
./runners.sh start neurotrack-app
```

### Runner parado mas PID existe

```bash
./runners.sh health all
./runners.sh restart neurotrack-app
```

### `_diag/pages/<id>.log already exists`

Causa provável: instância anterior do runner ficou parcialmente viva ou diagnóstico antigo conflitou no restart.

Use:

```bash
./runners.sh health agentsorch
./runners.sh restart agentsorch
```

O `restart` agora tenta parar o process group inteiro e arquiva `_diag/pages` antes de subir novamente.

### Cache grande demais

```bash
./cache.sh profiles
./cache.sh status --profile flutter
./cache.sh clean all --profile flutter --older-than 30 --dry-run
./cache.sh clean all --profile flutter --older-than 30
```

### Stack ausente

```bash
./runners.sh doctor neurotrack-app
./prewarm-cache.sh flutter
```

---

## Fluxo recomendado

```text
1. Configurar runner com configure-runner.sh
2. Aquecer cache com prewarm-cache.sh
3. Subir runner com runners.sh
4. Acompanhar pelo dashboard.py
5. Usar templates de workflow nos repos alvo
6. Monitorar alertas/cache com runners.sh health e cache.sh status
```
