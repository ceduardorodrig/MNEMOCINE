---
tags: [homelab, servico, n8n, automacao, miracena, kuaray]
---

# n8n

Automação visual (workflows) — "Zapier caseiro". Conecta Gmail, Sheets, IA, webhooks e serviços do homelab.

**Servidor:** kuaray (parte da stack Miracena)
**Porta:** `5678`
**URL interna:** `http://kuaray.chimaera-heptatonic.ts.net:5678` · `http://100.94.209.99:5678`
**Basic Auth:** ativo (`N8N_BASIC_AUTH_*` — ver store sops)

> **Migrado (10/09/2026):** de stack standalone (`/srv/data/n8n/`) para stack Miracena (`/srv/data/miracena/`). Compartilha PostgreSQL com Directus (bancos separados: `n8n` e `miracena`). Database vazio na migração (0 workflows, 0 credentials).

> **Migrado (04/10/2026):** stack Miracena inteira (incl. n8n) kavure → **kuaray** (liberar RAM/disco). Efeitos colaterais corrigidos em 09/10: o job `n8n` do Prometheus ainda scrapeava o alvo antigo do kavure (→ alertas `n8nDown`/`PrometheusDown` a cada 4h, alvo corrigido p/ `100.94.209.99:5678`) e o `hl-n8n-backup.timer` do kavure falhava todo dia (unit **desabilitada** — o dump agora é do `hl-miracena-backup` no kuaray).

## Stack

| Container | Imagem | Função |
|---|---|---|
| miracena-n8n | `docker.n8n.io/n8nio/n8n:stable` | Motor de workflows |
| miracena-postgres | `postgres:16-alpine` | Banco compartilhado (database `n8n`) |

- **PostgreSQL compartilhado** com Directus — mesma instância, bancos separados. Reduz overhead em ambiente com RAM limitada (12 GB).
- **`N8N_ENCRYPTION_KEY`** (no .env): criptografa as credenciais salvas nos workflows. **Perdê-la = credenciais ilegíveis** mesmo com o banco intacto. Backup no KeePass.
- `N8N_DEFAULT_BINARY_DATA_MODE=database`: anexos/binary ficam no Postgres → o `pg_dump` captura tudo.
- `N8N_METRICS=true`: expõe `/metrics` (Prometheus) — consumido pelo stack de observabilidade.
- `EXECUTIONS_DATA_PRUNE=true` + `MAX_AGE=336h`: retenção de execuções limitada (não enche o disco).
- **Basic Auth** ativo: acesso à UI exige usuário/senha (`N8N_BASIC_AUTH_USER`/`PASSWORD` do store).

## Acesso

- **Tailnet:** `http://kuaray.chimaera-heptatonic.ts.net:5678` (antes `kavure.*`, migrou 04/10)
- **Funnel:** não exposto publicamente (segurança) — webhooks públicos avaliar caso a caso.
- Primeiro acesso: criar a conta **owner** na UI (usuário admin do n8n).

## Configuração

```yaml
# /srv/data/miracena/docker-compose.yml (resumo do n8n; host: kuaray desde 04/10)
services:
  n8n:
    image: docker.n8n.io/n8nio/n8n:stable
    container_name: miracena-n8n
    env_file: .env
    ports: ["5678:5678"]
    volumes: [n8n_data:/home/node/.n8n]
    depends_on:
      postgres: { condition: service_healthy }

  postgres:
    image: postgres:16-alpine
    container_name: miracena-postgres
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./postgres/init:/docker-entrypoint-initdb.d  # cria database n8n
```

O `.env` contém todas as variáveis (PostgreSQL, Directus, WordPress, n8n). Segredos via store sops.

## Backup

- **PostgreSQL compartilhado:** `pg_dump` do banco `n8n` via `docker exec miracena-postgres pg_dump -U n8n n8n` — roda no **kuaray** pelo `hl-miracena-backup.timer` (05:35 → NFS `miracena-server-kavure/daily/postgres-n8n-<data>.sql.gz`, 09:10 verificado: dump diário saudável).
  > ⚠️ O `hl-n8n-backup.timer` do **kavure** (05:25) ficou órfão após a migração 04/10 — gerava dumps de 20 bytes (pg_dump falhando) e unit `failed` todo dia. **Desabilitado em 09/10/2026** (mount NFS `/srv/data/n8n/offbox` e fstab também removidos).
- **Restore:** subir o stack com a mesma `N8N_ENCRYPTION_KEY` → `zcat n8n-<data>.sql.gz | docker exec -i miracena-postgres psql -U n8n -d n8n`. Testar periodicamente.
- Export rápido de workflows: `docker exec miracena-n8n n8n export:workflow --all --output=/home/node/.n8n/export`.

## Manutenção

- **Update:** conforme a stack Miracena no kuaray (ver [`miracena-stack`](miracena-stack.md)). Antes de major update, rodar backup do PostgreSQL manualmente.
- **Logs:** `docker logs miracena-n8n` / via Loki (kavure coleta dos hosts).

## See also
- [[miracena-stack]] — Stack completa (PostgreSQL compartilhado)
- [[monitoring]] — Prometheus consome `/metrics` do n8n
- [[searxng]] — pode virar mecanismo de busca nos workflows (formato JSON)
