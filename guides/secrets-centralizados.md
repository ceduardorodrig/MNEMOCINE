---
tags: [homelab, env, sops, backup, secrets]
---

# Centralized Secrets (.env) with sops/age

Convention for centralizing the `.env`/secrets scattered across the homelab into a **single encrypted store** (sops/age), with per-service generation of the `.env` files. Established on **09/08/2026**.

## Architecture

```
Chave privada age (psicopompo, NÃO sincroniza)
  ~/.config/sops/age/keys.txt        ← ÚNICA forma de decriptar (backup em /mnt/NVME_PCI/secrets/age-keys-backup.txt)

Store central (psicopompo, plaintext, 0600, NÃO sincroniza)
  /mnt/NVME_PCI/secrets/secrets.env  ← fonte master (todas as chaves)

Store criptografado (SINCRONIZA via Syncthing — seguro pois é cifrado)
  mnemocine/secrets.enc.env          ← regras em mnemocine/.sops.yaml

Helpers (psicopompo, 0700)
  /mnt/NVME_PCI/secrets/sops-decrypt.sh   # extrai valores: sops-decrypt.sh <VAR>
  /mnt/NVME_PCI/secrets/gen-envs.sh       # gera .env por serviço em secrets/generated/
```

> ⚠️ **age private key = access to ALL secrets.** It never leaves psicopompo; the backup in `age-keys-backup.txt` is local. If you lose it, the encrypted store becomes unreadable (the plaintext `secrets.env` is the fallback).

## Workflow

**Extract a value** (e.g.: for the deploy):
```bash
/mnt/NVME_PCI/secrets/sops-decrypt.sh CRAFTY_API_KEY
```

**Adding/editing a secret:**
1. Edit `/mnt/NVME_PCI/secrets/secrets.env` (plaintext, 0600).
2. Re-encrypt:
   ```bash
   AGE_KEY=$(grep -oE "age1[a-z0-9]+" ~/.config/sops/age/keys.txt | head -1)
   sops --encrypt --age "$AGE_KEY" --input-type dotenv --output-type dotenv \
     /mnt/NVME_PCI/secrets/secrets.env > /mnt/NVME_PCI/agentic-ai/mnemocine/secrets.enc.env
   ```
3. Run `/mnt/NVME_PCI/secrets/gen-envs.sh` → generates the per-service `.env` files.

**Deploying the generated .env files** (documented in gen-envs.sh):
```bash
scp secrets/generated/zomboid.env   kavure:/srv/data/zomboid/.env        # + chown kavure:kavure
scp secrets/generated/homepage.env  ybytu:/home/ubuntu/homelab/homepage/config/.env
scp secrets/generated/sumaenima.env kavure:/srv/data/sumaenimahub/SUMAENIMA-HUB/.env
cp  secrets/generated/sumaenima.env /mnt/NVME_PCI/homelab/sumaenimahub/sumaenima-hub/.env
scp secrets/generated/sumaenima.env ybyra:/home/ubuntu/homelab/sumaenima/.env   # subset Sumænimá (edge/SPA)
```

## Inventory

| Service | File | In the store? | Prefix |
|---|---|---|---|
| Sumænimá sae-core | `SUMAENIMA-HUB/.env` (psicopompo + kavure) | ✅ | (direct) |
| Sumænimá edge/SPA | `/home/ubuntu/homelab/sumaenima/.env` (ybyra) | ✅ subset covered | (direct) |
| Zomboid | `/srv/data/zomboid/.env` (kavure) | ✅ | `ZOMBOID_*` |
| Homepage | `config/.env` (ybytu) | ✅ | `CRAFTY_API_KEY` |
| Zomboid Panel | `/srv/data/zomboid-panel/.env` (kavure) | ⚠️ config only (no secrets) | — |
| Minecraft (crafty) | config in `crafty.sqlite` | n/a (DB, not .env) | — |
| n8n | `/srv/data/n8n/.env` (kavure) | ✅ | `N8N_*` |
| SearXNG | `/srv/data/searxng/.env` (kavure) | ✅ | `SEARXNG_*` |
| Monitoring | `/srv/data/monitoring/.env` (kavure) | ✅ | `GRAFANA_ADMIN_PASSWORD` |
| Git push to GitHub (config mirror) | `~/.git-credentials` (edu, 0600) | ✅ 21/09 | `GH_PUSH_TOKEN` |
| Migration backup | `zomboid-server-kavure/archive/migration-20260805/.env` | n/a (history in archive) | — |

## Non-.env Secrets (28/08/2026 — migrated to the store)

Secrets sitting in non-`.env` configs (XML/JSON/YAML) are now **captured in the store** with restoration via
`inject-secrets.sh` (helper in `/mnt/NVME_PCI/secrets/`):

| Secret | Var in the store | Source (host config) | Restore |
|---|---|---|---|
| Lidarr API key | `LIDARR_API_KEY` | kuaray `config.xml` (`<ApiKey>`) | `inject-secrets.sh` |
| Prowlarr API key | `PROWLARR_API_KEY` | kuaray `config.xml` (`<ApiKey>`) | `inject-secrets.sh` |
| Transmission RPC | `TRANSMISSION_RPC_PASSWORD` | kuaray `settings.json` (`rpc-password`, **hash+salt** — restoring verbatim preserves the password) | `inject-secrets.sh` |
| Home Assistant | `HA_SOME_PASSWORD` | kavure `secrets.yaml` (`some_password`) | `inject-secrets.sh` |

**These are not gaps (verified 28/08/2026):**
- **slskd.yml** (kuaray) — **empty** (0 lines), no real secret.
- **soularr/config.ini** (kuaray) — **nonexistent** (only `compose.yml`).
- **Uptime Kuma / AdGuard** (ybytu) — passwords are **hashes** (bcrypt/sha) in DB/yaml, **not reusable** → they do not go into the store; handle them with a **password reset** (see the service docs).

> **Using the helper:** `inject-secrets.sh` (dry-run: `--dry-run`) reads from the store and injects the values
> back into the host configs with a `.bak` backup — it runs **only on restore** (never in normal operation).

## Security

- The vault `.stignore` already excludes `.env`, `.env.*`, `secrets/` — **never** include secrets in vault notes (only the encrypted `secrets.enc.env` + `.env.template`).
- The Sumænimá `BORG_PASSPHRASE` was changed from the placeholder (`CHANGE_ME_STRONG_PASSWORD`) to a strong passphrase (09/08/2026) — repo re-keyed, sentinel re-deployed.
