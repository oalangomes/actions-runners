# Codex Skills — Actions Runners

Skills operacionais para orientar Codex/agents em tarefas recorrentes deste repositório.

## Skills disponíveis

| Skill | Quando usar |
|---|---|
| [`create-new-runner.md`](create-new-runner.md) | Criar, registrar ou adicionar mais um self-hosted runner local sem sobrescrever runners existentes. |
| [`evaluate-runner-logs.md`](evaluate-runner-logs.md) | Avaliar runs/checks/logs, classificar GitHub-hosted vs self-hosted e recomendar melhorias no runner local. |
| [`start-project-runners-before-pr/SKILL.md`](start-project-runners-before-pr/SKILL.md) | Antes de criar uma PR, iniciar e validar apenas os self-hosted runners configurados para o repositório atual. |
| [`manage-local-runners/SKILL.md`](manage-local-runners/SKILL.md) | Inventariar, iniciar/parar, diagnosticar e cadastrar runners locais para projetos pessoais. |

## Regras gerais

- Não sobrescrever runner existente sem `--replace` explícito.
- Não iniciar dois processos na mesma pasta de runner.
- Não mover caches duráveis para dentro de `_work`.
- Não afirmar que um job rodou localmente sem evidência no log.
- Não alterar workflows durante uma análise de logs sem autorização explícita.

## Instalar as skills globalmente no Codex

As skills usam o formato nativo `<skill>/SKILL.md`:

```bash
mkdir -p ~/.codex/skills/start-project-runners-before-pr
mkdir -p ~/.codex/skills/manage-local-runners

cp codex-skills/start-project-runners-before-pr/SKILL.md \
  ~/.codex/skills/start-project-runners-before-pr/SKILL.md

cp codex-skills/manage-local-runners/SKILL.md \
  ~/.codex/skills/manage-local-runners/SKILL.md
```

`start-project-runners-before-pr` cuida do gate automático antes de publicar PR.

`manage-local-runners` é a skill administrativa para inventário, health, start/stop, diagnóstico e cadastro de novos runners pessoais.
