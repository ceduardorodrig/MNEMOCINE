---
tags: [homelab, env, sops, backup, secrets]
---

# Centralização de Segredos (.env) com sops/age

Convenção para centralizar os `.env`/segredos espalhados do homelab num **store único criptografado** (sops/age), com geração dos `.env` por serviço. Estabelecido em **09/08/2026**.

## Arquitetura

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

> ⚠️ **Chave privada age = acesso a TODOS os segredos.** Não sai do psicopompo; o backup em `age-keys-backup.txt` é local. Se perder, o store criptografado fica ilegível (o plaintext `secrets.env` é o fallback).

## Workflow

**Extrair um valor** (ex: para o deploy):
```bash
/mnt/NVME_PCI/secrets/sops-decrypt.sh CRAFTY_API_KEY
```

**Adicionar/editar um segredo:**
1. Editar `/mnt/NVME_PCI/secrets/secrets.env` (plaintext, 0600).
2. Re-criptografar:
   ```bash
   AGE_KEY=$(grep -oE "age1[a-z0-9]+" ~/.config/sops/age/keys.txt | head -1)
   sops --encrypt --age "$AGE_KEY" --input-type dotenv --output-type dotenv \
     /mnt/NVME_PCI/secrets/secrets.env > /mnt/NVME_PCI/agentic-ai/mnemocine/secrets.enc.env
   ```
3. Rodar `/mnt/NVME_PCI/secrets/gen-envs.sh` → gera os `.env` por serviço.

**Deploy dos .env gerados** (documentado no gen-envs.sh):
```bash
scp secrets/generated/zomboid.env   kavure:/srv/data/zomboid/.env        # + chown kavure:kavure
scp secrets/generated/homepage.env  ybytu:/home/ubuntu/homelab/homepage/config/.env
scp secrets/generated/sumaenima.env kavure:/srv/data/sumaenimahub/SUMAENIMA-HUB/.env
cp  secrets/generated/sumaenima.env /mnt/NVME_PCI/homelab/sumaenimahub/sumaenima-hub/.env
scp secrets/generated/sumaenima.env ybyra:/home/ubuntu/homelab/sumaenima/.env   # subset Sumænimá (edge/SPA)
```

## Inventário

| Serviço | Arquivo | No store? | Prefixo |
|---|---|---|---|
| Sumænimá sae-core | `SUMAENIMA-HUB/.env` (psicopompo + kavure) | ✅ | (direto) |
| Sumænimá edge/SPA | `/home/ubuntu/homelab/sumaenima/.env` (ybyra) | ✅ subset coberto | (direto) |
| Zomboid | `/srv/data/zomboid/.env` (kavure) | ✅ | `ZOMBOID_*` |
| Homepage | `config/.env` (ybytu) | ✅ | `CRAFTY_API_KEY` |
| Zomboid Panel | `/srv/data/zomboid-panel/.env` (kavure) | ⚠️ só config (sem segredos) | — |
| Minecraft (crafty) | config em `crafty.sqlite` | n/a (DB, não .env) | — |
| n8n | `/srv/data/n8n/.env` (kavure) | ✅ | `N8N_*` |
| SearXNG | `/srv/data/searxng/.env` (kavure) | ✅ | `SEARXNG_*` |
| Monitoring | `/srv/data/monitoring/.env` (kavure) | ✅ | `GRAFANA_ADMIN_PASSWORD` |
| Git push GitHub (espelho configs) | `~/.git-credentials` (edu, 0600) | ✅ 21/09 | `GH_PUSH_TOKEN` |
| Backup de migração | `zomboid-server-kavure/archive/migration-20260805/.env` | n/a (histórico em archive) | — |

## Segredos NÃO-.env (28/08/2026 — migrados para o store)

Segredos em configs não-`.env` (XML/JSON/YAML) agora **capturados no store** com restauração via
`inject-secrets.sh` (helper em `/mnt/NVME_PCI/secrets/`):

| Segredo | Var no store | Origem (config do host) | Restore |
|---|---|---|---|
| Lidarr API key | `LIDARR_API_KEY` | kuaray `config.xml` (`<ApiKey>`) | `inject-secrets.sh` |
| Prowlarr API key | `PROWLARR_API_KEY` | kuaray `config.xml` (`<ApiKey>`) | `inject-secrets.sh` |
| Transmission RPC | `TRANSMISSION_RPC_PASSWORD` | kuaray `settings.json` (`rpc-password`, **hash+salt** — restaurar verbatim preserva a senha) | `inject-secrets.sh` |
| Home Assistant | `HA_SOME_PASSWORD` | kavure `secrets.yaml` (`some_password`) | `inject-secrets.sh` |

**Não são lacunas (verificado 28/08/2026):**
- **slskd.yml** (kuaray) — **vazio** (0 linhas), sem segredo real.
- **soularr/config.ini** (kuaray) — **inexistente** (só `compose.yml`).
- **Uptime Kuma / AdGuard** (ybytu) — senhas são **hash** (bcrypt/sha) em DB/yaml, **não reutilizáveis** → não vão ao store; tratar com **reset de senha** (ver docs dos serviços).

> **Uso do helper:** `inject-secrets.sh` (dry-run: `--dry-run`) lê do store e injeta os valores de
> volta nos configs dos hosts com backup `.bak` — roda **apenas em restore** (nunca em operação normal).

## Segurança

- `.stignore` do vault já exclui `.env`, `.env.*`, `secrets/` — **nunca** incluir segredos em notas do vault (só o `secrets.enc.env` criptografado + `.env.template`).
- O `BORG_PASSPHRASE` do Sumænimá foi trocado do placeholder (`CHANGE_ME_STRONG_PASSWORD`) para uma passphrase forte (09/08/2026) — repo re-keyed, sentinel re-deployado.
