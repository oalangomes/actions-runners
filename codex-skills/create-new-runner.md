# Skill Codex: criar novo runner local

Use esta skill quando o usuário pedir para criar, registrar ou adicionar mais um GitHub Actions self-hosted runner usando este repositório `actions-runners`.

## Objetivo

Criar uma nova instância de runner sem sobrescrever runners existentes, mantendo:

- uma pasta por runner;
- um registro por runner no GitHub;
- labels funcionais específicas por repo/stack;
- uma label automática igual ao identificador final da instância;
- caches fora do `_work`;
- `runners.conf` atualizado pelo script oficial.

## Regra principal

Nunca crie dois runners na mesma pasta.

Correto:

```text
/home/alangomes/actions-runners/agentsorch
/home/alangomes/actions-runners/agentsorch-2
/home/alangomes/actions-runners/agentsorch-3
```

Errado:

```text
/home/alangomes/actions-runners/agentsorch
├── runner 1
└── runner 2
```

## Identificador e label automática

O identificador local final é registrado automaticamente como label exclusiva do runner.

Exemplos:

```text
nome local: agentsorch
label automática: agentsorch

nome local: agentsorch-2
label automática: agentsorch-2

nome local: neurotrack_ms-2
label automática: neurotrack_ms-2
```

O usuário e o Codex não devem repetir essa label no argumento `--labels`. O `configure-runner.sh` resolve o próximo nome livre e acrescenta a label depois.

Informe somente labels funcionais:

```text
python,agentsorch,alan-runner
```

Resultado calculado pelo script:

```text
python,agentsorch,alan-runner,agentsorch-2
```

## Pré-requisitos

1. O usuário deve gerar um token novo no GitHub:

```text
Repo → Settings → Actions → Runners → New self-hosted runner → Linux → x64
```

2. O usuário deve fornecer a linha completa do GitHub:

```bash
./config.sh --url https://github.com/oalangomes/agentsorch --token TOKEN_GERADO
```

3. Não inventar token, não reutilizar token vencido e não expor token em logs/respostas.

## Fluxo seguro

1. Entrar no diretório base:

```bash
cd /home/alangomes/actions-runners
```

2. Conferir runners existentes:

```bash
./runners.sh list
./runners.sh status
cat runners.conf
```

3. Configurar o novo runner usando apenas labels funcionais:

```bash
./configure-runner.sh \
  --github-line "./config.sh --url https://github.com/oalangomes/agentsorch --token TOKEN_GERADO" \
  --labels "python,agentsorch,alan-runner" \
  --profile python
```

4. Se o nome base já existir, o script deve auto-incrementar:

```text
agentsorch      → primeiro runner; label automática agentsorch
agentsorch-2    → segundo runner; label automática agentsorch-2
agentsorch-3    → terceiro runner; label automática agentsorch-3
```

5. Conferir no output do script:

```text
Runner local: agentsorch-2
Instance label: agentsorch-2
Labels: python,agentsorch,alan-runner,agentsorch-2
```

6. Validar estrutura:

```bash
./runners.sh doctor agentsorch-2
./runners.sh health agentsorch-2
```

7. Subir o runner:

```bash
./runners.sh start agentsorch-2
```

8. Confirmar status:

```bash
./runners.sh status
./runners.sh logs agentsorch-2
```

9. Confirmar em `Settings → Actions → Runners` que o runner registrado recebeu automaticamente a label da instância.

## Quando usar `--replace`

Use `--replace` somente quando a intenção explícita for recriar o mesmo runner.

Exemplo:

```bash
./configure-runner.sh \
  --github-line "./config.sh --url https://github.com/oalangomes/agentsorch --token TOKEN_GERADO" \
  --name agentsorch \
  --labels "python,agentsorch,alan-runner" \
  --profile python \
  --replace
```

Sem pedido explícito do usuário, não use `--replace`.

## Labels funcionais recomendadas

### AgentsOrch

```text
python,agentsorch,alan-runner
```

### NeuroTrack MS

```text
node,neurotrack-ms,alan-runner
```

### NeuroTrack Web

```text
node,web,neurotrack-web,alan-runner
```

### NeuroTrack App

```text
flutter,android,neurotrack-app,alan-runner
```

A label da instância é acrescentada automaticamente a qualquer conjunto acima.

## Critérios de sucesso

Ao final, informe somente:

- nome local do runner;
- nome registrado no GitHub;
- label automática da instância;
- conjunto final de labels calculado pelo script;
- pasta criada;
- linha adicionada ao `runners.conf`;
- status do runner;
- qualquer erro ou pendência real.

## Proibições

- Não registrar runner sem token novo fornecido pelo usuário.
- Não sobrescrever pasta existente sem `--replace` explícito.
- Não editar `runners.conf` manualmente se `configure-runner.sh` puder fazer isso.
- Não pedir ao usuário para informar manualmente a label igual ao nome final do runner.
- Não remover a label automática igual ao identificador final.
- Não mover caches para dentro de `_work`.
- Não iniciar dois processos na mesma pasta de runner.
- Não afirmar que o runner está online sem validar com `runners.sh status` ou evidência equivalente.
