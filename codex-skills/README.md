# Legacy Codex notes

Este diretório foi criado quando as automações eram tratadas como específicas do Codex.

As skills canônicas e portáveis agora vivem em:

```text
../skills/
├── start-project-runners-before-pr/SKILL.md
└── manage-local-github-runners/SKILL.md
```

Instale-as com:

```bash
./install-agent-skills.sh --tool codex
```

O mesmo conteúdo pode ser distribuído para Copilot CLI, Claude Code e implementações compatíveis com Agent Skills.

Os arquivos Markdown legados abaixo permanecem apenas como referência histórica:

- `create-new-runner.md`
- `evaluate-runner-logs.md`

Novas automações devem preferir `skills/<name>/SKILL.md`.
