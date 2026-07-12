# Skill Codex: criar novo runner local

Use esta skill quando o usuário pedir para criar, registrar ou adicionar mais um GitHub Actions self-hosted runner usando este repositório `actions-runners`.

## Objetivo

Criar uma nova instância de runner sem sobrescrever runners existentes, mantendo:

- uma pasta por runner;
- um registro por runner no GitHub;
- labels específicas por repo/stack;
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

3. Configurar o novo runner usando `configure-runner.sh`:

```bash
./configure-runner.sh \
  --github-line "./config.sh --url https://github.com/oalangomes/agentsorch --token TOKEN_GERADO" \
  --labels "python,agentsorch,alan-runner" \
  --profile python
```

4. Se o nome base já existir, o script deve auto-incrementar:

```text
agentsorch      → primeiro runner
agentsorch-2    → segundo runner
agentsorch-3    → terceiro runner
```

5. Validar estrutura:

```bash
./runners.sh doctor agentsorch-2
./runners.sh health agentsorch-2
```

6. Subir o runner:

```bash
./runners.sh start agentsorch-2
```

7. Confirmar status:

```bash
./runners.sh status
./runners.sh logs agentsorch-2
```

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

## Labels recomendadas

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

## Critérios de sucesso

Ao final, informe somente:

- nome local do runner;
- nome registrado no GitHub;
- pasta criada;
- linha adicionada ao `runners.conf`;
- status do runner;
- qualquer erro ou pendência real.

## Proibições

- Não registrar runner sem token novo fornecido pelo usuário.
- Não sobrescrever pasta existente sem `--replace` explícito.
- Não editar `runners.conf` manualmente se `configure-runner.sh` puder fazer isso.
- Não mover caches para dentro de `_work`.
- Não iniciar dois processos na mesma pasta de runner.
- Não afirmar que o runner está online sem validar com `runners.sh status` ou evidência equivalente.
