---
tags: [homelab, service, searxng, search]
---

# SearXNG

Mecanismo de busca **privado** (meta-search) — sem rastreamento/profiling. Também expõe **API JSON** para o n8n usar em workflows.

**Servidor:** kavure
**Porta:** `8080`
**URL:** `http://kavure.chimaera-heptatonic.ts.net:8080`
**JSON:** `http://kavure.chimaera-heptatonic.ts.net:8080/search?q=<termo>&format=json`

> **Deploy (28/08/2026):** config-as-code em `/srv/data/searxng/` (compose oficial + `.env` via store sops, prefixo `SEARXNG_*`).

## Stack

| Container | Imagem | Função |
|---|---|---|
| searxng-core | `docker.io/searxng/searxng:latest` | Meta-search |
| searxng-valkey | `docker.io/valkey/valkey:9-alpine` | Cache/limiter |

## Configuração

- `/srv/data/searxng/core-config/settings.yml`: `use_default_settings: true` + **`search.formats: [html, json]`** (JSON habilita a API p/ o n8n) + `server.public_instance: false`.
- `.env`: `SEARXNG_SECRET` (store sops — obrigatório p/ o rate limiter/cookies), `SEARXNG_HOST=0.0.0.0`, `SEARXNG_PORT=8080`.

## Uso

- **Navegador:** apontar a busca para `http://kavure.chimaera-heptatonic.ts.net:8080/search?q=%s` (busca privada no dia a dia).
- **n8n:** usar HTTP Request em `…/search?q=<query>&format=json` (engine "SearXNG") em workflows de pesquisa/resumo.
- **Limitações:** engines podem rate-limit; limiter/valkey em uso. Acesso via tailnet (sem expor público por padrão).

## Manutenção

- **Update:** watchtower do kavure gerencia.
- **Config:** editar `settings.yml` e `docker compose restart searxng-core` (ou `up -d`).
- **Espelho:** `config-backup` espelha `/srv/data/searxng` (`.env` excluído; segredo no store).

## See also
- [[n8n]] — consume a API JSON do SearXNG
- [[monitoring]] — Prometheus do kavure (mesmo host)