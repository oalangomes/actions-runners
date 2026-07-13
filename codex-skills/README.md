# Codex Skills — Actions Runners

Skills operacionais para orientar Codex/agents em tarefas recorrentes deste repositório.

## Skills disponíveis

| Skill | Quando usar |
|---|---|
| [`create-new-runner.md`](create-new-runner.md) | Criar, registrar ou adicionar mais um self-hosted runner local sem sobrescrever runners existentes. |
| [`evaluate-runner-logs.md`](evaluate-runner-logs.md) | Avaliar runs/checks/logs, classificar GitHub-hosted vs self-hosted e recomendar melhorias no runner local. |

## Regras gerais

- Não sobrescrever runner existente sem `--replace` explícito.
- Não iniciar dois processos na mesma pasta de runner.
- Não mover caches duráveis para dentro de `_work`.
- Não afirmar que um job rodou localmente sem evidência no log.
- Não alterar workflows durante uma análise de logs sem autorização explícita.
