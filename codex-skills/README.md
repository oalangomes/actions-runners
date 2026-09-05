# Codex Skills — Actions Runners

Skills operacionais para orientar Codex/agents em tarefas recorrentes deste repositório.

## Skills disponíveis

| Skill | Quando usar |
|---|---|
| [`create-new-runner.md`](create-new-runner.md) | Criar, registrar ou adicionar mais um self-hosted runner local sem sobrescrever runners existentes. |
| [`evaluate-runner-logs.md`](evaluate-runner-logs.md) | Avaliar runs/checks/logs, classificar GitHub-hosted vs self-hosted e recomendar melhorias no runner local. |
| [`start-project-runners-before-pr/SKILL.md`](start-project-runners-before-pr/SKILL.md) | Antes de criar uma PR, iniciar e validar apenas os self-hosted runners configurados para o repositório atual. |

## Regras gerais

- Não sobrescrever runner existente sem `--replace` explícito.
- Não iniciar dois processos na mesma pasta de runner.
- Não mover caches duráveis para dentro de `_work`.
- Não afirmar que um job rodou localmente sem evidência no log.
- Não alterar workflows durante uma análise de logs sem autorização explícita.

## Instalar a skill de pre-PR globalmente no Codex

A skill `start-project-runners-before-pr` usa o formato nativo de skills do Codex (`<skill>/SKILL.md`) e pode ser copiada para o diretório global:

```bash
mkdir -p ~/.codex/skills/start-project-runners-before-pr
cp codex-skills/start-project-runners-before-pr/SKILL.md \
  ~/.codex/skills/start-project-runners-before-pr/SKILL.md
```

Depois, novas sessões do Codex podem dispará-la quando estiverem prestes a criar/publicar uma pull request.
