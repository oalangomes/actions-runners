# Blueprint — notebook como central doméstica

## Decisão

Transformar o notebook Samsung em uma central Ubuntu é uma boa arquitetura para o estágio atual, desde que ele seja tratado como:

```text
laboratório privado + CI local + ambiente de testes
```

Não como produção pública com disponibilidade garantida.

O PC gamer fica reservado para:

- builds Flutter/Android pesados;
- testes que demandem mais CPU/RAM;
- execução manual;
- workloads com GPU;
- picos de paralelismo.

## Visão

```text
GitHub / Codex / AgentsOrch
          │
          ▼
Notebook Ubuntu — central sempre ligada
├── runners: agentsorch
├── runners: neurotrack
├── runners: ea-fc
├── runners: roboapostas
├── painel de runners
├── Docker Engine + Compose
│   ├── NeuroTrack API
│   ├── NeuroTrack Web
│   ├── MongoDB
│   ├── Redis
│   └── serviços auxiliares
├── volumes persistentes
├── backup
└── VPN privada / SSH
          │
          ├── APK NeuroTrack consome API privada
          └── PC gamer entra sob demanda para jobs heavy
```

## Divisão de responsabilidades

### Host Ubuntu

Rodar diretamente no host:

- SSH;
- VPN privada;
- GitHub Actions runners;
- `runners.sh` e `dashboard.py`;
- Docker Engine;
- monitoramento do host;
- backups;
- systemd.

### Containers

Rodar em Docker Compose:

- APIs;
- frontends web;
- MongoDB;
- Redis;
- filas;
- serviços de teste;
- mocks;
- ferramentas de observabilidade.

Evite instalar dependências específicas de cada aplicação diretamente no host quando elas puderem ficar no container.

## Estrutura de diretórios

```text
/home/alangomes/actions-runners/
├── agentsorch/
├── agentsorch-2/
├── neurotrack_ms/
├── neurotrack_web/
└── .runner-cache/

/srv/stacks/
├── neurotrack/
│   ├── compose.yaml
│   ├── compose.test.yaml
│   └── .env
├── agentsorch/
├── ea-fc/
└── roboapostas/

/srv/data/
├── neurotrack-mongo/
├── neurotrack-redis/
├── backups/
└── logs/
```

## Grupos de runners

### Notebook central

```text
agentsorch
neurotrack
ea-fc
roboapostas
```

Labels sugeridas:

```text
self-hosted,linux,x64,central,notebook,python,agentsorch
self-hosted,linux,x64,central,notebook,node,neurotrack
```

### PC gamer

```text
heavy
flutter
android
gpu
```

Labels sugeridas:

```text
self-hosted,linux,x64,pc-gamer,heavy,flutter,android
```

Jobs comuns ficam no notebook. Jobs pesados exigem labels do PC gamer.

## Concorrência

Não confunda quantidade de runners com capacidade real.

Comece com:

```text
2 runners concorrentes no notebook
```

Depois observe:

- load médio;
- RAM;
- temperatura;
- tempo de fila;
- I/O do SSD;
- duração dos testes.

Aumente para três ou quatro apenas se o hardware aguentar sem swap excessivo e sem thermal throttling.

## NeuroTrack como ambiente de testes

Stack sugerida:

```text
reverse proxy
├── /api  → NeuroTrack_MS
└── /     → NeuroTrack_Web

NeuroTrack_MS
├── MongoDB
├── Redis
└── serviços auxiliares
```

O APK pode usar uma base URL privada, por exemplo:

```text
https://neurotrack-central.<rede-privada>/api
```

Mantenha MongoDB e Redis acessíveis apenas pela rede Docker. Exponha somente a API ou o reverse proxy.

## Deploy de teste

Fluxo recomendado:

```text
PR validado
→ merge
→ workflow de deploy no runner central
→ docker compose pull/build
→ docker compose up -d
→ smoke test
→ health check no painel
```

Mantenha arquivos separados:

```text
compose.yaml
compose.test.yaml
compose.production.yaml
```

No notebook, use o ambiente de teste, não o de produção pública.

## Acesso remoto

Preferência:

```text
VPN privada
→ SSH
→ painel
→ APIs de teste
```

Não faça port-forward público de:

- SSH;
- dashboard;
- MongoDB;
- Redis;
- Docker socket;
- painéis administrativos.

Reserve IP no DHCP do roteador para facilitar o acesso na LAN.

## Codex e AgentsOrch trabalhando continuamente

Use um usuário dedicado sem sudo:

```text
codex-runner
```

Limites mínimos:

- sem acesso irrestrito ao host;
- workspaces separados;
- timeout por tarefa;
- limite de CPU e memória quando containerizado;
- lista explícita de repositórios permitidos;
- nenhuma alteração de workflow sem autorização;
- nenhum acesso ao Docker socket para código não confiável;
- logs e auditoria de comandos;
- segredos separados por projeto.

O AgentsOrch pode coordenar filas e metas, mas executores autônomos devem operar em containers ou usuários isolados.

## Energia e hardware

O notebook tende a ser mais adequado para ficar ligado continuamente do que um PC gamer, mas a decisão deve ser confirmada medindo o consumo real com tomada inteligente ou wattímetro.

Cuidados:

- usar SSD saudável;
- limpar ventoinha e entradas de ar;
- manter o notebook aberto ou bem ventilado;
- configurar ação da tampa para não suspender;
- limitar carga da bateria, se o modelo suportar;
- monitorar temperatura;
- habilitar reinício automático após queda de energia, quando suportado;
- manter backup externo.

A bateria pode ajudar em quedas curtas, mas não substitui backup nem UPS para modem/roteador.

## Observabilidade mínima

O painel de runners já cobre:

- runners e grupos;
- processos;
- RAM;
- load;
- disco;
- cache;
- logs;
- recomendações.

Para a central completa, evoluir depois com:

- temperatura;
- SMART do SSD;
- estado dos containers;
- health das APIs;
- filas de jobs;
- consumo de energia;
- backups recentes;
- disponibilidade da rede.

## Fases

### Fase 1 — central básica

- Ubuntu Server LTS;
- SSH;
- Docker Engine e Compose;
- VPN privada;
- runners do AgentsOrch e NeuroTrack;
- dashboard;
- NeuroTrack em Docker Compose.

### Fase 2 — operação confiável

- systemd para runners e dashboard;
- backups automáticos;
- health checks;
- reverse proxy privado;
- monitoramento de temperatura e disco;
- limite de concorrência.

### Fase 3 — capacidade sob demanda

- PC gamer como grupo `heavy`;
- Wake-on-LAN;
- notebook acorda/desliga o PC gamer conforme fila;
- AgentsOrch distribui trabalho por capacidade;
- ambientes descartáveis por branch quando necessário.

## Resultado esperado

```text
Notebook
→ central sempre ligada, econômica e previsível

PC gamer
→ estação manual e executor pesado sob demanda

GitHub Actions
→ orquestra PRs e checks

AgentsOrch
→ coordena metas, filas e automações

Docker Compose
→ hospeda ambientes de teste
```
