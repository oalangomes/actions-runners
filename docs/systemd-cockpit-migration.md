# Migração dos runners para systemd + Cockpit

## Objetivo

A primeira evolução da central de runners não troca os runners nem os toolchains atuais.

A mudança é somente de **lifecycle operacional**:

```text
antes
runners.sh
  -> PID files
  -> ps/awk
  -> run.sh
  -> logs próprios
  -> dashboard.py

depois
runner-services.sh
  -> svc.sh oficial do GitHub Runner
  -> systemd
  -> journalctl
  -> Cockpit (UI)
```

O `runners.conf`, as pastas de runner, labels, perfis e caches continuam sendo usados.

O dashboard antigo permanece disponível durante a migração.

## Por que systemd

O GitHub Actions Runner gera `svc.sh` depois que o runner é registrado. Em Linux com systemd, esse é o mecanismo oficial para instalar o runner como serviço.

Benefícios:

- inicialização automática no boot;
- restart e stop previsíveis;
- uma unit por runner;
- eliminação gradual de PID files próprios;
- logs via journal;
- operação via CLI padrão (`systemctl`) ou UI (Cockpit).

## Pré-requisitos

Verifique:

```bash
systemctl --version
test -d /run/systemd/system
```

No WSL, se systemd ainda não estiver habilitado, crie/ajuste:

```ini
# /etc/wsl.conf
[boot]
systemd=true
```

Depois, no PowerShell:

```powershell
wsl --shutdown
```

Abra a distro novamente.

## Validar antes de migrar

```bash
cd /home/alangomes/actions-runners

chmod +x runner-services.sh setup-cockpit.sh

./runner-services.sh doctor all
./runner-services.sh list
```

`list` mostra runners ainda em modo `legacy` e runners já instalados como serviço.

## Migrar um único runner primeiro

Não migre todos de uma vez.

Comece por uma instância de menor risco, por exemplo:

```bash
./runner-services.sh migrate agentsorchnext-2
```

A operação:

1. pede ao `runners.sh` atual para parar a instância;
2. executa o `svc.sh install` oficial;
3. cria um drop-in systemd com o ambiente de cache atual;
4. habilita a unit no boot;
5. inicia a unit;
6. confirma que ela ficou `active`.

Status:

```bash
./runner-services.sh status agentsorchnext-2
```

Logs:

```bash
./runner-services.sh logs agentsorchnext-2
```

O nome real da unit também fica no arquivo:

```bash
cat /home/alangomes/actions-runners/agentsorchnext-2/.service
```

E pode ser operado diretamente:

```bash
sudo systemctl status "$(cat agentsorchnext-2/.service)"
sudo journalctl -u "$(cat agentsorchnext-2/.service)" -f
```

## Migrar por grupo

Depois que uma instância estiver comprovada:

```bash
./runner-services.sh migrate group:agentsorch
./runner-services.sh status group:agentsorch
```

Depois:

```bash
./runner-services.sh migrate group:neurotrack
```

Evite `migrate all` na primeira execução.

## Cockpit

Cockpit substitui a necessidade de manter uma UI própria para:

- start/stop/restart de serviços;
- inspeção de units;
- journal/logs;
- CPU;
- memória;
- disco;
- processos;
- visão geral do host.

Instalação opcional:

```bash
./setup-cockpit.sh install
```

Acesso local:

```text
https://127.0.0.1:9090
```

O certificado inicial pode ser autoassinado.

### Segurança

Não publique a porta 9090 diretamente na internet.

Para acesso remoto, prefira uma rede privada/VPN (por exemplo Tailscale/WireGuard) e firewall.

O Cockpit usa as permissões do usuário Linux e systemd/Polkit. Não crie uma conta administrativa exclusiva sem necessidade.

## Cache

A central já possui `runner-cache-env.sh`.

Na instalação do serviço, `runner-services.sh` gera um snapshot de variáveis de cache em:

```text
.runner-service-env/<runner>.env
```

e instala um drop-in da unit:

```text
/etc/systemd/system/<unit>.d/10-actions-runners-cache.conf
```

Esse diretório local não deve ser versionado.

Se mudar o perfil/cache, execute novamente:

```bash
./runner-services.sh install <runner>
sudo systemctl restart "$(cat <runner>/.service)"
```

## Rollback

Para voltar uma instância ao gerenciamento legado:

```bash
./runner-services.sh uninstall agentsorchnext-2
./runners.sh start agentsorchnext-2
```

`uninstall` remove somente a integração com systemd. Ele não remove o registro do runner no GitHub nem a pasta local.

## Estratégia recomendada

### P0

- systemd para lifecycle;
- journalctl para logs;
- Cockpit para UI;
- scripts antigos preservados.

### P1

Depois de todos os runners estáveis em systemd:

- fazer `runners.sh` delegar start/stop/restart/status ao systemd;
- retirar PID files e process hunting;
- reduzir `dashboard.py` ou aposentá-lo.

### P2

Quando a central migrar para um host Ubuntu dedicado e houver necessidade real de runners efêmeros/scale-to-zero:

- avaliar GARM + Incus/LXD;
- não introduzir Kubernetes somente para runners.

## O que não muda

Workflows continuam usando as labels atuais. Nenhum repositório consumidor precisa mudar apenas por causa desta migração.
