# GitHub Actions Local Runners

Central Linux para operar múltiplos GitHub Actions self-hosted runners com:

- múltiplos runners por repositório;
- grupos operacionais por domínio;
- cache persistente fora de `_work`;
- start, stop, restart, health e doctor;
- proteção contra processos duplicados;
- painel local com métricas e recomendações;
- skills operacionais para Codex.

## Estrutura

```text
/home/alangomes/actions-runners/
├── configure-runner.sh
├── runners.sh
├── runner-cache-env.sh
├── cache.sh
├── prewarm-cache.sh
├── dashboard.py
├── runners.conf
├── codex-skills/
├── docs/
├── templates/
├── .runner-cache/
├── .runner-logs/
├── .runner-pids/
├── agentsorch/
├── agentsorch-2/
├── neurotrack_ms/
└── neurotrack_ms-2/
```

Cada pasta de runner representa uma instância registrada separadamente no GitHub.

## Configurar um runner

No repositório de destino:

```text
Settings → Actions → Runners → New self-hosted runner → Linux → x64
```

Copie a linha com URL e token e execute:

```bash
cd /home/alangomes/actions-runners

./configure-runner.sh \
  --github-line "./config.sh --url https://github.com/oalangomes/agentsorch --token TOKEN" \
  --labels "python,agentsorch,alan-runner" \
  --profile python
```

O grupo é inferido automaticamente:

| Repo/nome | Grupo |
|---|---|
| contém `agentsorch` | `agentsorch` |
| contém `neurotrack` | `neurotrack` |
| contém `ea-fc` ou `sheffield` | `ea-fc` |
| contém `roboapostas` ou `apostas` | `roboapostas` |

Também pode ser informado explicitamente:

```bash
./configure-runner.sh \
  --github-line "./config.sh --url https://github.com/oalangomes/NeuroTrack_MS --token TOKEN" \
  --labels "node,neurotrack-ms,alan-runner" \
  --profile node \
  --group neurotrack
```

## Múltiplos runners do mesmo repo

A primeira execução cria:

```text
agentsorch/
AlanGomes-PC-agentsorch
```

A segunda execução, usando um token novo, cria automaticamente:

```text
agentsorch-2/
AlanGomes-PC-agentsorch-2
```

A terceira cria `agentsorch-3`, e assim por diante.

Sem `--replace`, runners existentes são preservados. Use `--replace` somente para recriar explicitamente o mesmo runner.

## Gitignore de runners numerados

Ao configurar um runner, o script adiciona:

```gitignore
/agentsorch/
/agentsorch-[0-9]*/
```

Assim, `agentsorch-2`, `agentsorch-3` e próximos runners não aparecem como conteúdo versionável.

Se uma pasta já tiver sido adicionada ao índice antes da regra, remova apenas do índice:

```bash
git rm -r --cached agentsorch-2
```

Não apague a pasta física do runner.

## `runners.conf`

Formato atual:

```properties
# name|path|profile|repo|enabled|group
agentsorch|/home/alangomes/actions-runners/agentsorch|python|oalangomes/agentsorch|true|agentsorch
agentsorch-2|/home/alangomes/actions-runners/agentsorch-2|python|oalangomes/agentsorch|true|agentsorch
neurotrack_ms|/home/alangomes/actions-runners/neurotrack_ms|node|oalangomes/NeuroTrack_MS|true|neurotrack
```

Linhas antigas sem a sexta coluna continuam funcionando; o grupo é inferido pelo nome e repositório.

## Operar runners individuais

```bash
./runners.sh start agentsorch
./runners.sh stop agentsorch-2
./runners.sh restart neurotrack_ms
./runners.sh status agentsorch
./runners.sh doctor agentsorch
./runners.sh health agentsorch
./runners.sh logs agentsorch
```

## Operar por grupos

Listar grupos e capacidade:

```bash
./runners.sh groups
```

Subir todos os runners do NeuroTrack:

```bash
./runners.sh start group:neurotrack
```

Outros exemplos:

```bash
./runners.sh restart group:agentsorch
./runners.sh stop group:ea-fc
./runners.sh health group:roboapostas
./runners.sh status group:neurotrack
```

Operar tudo:

```bash
./runners.sh start all
./runners.sh stop all
./runners.sh status all
```

## Cache persistente

O `_work` continua sendo workspace descartável do runner.

Caches duráveis ficam em:

```text
.runner-cache/
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

Comandos:

```bash
./cache.sh profiles
./cache.sh status --profile python
./cache.sh status --profile node
./cache.sh status --profile flutter
./cache.sh clean all --profile python --older-than 30 --dry-run
```

Prewarm:

```bash
./prewarm-cache.sh python
./prewarm-cache.sh node
./prewarm-cache.sh flutter
./prewarm-cache.sh all
```

## Painel inteligente

Subir:

```bash
./dashboard.py
```

Abrir:

```text
http://127.0.0.1:8765
```

O painel mostra:

- runners agrupados por domínio;
- start, restart e stop por grupo;
- filtro de runners por grupo;
- hostname, uptime, CPUs, load, RAM e disco;
- score de saúde da central;
- processos detectados mesmo quando o PID file está stale;
- alertas de processo duplicado, runner parado, cache grande, RAM e disco;
- recomendações automáticas de capacidade e paralelismo;
- logs de execução e diagnóstico;
- cache por stack.

Por padrão, o painel escuta apenas em `127.0.0.1`. Para acesso pela rede privada:

```bash
RUNNERS_DASHBOARD_HOST=0.0.0.0 ./dashboard.py
```

Proteja esse acesso com firewall ou VPN privada.

## Proteção contra runner duplicado

O `runners.sh` procura processos ligados à pasta:

```text
run.sh
Runner.Listener
Runner.Worker
```

Ele evita iniciar outra instância na mesma pasta, encerra o grupo de processos no stop/restart e arquiva `_diag/pages` antes de subir novamente.

Comandos úteis:

```bash
./runners.sh health all
./runners.sh restart agentsorch
```

## Skills do Codex

```text
codex-skills/
├── create-new-runner.md
└── evaluate-runner-logs.md
```

- `create-new-runner.md`: cria runners sem sobrescrever pastas existentes.
- `evaluate-runner-logs.md`: identifica hosted/self-hosted, gargalos e melhorias sem alterar workflows sem autorização.

## Templates de workflow

```text
templates/
├── smart-runner-router.yml
├── flutter-self-hosted.yml
├── node-self-hosted.yml
└── python-self-hosted.yml
```

Contrato esperado:

| Label | Comportamento |
|---|---|
| `Self --force` | força self-hosted |
| `Self` | tenta self-hosted e usa fallback quando permitido |
| `Self --skip` | usa GitHub-hosted |
| sem label | self-hosted por padrão |

## Central Ubuntu em notebook

O blueprint para transformar um notebook em central de runners e laboratório doméstico está em:

```text
docs/notebook-central-blueprint.md
```

A separação recomendada é:

```text
host Ubuntu
├── GitHub runners como serviços do host
├── Docker Compose para ambientes de teste
├── volumes persistentes e backups
├── acesso privado por VPN
└── PC gamer usado sob demanda para builds pesados
```

## Validação

```bash
bash -n configure-runner.sh runners.sh cache.sh prewarm-cache.sh
python3 -m py_compile dashboard.py
./runners.sh list
./runners.sh groups
./runners.sh doctor all
./runners.sh health all
```

## Segurança

- não execute PR externo não confiável em runner persistente;
- não rode runners como root;
- use labels específicas por repo e stack;
- mantenha permissões mínimas no `GITHUB_TOKEN`;
- não exponha MongoDB, Redis, dashboard ou APIs diretamente à internet;
- mantenha ambientes de teste em containers separados dos processos dos runners;
- faça backup de volumes e arquivos de configuração, não de `_work`.
