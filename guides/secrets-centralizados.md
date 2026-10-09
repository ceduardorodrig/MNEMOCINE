---
tags: [homelab, env, sops, backup, secrets]
---

# Centralized Secrets Management (.env) with SOPS/age

Standard for consolidating distributed `.env` files and credentials into a **single encrypted store** using SOPS and age, with automated per-service generation. Established on **2026-08-09**.

## Architecture

```
age Private Key (psicopompo only, NEVER synchronized)
  ~/.config/sops/age/keys.txt        ← ONLY mechanism to decrypt (backup in /mnt/NVME_PCI/secrets/age-keys-backup.txt)

Central Master Store (psicopompo, plaintext, permissions 0600, NEVER synchronized)
  /mnt/NVME_PCI/secrets/secrets.env  ← Master source for all environment keys

Encrypted Store (SYNCHRONIZED via Syncthing — safe because it is ciphertext)
  mnemocine/secrets.enc.env          ← Managed via rules in mnemocine/.sops.yaml

Operational Helpers (psicopompo, permissions 0700)
  /mnt/NVME_PCI/secrets/sops-decrypt.sh   # Extracts values: sops-decrypt.sh <VAR>
  /mnt/NVME_PCI/secrets/gen-envs.sh       # Generates per-service .env files into secrets/generated/
```

> ⚠️ **age Private Key = access to ALL secrets.** It never leaves psicopompo; `age-keys-backup.txt` is an offline local copy. If destroyed without backup, the encrypted vault is irrecoverable (the plaintext `secrets.env` acts as fallback).

## Workflow

**Extracting a Single Value** (e.g., during script deployment):
```bash
/mnt/NVME_PCI/secrets/sops-decrypt.sh CRAFTY_API_KEY
```

**Adding or Updating a Secret:**
1. Edit `/mnt/NVME_PCI/secrets/secrets.env` (plaintext, permissions `0600`).
2. Re-encrypt into the vault repository:
   ```bash
   AGE_KEY=$(grep -oE "age1[a-z0-9]+" ~/.config/sops/age/keys.txt | head -1)
   sops --encrypt --age "$AGE_KEY" --input-type dotenv --output-type dotenv \
     /mnt/NVME_PCI/secrets/secrets.env > /mnt/NVME_PCI/agentic-ai/mnemocine/secrets.enc.env
   ```
3. Run `/mnt/NVME_PCI/secrets/gen-envs.sh` → regenerates service-specific `.env` bundles.

**Deploying Generated Environment Files:**
```bash
scp secrets/generated/zomboid.env   kavure:/srv/data/zomboid/.env        # + chown kavure:kavure
scp secrets/generated/homepage.env  ybytu:/home/ubuntu/homelab/homepage/config/.env
scp secrets/generated/sumaenima.env kavure:/srv/data/sumaenimahub/SUMAENIMA-HUB/.env
cp  secrets/generated/sumaenima.env /mnt/NVME_PCI/homelab/sumaenimahub/sumaenima-hub/.env
scp secrets/generated/sumaenima.env ybyra:/home/ubuntu/homelab/sumaenima/.env   # Sumænimá edge/SPA subset
```

## Secret Inventory

| Service | Target File | Present in Store? | Variable Prefix |
|---|---|---|---|
| Sumænimá sae-core | `SUMAENIMA-HUB/.env` (psicopompo + kavure) | ✅ | Direct |
| Sumænimá edge/SPA | `/home/ubuntu/homelab/sumaenima/.env` (ybyra) | ✅ Covered subset | Direct |
| Zomboid | `/srv/data/zomboid/.env` (kavure) | ✅ | `ZOMBOID_*` |
| Homepage | `config/.env` (ybytu) | ✅ | `CRAFTY_API_KEY` |
| Zomboid Panel | `/srv/data/zomboid-panel/.env` (kavure) | ⚠️ Config only (no secrets) | — |
| Minecraft (crafty) | Config in `crafty.sqlite` | N/A (SQLite, not .env) | — |
| n8n | `/srv/data/n8n/.env` (kavure) | ✅ | `N8N_*` |
| SearXNG | `/srv/data/searxng/.env` (kavure) | ✅ | `SEARXNG_*` |
| Monitoring | `/srv/data/monitoring/.env` (kavure) | ✅ | `GRAFANA_ADMIN_PASSWORD` |
| **Docker Registry** (psicopompo) | `~/homelab/registry/auth/htpasswd` (bcrypt — derived) | ✅ 2026-09-29 | `REGISTRY_USER`, `REGISTRY_PASSWORD` |
| Git Push GitHub (config mirror) | `~/.git-credentials` (edu, 0600) | ✅ 2026-09-21 | `GH_PUSH_TOKEN` |
| **Tailscale — ACL GitOps** | Secrets in `MNEMOCINE-ACL` repo (GitHub Actions) | ✅ 2026-09-29 | `TS_OAUTH_ID`, `TS_AUDIENCE`, `TS_TAILNET` |
| Migration Archive | `zomboid-server-kavure/archive/migration-20260805/.env` | N/A (historical archive) | — |
| **Oracle Cloud (OCI)** | `~/.oci/config` + private key (psicopompo) | ✅ 2026-10-08 | `OCI_*` |
| **Tailscale — Funnel Auth Key (edge)** | `edge.yml` via `${TS_AUTH_KEY}` | ✅ 2026-10-08 | `TS_AUTH_KEY` |

## Non-.env Secret Handling (Migrated 2026-08-28)

Credentials in structured configurations (XML, JSON, YAML) are backed up inside the SOPS store and restored via `inject-secrets.sh` (located in `/mnt/NVME_PCI/secrets/`):

| Target Secret | Store Variable | Source Configuration | Restoration Method |
|---|---|---|---|
| Lidarr API Key | `LIDARR_API_KEY` | kuaray `config.xml` (`<ApiKey>`) | `inject-secrets.sh` |
| Prowlarr API Key | `PROWLARR_API_KEY` | kuaray `config.xml` (`<ApiKey>`) | `inject-secrets.sh` |
| Transmission RPC | `TRANSMISSION_RPC_PASSWORD` | kuaray `settings.json` (`rpc-password`, salt/hash) | `inject-secrets.sh` |
| Home Assistant | `HA_SOME_PASSWORD` | kavure `secrets.yaml` (`some_password`) | `inject-secrets.sh` |
| rclone / GDrive | `RCLONE_GDRIVE_REFRESH_TOKEN`, `_CLIENT_ID`, `_CLIENT_SECRET` | psicopompo `~/.config/rclone/rclone.conf` | `inject-secrets.sh` (local) |
| CrowdSec LAPI | `CROWDSEC_LAPI_LOGIN`, `_PASSWORD` | ybytu `crowdsec/config/local_api_credentials.yaml` | `inject-secrets.sh` |
| CrowdSec CAPI | `CROWDSEC_CAPI_LOGIN`, `_PASSWORD` | ybytu `crowdsec/config/online_api_credentials.yaml` | `inject-secrets.sh` |

> **Why rclone stores `refresh_token` instead of full `token`:** The `token` block contains transient access tokens refreshed every 60 minutes. The durable credential is the `refresh_token`. The restore script builds a minimal configuration, prompting rclone to acquire a new access token on first connection.

**Non-Secret Invariants (Verified 2026-08-28):**
- **slskd.yml** (kuaray) — Empty file (0 bytes), no credentials.
- **soularr/config.ini** (kuaray) — Non-existent (`compose.yml` only).
- **Uptime Kuma / AdGuard** (ybytu) — Passwords stored as irreversible bcrypt/sha hashes in databases/configs; recovered via password resets if needed.

> **Helper Usage:** `inject-secrets.sh` (supports dry-run: `--dry-run`) injects credentials into target configurations while retaining `.bak` backups. It is executed strictly during recovery drills.

## Oracle Cloud (OCI) API Key Integration (2026-10-08)

Oracle Cloud VMs (`ybytu`, `ybyra`) are managed via API directly from the terminal. The credential is an RSA key pair: the private key resides on **psicopompo**, with only the public key uploaded to OCI. The encrypted store manages `OCI_USER_ID`, `OCI_TENANCY_ID`, `OCI_FINGERPRINT`, `OCI_REGION`, and `OCI_PRIVATE_KEY_B64`.

**Restoration Helper:**
```bash
/mnt/NVME_PCI/secrets/oci-restore.sh
```

## Security Enforcement

- Syncthing ignore patterns (`.stignore`) strictly exclude `.env`, `.env.*`, and `secrets/`.
- Vault markdown notes must never contain raw credentials.

### Automated Governance Enforcement (`SEC-SECRETS` Rule)

StenioSentinel enforces `SEC-SECRETS` across the `homelab` and `vault` scopes. Any unencrypted credential discovered in a markdown or configuration file triggers an immediate fatal error during pre-commit passes.

### Minimum File Permissions

Sensitive configuration files must strictly enforce permissions `0600` (read/write by owner only):

| Host | Path | Enforcement |
|---|---|---|
| kavure | `/srv/data/miracena/.env` | `0600` |
| kavure | `/srv/data/zomboid-panel/.env` | `0600` |
| kavure | `/srv/data/homeassistant/config/secrets.yaml` | `0600` |
| ybyra | `/home/ubuntu/homelab/sumaenima/.env` | `0600` |
| ybytu | `/home/ubuntu/homelab/changedetection/data/secret.txt` | `0600` |
