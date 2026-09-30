---
tags: [homelab, service, adguard, dns]
---

# AdGuard Home

Servidor DNS com bloqueio de anúncios e rastreadores.

**Servidor:** ybytu
**Porta DNS:** `53` (TCP/UDP)
**Porta Admin:** `3000`
**URL:** `http://ybytu.chimaera-heptatonic.ts.net:3000`

## Instância

Roda tanto como **container Docker** quanto como **binário nativo** (`/opt/adguardhome/`). O nativo é a instância ativa em produção.

- Nativo: `/opt/adguardhome/AdGuardHome`
- Config: `/opt/adguardhome/conf/AdGuardHome.yaml`
- Work dir: `/opt/adguardhome/work`

## Acesso Admin

```
URL: http://ybytu.chimaera-heptatonic.ts.net:3000
```

- **Login:** a senha admin é **hash (bcrypt)** no `AdGuardHome.yaml` (`users:`) — **não vai ao store sops** (não reutilizável).
- **Reset de senha (28/08/2026):** gerar novo hash bcrypt e injetar no YAML:
  ```bash
  htpasswd -B -C 10 -n -b admin '<NOVA_SENHA>'      # ou: mkpasswd -m bcrypt -R 10 '<NOVA_SENHA>'
  ```
  Copiar a parte `$2y$...` para `users:` → `password:` no `/opt/adguardhome/conf/AdGuardHome.yaml` e `systemctl restart adguardhome`. Ver [wiki de configuração do AdGuard Home](https://github.com/AdguardTeam/AdGuardHome/wiki/Configuration#reset-web-password).

## Listas de Bloqueio

Listas ativas (verificar no admin — podem ter mudado):
- AdGuard DNS filter
- OISD basic
- ...

## Manutenção

```bash
# Verificar status
systemctl status adguardhome

# Nativo
/opt/adguardhome/AdGuardHome -s start|stop|restart|status

# Ou pelo serviço systemd do filebrowser (mesmo host)
```

## Logs

`/opt/adguardhome/work/data/querylog.json` (desabilitar ou limitar em produção com 1GB de RAM)
