---
tags: [homelab, service, adguard, dns]
---

# AdGuard Home

DNS server with ad and tracker blocking.

**Server:** ybytu
**DNS Port:** `53` (TCP/UDP)
**Admin Port:** `3000`
**URL:** `http://ybytu.chimaera-heptatonic.ts.net:3000`

## Instance

Runs both as a **Docker container** and as a **native binary** (`/opt/adguardhome/`). The native one is the instance active in production.

- Native: `/opt/adguardhome/AdGuardHome`
- Config: `/opt/adguardhome/conf/AdGuardHome.yaml`
- Work dir: `/opt/adguardhome/work`

## Admin Access

```
URL: http://ybytu.chimaera-heptatonic.ts.net:3000
```

- **Login:** the admin password is a **hash (bcrypt)** in `AdGuardHome.yaml` (`users:`) — it **does not go into the sops store** (not reusable).
- **Password reset (28/08/2026):** generate a new bcrypt hash and inject it into the YAML:
  ```bash
  htpasswd -B -C 10 -n -b admin '<NOVA_SENHA>'      # ou: mkpasswd -m bcrypt -R 10 '<NOVA_SENHA>'
  ```
  Copy the `$2y$...` part into `users:` → `password:` in `/opt/adguardhome/conf/AdGuardHome.yaml` and `systemctl restart adguardhome`. See [AdGuard Home configuration wiki](https://github.com/AdguardTeam/AdGuardHome/wiki/Configuration#reset-web-password).

## Blocklists

Active lists (check in the admin — they may have changed):
- AdGuard DNS filter
- OISD basic
- ...

## Maintenance

```bash
# Verificar status
systemctl status adguardhome

# Nativo
/opt/adguardhome/AdGuardHome -s start|stop|restart|status

# Ou pelo serviço systemd do filebrowser (mesmo host)
```

## Logs

`/opt/adguardhome/work/data/querylog.json` (disable it or limit it in production with 1GB of RAM)
