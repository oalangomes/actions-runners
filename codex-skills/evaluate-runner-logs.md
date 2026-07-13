# Skill Codex: avaliar logs de runners locais

Use esta skill quando o usuário pedir para investigar um run, job, workflow, check ou comportamento de runner local/self-hosted.

## Objetivo

Classificar onde o job rodou, encontrar gargalos ou erros recorrentes e sugerir melhorias no runner local sem alterar workflows ou código sem autorização explícita.

## Fontes de evidência

Use, nessa ordem:

1. logs do GitHub Actions do job/run informado;
2. `runners.sh status`, `health`, `doctor` e `logs` no host local, quando disponível;
3. `runners.conf` para mapear nome, pasta, profile e repo;
4. `cache.sh status` para avaliar cache por stack;
5. arquivos `_diag`, `_work/_diag` e `.runner-logs` apenas quando necessário.

## Classificação do ambiente

### GitHub-hosted

Classifique como GitHub-hosted se o log contiver sinais como:

```text
Hosted Compute Agent
Runner Image: ubuntu-24.04
/home/runner/work/
```

### Self-hosted local

Classifique como self-hosted local se o log contiver sinais como:

```text
Runner name: 'AlanGomes-PC-agentsorch'
Machine name: 'AlanGomes-PC'
/home/alangomes/actions-runners/<runner>/_work/
```

## Checklist de análise

### 1. Identificar run e jobs

Levante:

- repo;
- PR ou branch;
- workflow;
- run id;
- job id;
- status/conclusão;
- jobs em progresso, sucesso, falha, cancelados ou skipped.

### 2. Confirmar roteamento

Verifique o modo selecionado pelo roteador:

```text
Selected mode: self-default
Selected mode: self-force-label
Selected mode: github-default
Selected mode: github-label-self-skip
```

Regras esperadas:

```text
sem label       → self-hosted
Self --force    → self-hosted
Self            → self-hosted, com fallback apenas se permitido
Self --skip     → GitHub-hosted
```

Se encontrar `github-default`, sinalize como desvio de contrato.

### 3. Verificar workspace

Self-hosted esperado:

```text
/home/alangomes/actions-runners/<runner>/_work/<repo>/<repo>
```

GitHub-hosted esperado:

```text
/home/runner/work/<repo>/<repo>
```

### 4. Procurar gargalos

Procure sinais de:

- downloads repetidos de actions;
- `setup-python`, `setup-node`, Flutter ou Java baixando toolchain toda vez;
- `npm ci`, `pip install`, `flutter pub get` lentos;
- upload de artifact demorado;
- `git clean -ffdx` removendo muitos diretórios;
- muitos `__pycache__` no workspace;
- cache dentro de `_work/_tool` em vez de `.runner-cache/tools/tool-cache`;
- erro `_diag/pages/<id>.log already exists`;
- processos órfãos de `Runner.Listener` ou `Runner.Worker`.

### 5. Avaliar cache

Comandos locais recomendados:

```bash
./cache.sh profiles
./cache.sh status --profile python
./cache.sh status --profile node
./cache.sh status --profile flutter
./runners.sh doctor all
./runners.sh health all
```

Cache ideal:

```text
/home/alangomes/actions-runners/.runner-cache/tools/tool-cache
/home/alangomes/actions-runners/.runner-cache/stacks/python
/home/alangomes/actions-runners/.runner-cache/stacks/node
/home/alangomes/actions-runners/.runner-cache/stacks/flutter
```

Evite recomendar cache durável dentro de `_work`.

## Recomendações padrão

### Runner local está funcionando

Se o job rodou em self-hosted e passou:

- confirmar que o runner está saudável;
- sugerir paralelismo com `runner-2` se houver fila;
- sugerir labels específicas por repo/stack;
- sugerir cache fora de `_work`;
- sugerir summary de auditoria por job.

### Job caiu em GitHub-hosted indevidamente

Se o default caiu em GitHub-hosted:

- apontar o trecho `github-default`;
- recomendar default `self-hosted`;
- recomendar guard contra alteração indevida;
- manter `Self --skip` como escape hatch se o usuário quiser.

### Runner travado ou duplicado

Se houver erro de `_diag/pages` ou processo órfão:

```bash
./runners.sh health <runner>
./runners.sh stop <runner>
./runners.sh start <runner>
```

Se persistir:

```bash
./runners.sh restart <runner>
```

Nunca recomendar iniciar outro processo na mesma pasta.

## Formato da resposta

Responder em quatro blocos:

1. **Veredito** — verde, falhou, travado, rodou local ou hosted.
2. **Evidências** — linhas/trechos de log, runner name, workspace, selected mode.
3. **Gargalos** — cache, setup, downloads, artifact, processos, labels.
4. **Ações recomendadas** — P0/P1/P2, com comandos quando útil.

## Proibições

- Não afirmar que rodou no self-hosted sem evidência de `Runner name`, `Machine name` ou workspace local.
- Não confundir runner online com job executado localmente.
- Não alterar workflows durante uma análise de logs, salvo pedido explícito.
- Não esconder que a API/log está incompleta.
- Não usar `Self --skip` como default sem autorização explícita.
