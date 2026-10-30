---
tags: [homelab, env, sops, backup, secrets]
pending: [HB-026, HB-051, HB-072]
---

# Centralized Secrets Management (.env) with SOPS/age

Standard for consolidating distributed `.env` files and credentials into a **single encrypted store** using SOPS and age, with automated per-service generation. Established on **2026-08-09**.

## Architecture

```
age Private Keys — TWO recipients since 2026-10-13 (DR "Rota A"), NEVER synchronized
  psicopompo  ~/.config/sops/age/keys.txt  ← primary (same-host convenience copy: /mnt/NVME_PCI/secrets/age-keys-backup.txt)
  kavure      ~/.config/sops/age/keys.txt  ← 2nd recipient: the store stays decryptable if psicopompo is LOST
  (the store decrypts with EITHER key; the cold OFFLINE copy is still pending — see recovery/psicopompo-loss.md §2 G1 / HB-064)

Central Master Store (psicopompo, plaintext, permissions 0600, NEVER synchronized)
  /mnt/NVME_PCI/secrets/secrets.env  ← Master source for all environment keys

Encrypted Store (SYNCHRONIZED via Syncthing — safe because it is ciphertext)
  mnemocine/secrets.enc.env          ← Managed via rules in mnemocine/.sops.yaml

Operational Helpers (psicopompo, permissions 0700)
  /mnt/NVME_PCI/secrets/sops-decrypt.sh   # Extracts values: sops-decrypt.sh <VAR>
  /mnt/NVME_PCI/secrets/gen-envs.sh       # Generates per-service .env files into secrets/generated/
```

> ⚠️ **age Private Key = access to ALL secrets.** The store is encrypted to **two** age recipients
> — **psicopompo** and **kavure** (since 2026-10-13) — so it decrypts with **either** key: losing
> one host no longer loses the vault. `age-keys-backup.txt` (psicopompo) is a same-host convenience
> copy, **not** an off-host backup; the **cold offline copy** (KeePassXC / USB) is still **pending**
> — see [`../recovery/psicopompo-loss.md`](../recovery/psicopompo-loss.md) §2 G1 · HB-064.

## Workflow

**Extracting a Single Value** (e.g., during script deployment):
```bash
/mnt/NVME_PCI/secrets/sops-decrypt.sh CRAFTY_API_KEY
```

**Adding or Updating a Secret:**
1. Edit `/mnt/NVME_PCI/secrets/secrets.env` (plaintext, permissions `0600`).
2. Re-encrypt into the vault repository — **let `mnemocine/.sops.yaml` supply the recipients**:
   ```bash
   cd /mnt/NVME_PCI/agentic-ai/mnemocine        # run from here: SOPS discovers .sops.yaml from the CWD
   sops --encrypt --input-type dotenv --output-type dotenv \
     /mnt/NVME_PCI/secrets/secrets.env > secrets.enc.env
   ```
   > ⚠️ **Never pass `--age` on the command line.** A CLI recipient **overrides** `mnemocine/.sops.yaml`
   > (SOPS docs: *"the configuration file is ignored when … parameters are passed on the SOPS command
   > line"*), which would re-encrypt to a **single** key and silently **drop the kavure recipient** —
   > re-breaking host-loss recovery (HB-064). `.sops.yaml` is the single source of truth for recipients.
   > After re-encrypting, confirm the store still lists **both** recipients:
   > `rg -c 'sops_age__list_[0-9]+__map_recipient=' secrets.enc.env` → **2**.
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
| Sumænimá edge/SPA | `/home/ubuntu/homelab/sumaenima/.env` (ybyra) | ✅ Strict Least-Privilege (HB-082) | `TS_EDGE_AUTH_KEY`, `UMAMI_DB_PASSWORD` |
| Zomboid | `/srv/data/zomboid/.env` (kavure) | ✅ | `ZOMBOID_*` |
| Homepage | `config/.env` (ybytu) | ✅ | `CRAFTY_API_KEY` |
| Zomboid Panel | `/srv/data/zomboid-panel/.env` (kavure) | ⚠️ Config only (no secrets) | — |
| Minecraft (crafty) | Config in `crafty.sqlite` | N/A (SQLite, not .env) | — |
| n8n (Homelab) | `/srv/data/n8n/.env` (kavure) | ✅ | `N8N_*` |
| n8n (Miracena) | `/srv/data/miracena/.env` (kuaray) | ✅ | `N8N_*` (shared stack env) |
| SearXNG | `/srv/data/searxng/.env` (kavure) | ✅ | `SEARXNG_*` |
| Monitoring | `/srv/data/monitoring/.env` (kavure) | ✅ | `GRAFANA_ADMIN_PASSWORD` |
| **Docker Registry** (psicopompo) | `~/homelab/registry/auth/htpasswd` (bcrypt — derived) | ✅ 2026-09-29 | `REGISTRY_USER`, `REGISTRY_PASSWORD` |
| Git Push GitHub (config mirror) | `~/.git-credentials` (edu, 0600) | ✅ 2026-09-21 | `GH_PUSH_TOKEN` |
| **Tailscale — ACL GitOps** | Secrets in `MNEMOCINE-ACL` repo (GitHub Actions) | ✅ 2026-09-29 | `TS_OAUTH_ID`, `TS_AUDIENCE`, `TS_TAILNET` |
| Migration Archive | `zomboid-server-kavure/archive/migration-20260805/.env` | N/A (historical archive) | — |
| **Oracle Cloud (OCI)** | `~/.oci/config` + private key (psicopompo) | ✅ 2026-10-08 | `OCI_*` |
| **Tailscale — Funnel Auth Key (edge)** | `edge.yml` via `${TS_AUTH_KEY}` | ✅ 2026-10-08 | `TS_AUTH_KEY` |
| **Miracena — Directus static token** | Referenced from `services/miracena-stack.md` | ✅ 2026-10-13 | `MIRACENA_DIRECTUS_TOKEN` |

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

## Secret Hygiene Findings (HB-051) — 2026-10-13

Reconnaissance recorded three secret-hygiene gaps. The Directus token is remediated here; the
`TS_AUTH_KEY` was rotated the same day, but the replacement value was then exposed in a chat
session (see (a)) — the owner **accepted that exposure risk on 2026-10-13** instead of rotating a
second time; the `authorized_keys` cleanup is a recommendation only (files deliberately
untouched).

### (a) `TS_AUTH_KEY` in the running `sae-edge_tunnel` service spec — rotated 2026-10-13; second rotation declined (risk accepted)

**Finding.** The `sae-edge` stack passes the Tailscale auth key as an *inline environment
variable* (`TS_AUTH_KEY: ${TS_AUTH_KEY}` in `provisioning/stacks/edge.yml`, services `tunnel`
and `tunnel-standby`). `docker stack deploy` bakes the resolved value into the service spec, so it
is readable by anyone with Docker API access (`docker service inspect`) and persisted in the
Swarm **Raft log** — and therefore in every manager snapshot/backup.

Verified 2026-10-13 (key **name** only — the value is never printed):

```bash
ssh kavure 'docker service inspect sae-edge_tunnel \
  --format "{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}"'
# → TS_AUTH_KEY=<redacted>  (61-char tskey…), TS_HOSTNAME, TS_STATE_DIR, TS_USERSPACE, TS_SERVE_CONFIG
```

> ✅ **Rotated 2026-10-13 (14:10).** A replacement key was generated, written to the master
> `secrets.env` **and** the encrypted store, and the `sae-edge` stack was redeployed: the running
> spec's key now **matches the store** (compared by SHA-256 of the value — never by value). A
> **new `TS_API_TOKEN`** was added to the store the same day. The pre-rotation store is kept as
> `mnemocine/secrets.enc.env.bak-rotacao-2026-10-13-1410` (rollback point — delete once stable;
> it still contains the **old** key, so it is itself a hygiene item).
>
> ⚠️ **Exposure risk accepted — no second rotation (owner decision, 2026-10-13).** The replacement
> values were **pasted into a chat session**, so they are treated as exposed. The advice to rotate
> again **stands and remains valid**, but the owner has **deliberately chosen not to** follow it
> here. What the exposed key implies while it stays in place: its value is known to anyone with
> access to that chat thread (transcript, logs, tool history), and it remains embedded **inline**
> in the service spec and the Swarm Raft log/snapshots as described above — so the exposure window
> and blast radius are unchanged until a future rotation. This is a **documented, reversible
> decision**: reverting it is cheap and carries no architectural change — run the procedure below
> at any time to generate and deploy a fresh key. The durable fix (moving the key out of the
> inline environment into a Docker secret) remains the hardening step in *Proposed hardening*.

**Rotation procedure (owner + operator):**

1. **Console (owner).** Create a new auth key tagged `tag:edge`; mark it **ephemeral** for the
   standby so a decommissioned failover leaves no orphan node. Never click *"Disable key expiry"*
   on an already-expired device (see `tailnet-acl-runbook.md` §8).
2. **Store.** Update `TS_AUTH_KEY` in the SOPS store (never inline it) through the master
   `secrets.env` + re-encrypt workflow above.
3. **Redeploy.** `docker stack deploy -c edge.yml sae-edge` from the provisioning directory so the
   containers re-authenticate with the new key.
4. **Revoke.** Delete the old key in the console **after** the stack re-authenticates.
5. **Verify.** `docker exec <tunnel-task> tailscale status` shows the node as tagged and connected;
   confirm the old key is gone from the console.

**Proposed hardening (text only — NOT applied).** Stop passing the key inline and inject it as a
**Docker secret** materialised from the SOPS store at deploy time. The Tailscale container natively
reads the key from a file via `TS_AUTHKEY_FILE` (or `TS_AUTHKEY=file:/…`), so no entrypoint shim is
needed on current images:

```yaml
# edge.yml (proposed)
services:
  tunnel:
    environment:
      TS_AUTH_KEY_FILE: /run/secrets/ts_auth_key
    secrets:
      - ts_auth_key
secrets:
  ts_auth_key:
    external: true   # create once: printf %s "$(/mnt/NVME_PCI/secrets/sops-decrypt.sh TS_AUTH_KEY)" | docker secret create ts_auth_key -
```

Apply the same to `tunnel-standby`. This keeps the value **out of the service spec, the Raft log
and `docker service inspect`**; the secret is still readable inside the container at runtime, but
the exposure window and blast radius shrink substantially. Coordinate the compose change with the
edge stack owner before deploying.

### (b) Static Directus token moved out of the vault — remediated 2026-10-13

The literal token previously inlined in `services/miracena-stack.md` was moved to the SOPS store
under the key **`MIRACENA_DIRECTUS_TOKEN`**; the note now references the key name only. Retrieve it
with `/mnt/NVME_PCI/secrets/sops-decrypt.sh MIRACENA_DIRECTUS_TOKEN`. The same value was added to
the master `secrets.env` to keep the re-encrypt workflow lossless.

> ✅ **Master-store drift — reconciled 2026-10-13 (HB-056).** The master `secrets.env` was found
> **behind** the encrypted store by three keys (`GEMINI_API_KEY`, `BLUESKY_HANDLE`,
> `BLUESKY_APP_PASSWORD`), so running the re-encrypt step from the master as-is would have
> **dropped** them from the store. All three have live consumers — `hl-autopilot` injects them
> from the SOPS store at runtime (`provisioning/scripts/hl-autopilot`; `autopilot-publish` /
> `autopilot-providers`). The master was **backfilled from the store**, proved by **key name +
> SHA-256 of each value** (never by value). Both stores now carry the **same 93 keys** with **no
> value divergence** (`comm` of key names is empty; perms stay `0600`).
>
> **Guard against recurrence.** The trap is the blind `>` redirect in step 2 of *Adding or Updating
> a Secret*. After editing the master, confirm the re-encrypt **never shrinks** the store — compare
> key names before and after (`cut -d= -f1 | sort -u`), or merge additively instead of overwriting.
> A key that exists only in the store and not in the master is the signal to reconcile before
> encrypting.

### (c) SSH `authorized_keys` inventory — recommendation only (files NOT modified)

Fingerprints of the current client key and of every `authorized_keys` entry across the three
nodes, verified 2026-10-13:

| Host | File | Fingerprint (SHA256) | Comment | Assessment |
|---|---|---|---|---|
| psicopompo (current client key) | `~/.ssh/id_ed25519.pub` | `U3VF75dsdtt+CY4F96oS71X06g6FozSvs4PQA3xaSIs` | `edu@psicopompo` | — |
| psicopompo | `~/.ssh/authorized_keys` | `/Ry7XvbkZczypEogPEaIodholanjrb9BVuB6s/44s4k` | `kavure` | **Legitimate** — kavure's own user key (matches kavure `~/.ssh/id_ed25519.pub`); keep |
| kuaray | `~/.ssh/authorized_keys` | `GLg5fhclnN5FjgxdlrGTsrKf0VAGOjxrm0MheTLYnuE` | `edu@Psicopompo` | **Vestigial** — stale and duplicated ×2; superseded by the current key |
| kuaray | `~/.ssh/authorized_keys` | `U3VF75dsdtt+CY4F96oS71X06g6FozSvs4PQA3xaSIs` | `edu@psicopompo` | **Current key** — keep |
| kavure | `~/.ssh/authorized_keys` | `U3VF75dsdtt+CY4F96oS71X06g6FozSvs4PQA3xaSIs` | `edu@psicopompo` | **Current key** — keep |

**Verified behaviour.** A forced login with the current key succeeds on both LAN nodes:
`ssh -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 kuaray` → OK and `… kavure` → OK. Loopback to
`psicopompo` is refused **by design** (no inbound sshd for self). This contradicts the earlier
"LAN key login refused" note — the current key *is* authorised on kuaray and kavure.

**Recommendation.** Do **not** authorise a new key — it already works. Delete the two stale
`edu@Psicopompo` duplicates from **kuaray**'s `authorized_keys`, keeping the current `U3VF75ds…`
entry, to remove an obsolete credential from an exposed file. Keep kavure's and psicopompo's
entries unchanged. The removal is a host change and was deliberately **not** performed here.

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

---

## ⚠️ The `.sops.yaml` mirror in the `MNEMOCINE` git repo is **frozen** (2026-10-13, HB-072)

`/mnt/NVME_PCI/homelab/mnemocine/.sops.yaml` (repo `ceduardorodrig/MNEMOCINE`, fed from the vault by
the `docs(homelab): auto-sync documentation updates` job) holds a **second copy of the encryption
rules**. Two facts make it dangerous:

1. **The auto-sync copies only `*.md`** — verified in the commit stat: 44 files, all `.md`. So this
   `.sops.yaml` has been **frozen since the initial public release**, and it still carried **one**
   age recipient (`age1fgqzpez…`) while the vault copy gained the kavure key on 2026-10-13.
2. **`sops` discovers `.sops.yaml` from the current working directory.** An encrypt run started in
   that repo would re-encrypt `secrets.enc.env` for psicopompo's key **only**, silently dropping
   kavure and undoing the whole recovery net (HB-064 / G1) — with **no error and no warning**.

**Fixed 2026-10-13:** the mirror now matches the source of truth (2 recipients) and carries a header
saying *do not edit it here*. Repo commit `f4fffe7`. No secret was ever in that file — age
recipients are **public** keys (and the repo's `.env.template` holds variable **names** only).

**Source of truth:** the **vault** copy, `mnemocine/.sops.yaml`. Always run the re-encrypt from
inside `mnemocine/` so the vault's rules are the ones `sops` picks up, and **never** pass `--age`
(it overrides the file).

**Still open (HB-072):** the sync should either include non-`.md` governance files, or this mirror
should be **removed** so it can never mislead — a stale copy of a *security* rule is worse than none.
Until then: after any recipient change, **verify both copies** (and the store's
`sops_age__list_N__map_recipient` count) instead of assuming the mirror followed.
