---
tags: [homelab, meta]
---

# 🔒 Security Policy — Mnemocine

## Secrets Management

### .env

All secrets are stored in `.env` at the folder root. This file is **never versioned nor synced** —
a pasta não é um repo git (sem versionamento) e o Syncthing ignora `.env` via `.stignore`.
Use `.env.template` as a reference:

```bash
cp .env.template .env
# Edit .env with real values
```

### Placeholder Convention

Every sensitive value in documentation uses `{{PLACEHOLDER_NAME}}` format:

| Padrão | Exemplo |
|--------|---------|
| Senhas | `{{DB_PASSWORD}}` |
| Tokens | `{{STREMIO_ADDON_URL}}` |
| IPs internos | `{{TAILSCALE_PSICOPOMPO_IP}}` |
| Domínios | `{{TAILSCALE_FUNNEL_DOMAIN}}` |
| Emails | `{{OWNER_EMAIL}}` |

### What NOT to commit

- `.env` or any `.env.*` file (except `.env.template`)
- `*.key`, `*.pem`, `*.cert` files
- SSH private keys
- API tokens or secrets in plain text
- Real IPs or domains that expose internal infrastructure
- PII (personally identifiable information) of third parties

## Reporting

If you find a leaked secret in this folder, contact the owner directly.
