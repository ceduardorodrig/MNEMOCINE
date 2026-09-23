---
tags: [homelab, servico, miracena, stack, docker, n8n, directus, wordpress, nuxt, kavure]
---

# Miracena - Stack de Infraestrutura

**Servidor:** Kavure (Dell OptiPlex 3060 SFF)
**Data de Deploy:** 10/09/2026
**Projeto Canônico & Governança:** Miracena (Incubação temporária no Homelab)
**Ambiente:** Servidor Kavure (instância dedicada isolada)

## Stack Deployada

| Serviço | Container | Porta | Imagem | Limite RAM | Limite CPU |
|---------|-----------|-------|--------|------------|------------|
| PostgreSQL | miracena-postgres | 5432 (interno) | postgres:16-alpine | 1 GB | 0.5 |
| Redis | miracena-redis | 6379 (interno) | redis:7-alpine | 128 MB | 0.25 |
| Directus | miracena-directus | 8055 | directus/directus:latest | 2 GB | 1.0 |
| Nuxt3 Frontend | miracena-nuxt | 3003 | node:22-alpine | 1 GB | 1.0 |
| Nginx Proxy Manager | miracena-nginx-proxy-manager | 81 (admin), 8180 (HTTP), 8445 (HTTPS) | jc21/nginx-proxy-manager:latest | 256 MB | 0.25 |
| WordPress | miracena-wordpress | 8085 | wordpress:latest | 512 MB | 0.5 |
| MariaDB | miracena-mariadb | 3306 (interno) | mariadb:11 | 512 MB | 0.25 |
| n8n | miracena-n8n | 5678 | docker.n8n.io/n8nio/n8n:stable | 1 GB | 0.5 |
| Tailscale Tunnel | miracena-tunnel | — | tailscale/tailscale:latest | 128 MB | 0.25 |

## Acessos

### Externo (via Tailscale Funnel — público, sem Tailscale necessário)
- **WordPress (site):** https://miracena.chimaera-heptatonic.ts.net/

### Interno (via Tailscale — requer Tailscale conectado)
- **Nuxt3 Frontend:** http://kavure.chimaera-heptatonic.ts.net:3003
- **WordPress:** http://kavure.chimaera-heptatonic.ts.net:8085
- **Directus:** http://kavure.chimaera-heptatonic.ts.net:8055
- **n8n:** http://kavure.chimaera-heptatonic.ts.net:5678
- **NPM Admin:** http://kavure.chimaera-heptatonic.ts.net:81

### Credenciais

#### Nginx Proxy Manager
- **Email:** ceduadorodrig@gmail.com
- **Senha:** (no .env — NPM_ADMIN_PASSWORD / SOPS)
- **URL:** http://kavure.chimaera-heptatonic.ts.net:81

#### n8n
- **Usuario:** edu
- **Senha:** (no .env — N8N_BASIC_AUTH_PASSWORD)
- **Status:** ✅ Configurado (10/09/2026)

#### Directus
- **Email:** ceduadorodrig@gmail.com
- **Senha:** (no .env — ADMIN_PASSWORD)
- **Static Token:** `miracena-admin-token-2026` (para API/CLI)
- **Status:** ✅ Configurado (10/09/2026)
- **Schema:** 21 collections, 28 relações via SQL direto
- **Dados de teste:** 6 membros, 3 guildas, 3 cabals, 3 contatos, 2 squads, 3 projetos, 2 deals, 4 tarefas, 3 OKRs, 5 key results, 2 invoices, 1 pagamento, 3 assets, 2 peer reviews
- **Roles:** Admin (built-in), Member (full CRUD), Client (read-only), Public (assets/guildas/cabals)
- **Policies:** Miracena Member (full CRUD), Miracena Client (read-only), Miracena Public (read-only on assets)
- **Permissions:** 103 custom permissions (Member: CRUD em 23 collections, Client: read em 8 collections, Public: read em 3 collections)
- **Dashboards:** 4 dashboards (Visão Geral, OKRs & Progresso, Financeiro, Asset Bank) com 21 painéis
- **Flows:** 3 flows ativos (Novo Membro, Tarefa Criada, Proposta Criada) — limite free tier atingido

#### WordPress
- **Setup:** http://kavure.chimaera-heptatonic.ts.net:8085 (primeiro acesso cria admin)
- **Status:** ⏳ Aguardando configuração

## PostgreSQL Compartilhado

Um único PostgreSQL (`miracena-postgres`) serve **dois bancos separados**:

| Database | Usuário | Serviço |
|----------|---------|---------|
| `miracena` | `miracena` | Directus |
| `n8n` | `n8n` | n8n |

**Critério:** homelab com RAM limitada (12 GB); compartilhar instância reduz overhead. Bancos isolados, sem cross-reference. Padrão aceito para ambientes não-críticos.

## Tailscale Funnel

O container `miracena-tunnel` conecta-se à tailnet como hostname `miracena` e expõe o NPM via Funnel na porta 443.

**serve.json:**
```json
{
  "TCP": { "443": { "HTTPS": true } },
  "Web": {
    "${TS_CERT_DOMAIN}:443": {
      "Handlers": { "/": { "Proxy": "http://miracena-nginx-proxy-manager:80" } }
    }
  },
  "AllowFunnel": { "${TS_CERT_DOMAIN}:443": true }
}
```

**Limitação do Tailscale MagicDNS:** subdomínios (`site.miracena.xxx`, `cms.miracena.xxx`) não resolvem — o DNS só registra o hostname do nó (`miracena.chimaera-heptatonic.ts.net`). Serviços internos (Directus, n8n) ficam acessíveis pelas portas mapeadas em `kavure.chimaera-heptatonic.ts.net:{porta}`.

## Estrutura de Arquivos

```
/srv/data/miracena/
├── docker-compose.yml          # Stack principal
├── .env                        # Variáveis sensíveis
├── postgres/                   # Dados PostgreSQL
│   └── init/                   # Scripts de inicialização
│       └── init-multiple-dbs.sh
├── nginx-proxy-manager/        # Configurações NPM
│   ├── data/                   # Dados NPM (SQLite)
│   └── letsencrypt/            # Certificados SSL
├── tailscale/                  # Config Tailscale tunnel
│   └── serve.json              # Config de Funnel/Serve
├── nuxt/                       # Frontend Nuxt3
│   ├── app/                    # Código da aplicação
│   ├── assets/                 # CSS e assets
│   ├── package.json            # Dependências
│   ├── nuxt.config.ts          # Configuração Nuxt
│   └── docker-compose.yml      # Container Nuxt
├── wordpress/                  # Código WordPress
│   └── html/                   # Arquivos WordPress
└── backups/                    # Backups locais
```

## Rede Docker

```
miracena_default (172.x.x.x/16)
├── miracena-postgres
├── miracena-redis
├── miracena-directus
├── miracena-nuxt
├── miracena-nginx-proxy-manager
├── miracena-wordpress
├── miracena-mariadb
├── miracena-n8n
└── miracena-tunnel
```

## Comandos Úteis

```bash
# Status dos containers
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep miracena

# Logs
docker logs miracena-directus -f
docker logs miracena-wordpress -f
docker logs miracena-n8n -f
docker logs miracena-tunnel -f

# Reiniciar stack
cd /srv/data/miracena && docker compose restart

# Parar stack
cd /srv/data/miracena && docker compose down

# Atualizar imagens
cd /srv/data/miracena && docker compose pull && docker compose up -d

# Verificar Funnel
docker exec miracena-tunnel tailscale funnel status

# Verificar status Tailscale
docker exec miracena-tunnel tailscale status
```

## Portas no Kavure

| Porta | Serviço | Conflito? |
|-------|---------|-----------|
| 80 | Pi-hole | — |
| 443 | Pi-hole | — |
| 81 | NPM Admin | — |
| 3000 | aiostreams | — |
| 3003 | Nuxt3 Frontend | — |
| 8055 | Directus | — |
| 8080 | SearXNG | — |
| 8085 | WordPress | — |
| 8180 | NPM HTTP | — |
| 8443 | aiostreams | — |
| 8444 | Crafty | — |
| 8445 | NPM HTTPS | — |
| 5678 | n8n | — |

## Backups Automáticos

### Estrutura

| Componente | Método | Frequência |
|------------|--------|------------|
| PostgreSQL (Directus + n8n) | `pg_dump` → gzip | Diário 05:35 BRT |
| MariaDB (WordPress) | `mariadb-dump` → gzip | Diário 05:35 BRT |
| WordPress files | `rsync --delete` | Diário 05:35 BRT |
| Directus uploads | `rsync --delete` | Diário 05:35 BRT |
| NPM config | `rsync --delete` | Diário 05:35 BRT |

### Destino

- **NAS:** `/mnt/BACKUP/miracena-server-kavure/daily/` (psicopompo)
- **Mount point:** `/srv/data/miracena/offbox` (NFS via autofs)
- **Timer:** `hl-miracena-backup.timer` (05:35 BRT, `Persistent=true`)
- **Script:** `/usr/local/bin/miracena-backup`
- **Health file:** `/srv/health/miracena-backup-last-ok`
- **Log:** `/var/log/miracena-backup.log`
- **ntfy:** `/backup` topic em caso de falha

### Comandos

```bash
# Executar backup manualmente
sudo /usr/local/bin/miracena-backup

# Verificar timer
systemctl list-timers hl-miracena-backup.timer

# Ver logs
journalctl -u hl-miracena-backup.service -f
cat /var/log/miracena-backup.log

# Restaurar PostgreSQL
zcat /mnt/BACKUP/miracena-server-kavure/daily/postgres-miracena-YYYY-MM-DD.sql.gz | docker exec -i miracena-postgres psql -U miracena -d miracena
zcat /mnt/BACKUP/miracena-server-kavure/daily/postgres-n8n-YYYY-MM-DD.sql.gz | docker exec -i miracena-postgres psql -U n8n -d n8n

# Restaurar MariaDB
zcat /mnt/BACKUP/miracena-server-kavure/daily/mariadb-wordpress-YYYY-MM-DD.sql.gz | docker exec -i miracena-mariadb mariadb -u root -p"$MYSQL_ROOT_PASSWORD" wordpress
```

## Próximos Passos

1. **Configurar roles & policies** no Directus (Admin, Member, Client, Public)
2. **Criar dashboards (Insights)** no Directus — OKR progress, squad velocity, revenue, peer review, asset bank
3. **Configurar flows (automações)** — notifications, calendar sync, AI agent triggers
4. **Configurar WordPress** (primeiro acesso via http://kavure.chimaera-heptatonic.ts.net:8085)
5. **Habilitar SSL** via Let's Encrypt no NPM (se domínio próprio disponível)
6. **Migrar para VPS** quando dimensionar (plano Hostinger Business não suporta)

## Notas

- **n8n migrado:** de stack standalone (`/srv/data/n8n/`) para stack Miracena. Database vazio (0 workflows, 0 credentials) — sem necessidade de migração de dados.
- **PostgreSQL compartilhado:** Directus e n8n usam a mesma instância com bancos separados.
- **Tailscale Funnel:** expõe WordPress publicamente via HTTPS. Directus e n8n acessíveis internamente via portas.
- **Resource limits:** Total alocado ~6.6 GB RAM (funcional com 12 GB disponíveis).
- **Ambiente CGNAT:** sem IP público, acesso externo exclusivamente via Tailscale.
- **Directus Flatland:** 21 collections criadas (squads, guildas, cabals, peer reviews, OKRs, tasks, projects, deals, contacts, invoices, assets, etc.) com 28 relações via SQL direto (API retornava 500 por causa de tipo UUID vs integer).
- **Nuxt3 Frontend:** Container `miracena-nuxt` na porta 3003, conectado ao Directus via `NUXT_PUBLIC_DIRECTUS_URL`. Dashboard com stats, tarefas recentes e OKRs.
- **Directus Access Control:** 3 roles customizadas (Member, Client, Public) com policies e 103 permissões customizadas. Free tier limitado a 3 flows — Novo Membro, Tarefa Criada, Proposta Criada.
- **Directus Insights:** 4 dashboards com 21 painéis (metrics, lists) para visão geral, OKRs, financeiro e asset bank.

## Governança Enforced no Directus (11/09/2026)

### Infra de extensões

- `docker-compose.yml`: directus com `EXTENSIONS_AUTO_RELOAD=true` + `MARKETPLACE_TRUST=all` + volume `./directus/extensions:/directus/extensions`
- **Hook custom `miracena-workflow`**: enforcement de fluxo em todas as operações de itens do API
  - Fonte canônica: `/srv/data/miracena/directus/src/miracena-workflow/`
  - Build: dentro do container `miracena-nuxt` (Node 22), apontando para `/srv/data/miracena/directus/src/miracena-workflow` (mesma pasta montada em `/app`); `npm run build` gera `dist/`
  - **Requisito:** package.json de API extension precisa de `directus:extension: {type, path, source}` — o campo `source` é obrigatório (se faltar, erro "Current directory is not a valid Directus extension")
  - Deploy: copia `dist/` + `package.json` para `/directus/extensions/miracena-workflow/`
  - **Importante:** runtime do Directus 12 não resolve `@directus/errors` a partir do `import` do hook — é preciso vendê-la em `dist/node_modules/@directus/errors` (copiar do node_modules do build)

### Regras de workflow (hook `miracena-workflow`)

| Collection | Regra | Erro |
|---|---|---|
| `tasks` | status `done` requer `deliverable_url` | `INCOMPLETE_WORKFLOW 400` |
| `tasks` | status `in_progress` requer `assignee` | `INCOMPLETE_WORKFLOW 400` |
| `projects` | status `ativo` requer `squad` + `client` | `INCOMPLETE_WORKFLOW 400` |
| `deals` | stage `won` requer `project` | `INCOMPLETE_WORKFLOW 400` |

Bateria de testes 11/09/2026: 6/6 corretos (bloqueios e passagens).

### Consolidação para 25 collections (limite free tier)

O Directus 12 free tier limita a **25 collections custom até em self-hosted** (erro HTTP 403 `LIMIT_EXCEEDED`). Consolidação feita:

| Collection removida | Onde foi parar |
|---|---|
| `licenses` | campos `license_type`, `license_cost`, `purchase_date` em `assets` |
| `deliverables` | campos `deliverable_url`, `deliverable_note` em `tasks` |
| `milestones` | cobertos por `tasks` com prazos |
| `pdps` | campos `pdi_goals`, `pdi_actions` em `members` |
| `payments` | campos `payment_method`, `payment_date` em `invoices` |

Novas collections de governança criadas (guias no campo `note` de cada collection visível no Data Studio):

- `sprints` — ciclo quinzenal, status planejada/em_andamento/concluída; squad + objetivo
- `daily_syncs` — daily async (done_yesterday, plan_today, blockers obrigatórios)
- `retrospectives` — retro da sprint (what_went_well, what_improve, actions)
- `decisions` — registro decisório (estratégica/tática/operacional, reversível, review_date)
- `guild_sessions` — sessões de guilda ( alimenta métrica Conhecimento Compartilhado)
- `checklists` — pendências do framework viva (demais categorias em cadeia_valor/processo/infra/acesso/marketing/juridico)
- `links` — centralização de clientes, ferramentas, templates, referências

Permissões `Miracena Member` aplicadas: full CRUD sobre as 7 novas collections (28 permissões).

### Roles granulares (11/09/2026 — controle de acesso)

Nova role **Freelancer** (editores/freelas externos) criada:

| Role | Policy | O que vê | O que NÃO vê |
|---|---|---|---|
| Admin | Administrator | tudo | — |
| Member | Miracena Member | full CRUD (time interno) | — |
| **Freelancer** | Miracena Freelancer | read: tasks, projects, members, assets, guilds, sprints, links · update: tasks, daily_syncs · create: daily_syncs | **403:** invoices, profit_share, deals, contacts, proposals, peer_reviews, okrs, key_results, decisions, checklists, cabals, guild_sessions · não cria tasks |
| Client | Miracena Client | read: projetos/faturas/deals (API only) | módulos do app |

Validado com usuário de teste (13 verificações, passou tudo — usuário deletado após teste).

**Limitação free tier:** restrição de *fields por permissão* retorna `custom_permission_rules_enabled is a restricted resource` — não dá para esconder emails do diretório de members do freela via DB override (não enforce mesmo alterando a tabela). Na cultura de transparência Miracena, diretório aberto é aceitável.

**Dashboards por role:** no Directus 12 o `module_listing` (ocultar módulos por role) foi **removido** — a barrra de módulos é global (`directus_settings.module_bar`). Dashboards são visíveis para qualquer usuário com app_access (painéis de coleta sem permissão retornam erro vazio na UI). Solução definitiva planejada: **dashboards por role no front Nuxt3** (rotas por role com o SDK do Directus), que respeita as mesmas permissões da API — front apenas lê o que a permissão deixa.

### Backup do diretório de extensions

O hook em `/srv/data/miracena/directus/extensions/` **não é coberto pelo rsync do `miracena-backup`** (que copia apenas uploads, database, wordpress, NPM). A fonte canônica em `src/miracena-workflow` permite rebuild. Se instalar extensões do Marketplace, adicionar linha rsync no `/usr/local/bin/miracena-backup`.
