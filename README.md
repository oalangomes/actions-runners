# GitHub Actions Local Runners

Setup local Linux-first para executar GitHub Actions em runners self-hosted.

A ideia é usar uma máquina Linux local para rodar pipelines pesados, testes, builds Flutter/Android, builds Node/Web e outros jobs, reduzindo consumo de minutos/budget do GitHub Actions.

## Estrutura Esperada

```text
/home/alangomes/actions-runners/
├── README.md
├── actions-runner-linux-x64-2.335.1.tar.gz
├── configure-runner.sh
├── runners.sh
├── runners.conf
├── .runner-logs/
├── .runner-pids/
├── agentsorch/
├── neurotrack-web/
└── neurotrack-app/
```

Cada subpasta representa um runner registrado para um repositório GitHub específico.

Exemplo:

```text
/home/alangomes/actions-runners/neurotrack-app/
├── config.sh
├── run.sh
├── .runner
└── _work/
```

## Arquivos Principais

`configure-runner.sh` cria e configura um novo runner local. Ele recebe a linha copiada do GitHub, extrai `--url` e `--token`, valida o tarball Linux, extrai o runner, atualiza `runners.conf` e executa `config.sh`.

`runners.sh` opera os runners configurados:

```bash
./runners.sh status
./runners.sh start all
./runners.sh stop all
./runners.sh restart all
./runners.sh doctor all
./runners.sh start neurotrack-app
./runners.sh logs neurotrack-app
```

`runners.conf` guarda os runners conhecidos:

```properties
# name|path
agentsorch|/home/alangomes/actions-runners/agentsorch
neurotrack-web|/home/alangomes/actions-runners/neurotrack-web
neurotrack-app|/home/alangomes/actions-runners/neurotrack-app
```

## Pre-Requisitos

Na máquina Linux:

```bash
git --version
tar --version
sha256sum --version
```

Para projetos Flutter/Android:

```bash
flutter doctor
java -version
adb version
```

Para projetos Node/Web:

```bash
node -v
npm -v
git --version
```

Para projetos Python:

```bash
python3 --version
pip3 --version
git --version
```

## Tarball Do Runner

O tarball deve estar em:

```text
/home/alangomes/actions-runners/actions-runner-linux-x64-2.335.1.tar.gz
```

O script não baixa o arquivo. Ele apenas valida e extrai o tarball já existente.

Checksum esperado:

```text
4ef2f25285f0ae4477f1fe1e346db76d2f3ebf03824e2ddd1973a2819bf6c8cf
```

## Criar Runner No GitHub

No repositório desejado:

```text
Settings -> Actions -> Runners -> New self-hosted runner
```

Escolha:

```text
Linux
x64
```

O GitHub vai gerar uma linha parecida com:

```bash
./config.sh --url https://github.com/oalangomes/neurotrack-app --token TOKEN_GERADO_PELO_GITHUB
```

Copie essa linha inteira.

## Configurar Runner Local

```bash
cd /home/alangomes/actions-runners
chmod +x configure-runner.sh runners.sh
```

Exemplo para `neurotrack-app`:

```bash
./configure-runner.sh \
  --github-line "./config.sh --url https://github.com/oalangomes/neurotrack-app --token TOKEN_GERADO_PELO_GITHUB" \
  --labels "flutter,android,neurotrack-app,alan-runner"
```

O script cria:

```text
/home/alangomes/actions-runners/neurotrack-app
```

E atualiza:

```text
/home/alangomes/actions-runners/runners.conf
```

Com:

```properties
neurotrack-app|/home/alangomes/actions-runners/neurotrack-app
```

## Configurar Com Nome Manual

Use `--name` quando quiser controlar o nome da pasta local:

```bash
./configure-runner.sh \
  --name "neurotrack-app" \
  --github-line "./config.sh --url https://github.com/oalangomes/neurotrack-app --token TOKEN_GERADO_PELO_GITHUB" \
  --labels "flutter,android,neurotrack-app,alan-runner"
```

## Recriar Runner Existente

Use `--replace`:

```bash
./configure-runner.sh \
  --github-line "./config.sh --url https://github.com/oalangomes/neurotrack-app --token TOKEN_GERADO_PELO_GITHUB" \
  --labels "flutter,android,neurotrack-app,alan-runner" \
  --replace
```

Isso remove a pasta local do runner e configura novamente.

## Operar Runners

Todos os comandos abaixo devem ser executados no Linux:

```bash
cd /home/alangomes/actions-runners
```

Ver status:

```bash
./runners.sh status
```

Subir todos:

```bash
./runners.sh start all
```

Subir um runner específico:

```bash
./runners.sh start neurotrack-app
```

Parar todos:

```bash
./runners.sh stop all
```

Parar um runner específico:

```bash
./runners.sh stop neurotrack-app
```

Reiniciar:

```bash
./runners.sh restart all
./runners.sh restart neurotrack-web
```

Validar estrutura:

```bash
./runners.sh doctor all
```

Listar runners conhecidos:

```bash
./runners.sh list
```

Ver arquivos de log:

```bash
./runners.sh logs all
tail -f .runner-logs/neurotrack-app.log
```

## Painel Web Local

Para acompanhar status, ligar/desligar runners e ver logs sem ficar usando comandos no terminal:

```bash
cd /home/alangomes/actions-runners
./dashboard.py
```

Abra:

```text
http://127.0.0.1:8765
```

O painel lê `runners.conf`, usa os PID files de `.runner-pids/`, mostra os logs de `.runner-logs/` e também os logs de diagnóstico do runner em `_diag/*.log`.

Ver logs no painel não gera custo no GitHub. O painel só lê arquivos locais; custo/minutos só são consumidos quando jobs executam no GitHub Actions.

No seletor de logs:

* `Execução` mostra o stdout/stderr capturado pelo `runners.sh`.
* `Diagnóstico` mostra arquivos internos do runner em `_diag`.
* `Todos logs` combina as duas fontes.

Para logs ainda mais detalhados dos steps do workflow, habilite debug no próprio repositório GitHub usando os secrets `ACTIONS_RUNNER_DEBUG=true` e `ACTIONS_STEP_DEBUG=true`. Isso aumenta a verbosidade dos jobs; não cobra por visualizar logs, mas jobs mais verbosos podem demorar um pouco mais e consumir minutos enquanto executam.

Para usar outra porta:

```bash
RUNNERS_DASHBOARD_PORT=8780 ./dashboard.py
```

## Labels Recomendadas

### Neurotrack App

Labels:

```text
flutter,android,neurotrack-app,alan-runner
```

YAML:

```yaml
runs-on: [self-hosted, linux, x64, neurotrack-app]
```

Ou:

```yaml
runs-on: [self-hosted, linux, x64, flutter]
```

### NeuroTrack Web

Labels:

```text
node,web,neurotrack-web,alan-runner
```

YAML:

```yaml
runs-on: [self-hosted, linux, x64, neurotrack-web]
```

### AgentsOrch

Labels:

```text
python,node,agentsorch,alan-runner
```

YAML:

```yaml
runs-on: [self-hosted, linux, x64, agentsorch]
```

## Contrato De Labels Para Workflows

Estratégia desejada para PRs:

| Label | Comportamento |
| --- | --- |
| `Self --force` | força self-hosted |
| `Self` | tenta self-hosted; se indisponível, usa GitHub-hosted |
| `Self --skip` | pula self-hosted e usa GitHub-hosted |
| Sem label | default = `Self --force` |

Resumo:

```text
Default
└── Self --force

Self --force
└── economia máxima, mas pode ficar em fila se a máquina estiver desligada

Self
└── usa self-hosted se estiver online/livre; caso contrário, fallback para GitHub-hosted

Self --skip
└── usa GitHub-hosted direto
```

## Exemplo Simples De Workflow Self-Hosted

```yaml
name: CI Local Runner

on:
  workflow_dispatch:
  pull_request:

jobs:
  test:
    runs-on: [self-hosted, linux, x64, neurotrack-app]

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Flutter doctor
        run: flutter doctor

      - name: Install dependencies
        run: flutter pub get

      - name: Run tests
        run: flutter test
```

## Exemplo De Workflow Manual Para APK

```yaml
name: Build APK Local

on:
  workflow_dispatch:

jobs:
  build-apk:
    runs-on: [self-hosted, linux, x64, neurotrack-app]

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Flutter doctor
        run: flutter doctor

      - name: Install dependencies
        run: flutter pub get

      - name: Run tests
        run: flutter test

      - name: Build APK
        run: flutter build apk --release

      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: app-release
          path: build/app/outputs/flutter-apk/app-release.apk
```

## Runner Group

Durante a configuração, não usar nomes como `neurotrack` no campo de runner group se o grupo não existir.

Use o padrão:

```text
Default
```

Runner group não é label.

Labels são configuradas no script com:

```bash
--labels "flutter,android,neurotrack-app,alan-runner"
```

## Máquina Desligada

Se o workflow exigir self-hosted e a máquina estiver desligada, o job fica aguardando runner disponível.

Exemplo:

```yaml
runs-on: [self-hosted, linux, x64, neurotrack-app]
```

Nesse caso, não existe fallback automático.

Para fallback, o workflow precisa ter uma etapa de roteamento antes de enfileirar o job pesado.

## Concorrência

Se houver vários runners na mesma máquina, o GitHub pode tentar rodar jobs simultâneos em runners diferentes.

Recomendação inicial:

* manter poucos runners ligados ao mesmo tempo;
* usar `concurrency` nos workflows;
* evitar rodar builds pesados em paralelo.

Exemplo:

```yaml
concurrency:
  group: local-runner-${{ github.repository }}
  cancel-in-progress: false
```

## Segurança

Self-hosted runner executa código do workflow na sua máquina.

Evite usar self-hosted runner em repositórios públicos aceitando PRs externos sem proteção.

Boas práticas no workflow:

```yaml
permissions:
  contents: read
```

Também recomendado:

* não rodar o runner como root;
* não deixar secrets pessoais na máquina;
* não usar a máquina principal para PRs não confiáveis;
* preferir workflows manuais para builds pesados;
* usar labels específicas por repo.

## Problemas Comuns

### `Could not find any self-hosted runner group named "neurotrack"`

Causa: foi informado `neurotrack` como runner group.

Solução: usar `Default` como runner group e colocar `neurotrack` como label.

### `Waiting for a runner to pick up this job...`

Causa: nenhum runner compatível está online/livre.

Soluções:

```bash
./runners.sh status
./runners.sh start neurotrack-app
```

Também verificar se o YAML usa labels corretas:

```yaml
runs-on: [self-hosted, linux, x64, neurotrack-app]
```

### `tarball nao encontrado`

Verificar se o arquivo existe:

```text
/home/alangomes/actions-runners/actions-runner-linux-x64-2.335.1.tar.gz
```

### `checksum diferente`

Causa: tarball diferente da versão esperada ou arquivo corrompido.

Solução: baixar novamente o tarball correto ou atualizar o hash esperado no script, caso a versão tenha sido alterada intencionalmente.

### `run.sh nao encontrado`

Causa: runner ainda não foi extraído/configurado corretamente.

Solução:

```bash
./configure-runner.sh \
  --github-line "./config.sh --url https://github.com/oalangomes/repositorio --token TOKEN" \
  --labels "labels,aqui"
```

### Runner Aparece Offline No GitHub

Verificar status local:

```bash
./runners.sh status
```

Subir runner:

```bash
./runners.sh start neurotrack-app
```

Depois conferir no GitHub:

```text
Settings -> Actions -> Runners
```

## Rotina Recomendada

Antes de trabalhar:

```bash
cd /home/alangomes/actions-runners
./runners.sh status
./runners.sh start all
```

Ao finalizar:

```bash
./runners.sh stop all
```

Para validar tudo:

```bash
./runners.sh doctor all
```

## Fluxo Ideal

```text
1. Criar runner Linux x64 no GitHub
2. Copiar linha ./config.sh --url ... --token ...
3. Rodar configure-runner.sh
4. Subir runner com runners.sh
5. Ajustar YAML com runs-on self-hosted/linux/x64
6. Usar labels de PR para controlar custo/fallback
```

## Resumo Rápido

Configurar novo runner:

```bash
cd /home/alangomes/actions-runners

./configure-runner.sh \
  --github-line "./config.sh --url https://github.com/oalangomes/neurotrack-app --token TOKEN_GERADO_PELO_GITHUB" \
  --labels "flutter,android,neurotrack-app,alan-runner"
```

Subir runner:

```bash
./runners.sh start neurotrack-app
```

Ver status:

```bash
./runners.sh status
```

Parar runner:

```bash
./runners.sh stop neurotrack-app
```
