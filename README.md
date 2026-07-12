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
├── agentsorch/
├── neurotrack-web/
└── neurotrack-app/
```

Cada subpasta representa um runner registrado em um repositório GitHub.

---

## Scripts principais

| Script | Função |
|---|---|
| `configure-runner.sh` | cria pasta, extrai o tarball, registra runner no GitHub e atualiza `runners.conf` |
| `runners.sh` | start/stop/restart/status/list/doctor/health/logs dos runners |
| `runner-cache-env.sh` | exporta caches persistentes para ferramentas e actions |
| `cache.sh` | mostra status e limpa caches/logs com `--dry-run` |
| `prewarm-cache.sh` | aquece caches e valida stacks antes dos workflows |
| `dashboard.py` | painel local com status, logs, saúde, cache e alertas |

---

## Pré-requisitos

```bash
git --version
tar --version
sha256sum --version
python3 --version
```

Stacks opcionais:

```bash
# Node/Web
node -v
npm -v

# Python
python3 --version
pip3 --version

# Flutter/Android
flutter doctor
java -version
adb version
```

---

## Tarball do runner

O arquivo deve estar no diretório raiz:

```text
/home/alangomes/actions-runners/actions-runner-linux-x64-2.335.1.tar.gz
```

Checksum esperado:

```text
4ef2f25285f0ae4477f1fe1e346db76d2f3ebf03824e2ddd1973a2819bf6c8cf
```

O projeto **não baixa** o tarball automaticamente. Ele valida e extrai o arquivo já existente.

---

## Configurar um runner

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

O script vai:

1. extrair o runner em `/home/alangomes/actions-runners/neurotrack-app`;
2. registrar no GitHub com nome `<hostname>-neurotrack-app`;
3. inferir `profile=flutter`;
4. atualizar `runners.conf`;
5. adicionar a pasta no `.gitignore`.

---

## `runners.conf`

Formato atual:

```properties
# name|path|profile|repo|enabled
neurotrack-app|/home/alangomes/actions-runners/neurotrack-app|flutter|oalangomes/neurotrack-app|true
neurotrack-web|/home/alangomes/actions-runners/neurotrack-web|node|oalangomes/neurotrack-web|true
agentsorch|/home/alangomes/actions-runners/agentsorch|python|oalangomes/agentsorch|true
```

Formato antigo também funciona:

```properties
neurotrack-app|/home/alangomes/actions-runners/neurotrack-app
```

Nesse caso, o perfil vira `generic`, repo fica vazio e `enabled=true`.

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

Alertas rápidos no terminal:

```bash
./runners.sh health all
```

---

## Cache persistente

`runner-cache-env.sh` configura caches em:

```text
/home/alangomes/actions-runners/.runner-cache/
```

Inclui:

- `RUNNER_TOOL_CACHE` e `AGENT_TOOLSDIRECTORY`;
- npm, pnpm, yarn;
- Gradle e Maven;
- pip e pipx;
- Pub/Flutter;
- Cargo/Rust;
- Go;
- .NET/NuGet;
- Playwright.

Status:

```bash
./cache.sh status
```

Validação:

```bash
./cache.sh doctor
```

Limpeza segura:

```bash
./cache.sh clean all --older-than 30 --dry-run
./cache.sh clean gradle --older-than 45
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

Para Flutter, ele executa também:

```bash
flutter precache --android
```

Isso ajuda a reduzir tempo perdido com downloads e validações repetidas dentro do workflow.

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
- cache local por categoria;
- alertas de runner parado, PID órfão, erro recente em log, disco baixo, cache grande e estrutura incompleta;
- botões de start/stop/restart.

Porta customizada:

```bash
RUNNERS_DASHBOARD_PORT=8780 ./dashboard.py
```

Host customizado:

```bash
RUNNERS_DASHBOARD_HOST=0.0.0.0 ./dashboard.py
```

Use `0.0.0.0` apenas em rede confiável, porque o painel executa ações locais.

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

> O fallback do modo `Self` exige um token com permissão de leitura administrativa salvo como `ACTIONS_ADMIN_READ_TOKEN`, porque o workflow precisa consultar runners disponíveis.

---

## Exemplo simples

```yaml
name: CI Local Runner

on:
  workflow_dispatch:
  pull_request:

jobs:
  test:
    runs-on: [self-hosted, linux, x64, neurotrack-app]

    steps:
      - uses: actions/checkout@v4
      - run: flutter doctor
      - run: flutter pub get
      - run: flutter test
```

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

Nenhum runner compatível está online/livre.

```bash
./runners.sh status
./runners.sh start neurotrack-app
```

### Runner parado mas PID existe

```bash
./runners.sh health all
./runners.sh restart neurotrack-app
```

### Cache grande demais

```bash
./cache.sh status
./cache.sh clean all --older-than 30 --dry-run
./cache.sh clean all --older-than 30
```

### Stack ausente

```bash
./runners.sh doctor neurotrack-app
./prewarm-cache.sh flutter
```

### Ver logs

```bash
./runners.sh logs neurotrack-app
tail -f .runner-logs/neurotrack-app.log
```

Ou use o dashboard:

```bash
./dashboard.py
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
