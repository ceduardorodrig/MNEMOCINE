---
tags: [homelab, docker, compose, config, tutorial]
---

# Política Canônica de Imagens e Versionamento de Containers (Mnemocine)

> **Padrão Estabelecido em 29/10/2026:** Define a governança de tags, ciclo de atualização e regras de pinagem de imagens Docker em todos os nós da frota (`psicopompo`, `kavure`, `ybytu`, `ybyra`, `kuaray`).

---

## 1. Filosofia de Engenharia: A Política Híbrida em 4 Camadas

Em infraestruturas profissionais de alta confiabilidade (padrões SRE, CNCF e ambientes corporativos em produção), a gestão de imagens Docker é orientada por dois princípios fundamentais:

1. **O Anti-padrão do "Tudo `:latest`" (*Rolling Drift Trap*):**
   - Imagens `:latest` em bancos de dados ou aplicações com estado introduzem quebras silenciosas no meio da noite (migrações automáticas de schema, corrupção de tabelas, quebra de plugins legados).
   - Invalida a reprodutibilidade: impede disaster recovery determinístico e auditoria de vulnerabilidades (CVEs).
2. **O Anti-padrão do "Congelamento Total e Irreal" (*Dependency Rot*):**
   - Fixar patches estritos em tudo sem exceção (ex: `glances:4.3.0.1`, `steamcmd:2024-01`) faz a infraestrutura apodrecer. Utilitários perdem patches de segurança, e containers wrappers de jogos (SteamCMD) quebram assim que a Valve altera protocolos de API da Steam.

A **Política Híbrida em 4 Camadas** equilibra segurança máxima onde há dados e conveniência/agilidade onde o serviço é efêmero ou orientado a APIs externas.

```
┌────────────────────────────────────────────────────────────────────────┐
│ CAMADA 1: Pinagem Estrita SemVer (Major.Minor)                         │
│ Bancos de Dados, CMS, Auth, Gateways de Borda (NUNCA auto-update)       │
├────────────────────────────────────────────────────────────────────────┤
│ CAMADA 2: Game Servers & Wrappers de Jogo                              │
│ Wrapper estável / latest + Engine atualizada via SteamCMD no boot      │
├────────────────────────────────────────────────────────────────────────┤
│ CAMADA 3: SemVer Flutuante por Major (:1, :v2, :YYYY.MM)               │
│ Dashboards, automações e indexadores (recebe patches, bloqueia breaks) │
├────────────────────────────────────────────────────────────────────────┤
│ CAMADA 4: Utilitários Stateless de Infraestrutura                      │
│ Telemetria e manutenção contínua (:latest monitorado por Watchtower)   │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. As Quatro Camadas do Homelab

### Camada 1: Pinagem Estrita (SemVer Patch/Minor) — Crítico & Stateful
- **Critério:** Serviços que persistem schemas relacionais, dados de clientes, certificados TLS de borda ou arquivos de configuração sensíveis.
- **Regra de Versionamento:** Sempre fixar `major.minor` ou `major.minor.patch` (ex: `mariadb:11`, `postgres:16-alpine`, `wordpress:6.6.2-php8.3-apache`).
- **Comportamento do Watchtower:** **DESATIVADO OBRIGATORIAMENTE** via label `com.centurylinklabs.watchtower.enable: "false"`.
- **Procedimento de Atualização:** Exclusivamente manual, precedido por backup completo (`config-backup`, dump SQL) e leitura do changelog oficial.

### Camada 2: Servidores de Jogos (SteamCMD / Runtimes)
- **Critério:** Servidores de jogos dedicados onde o container Docker atua apenas como ambiente Linux/GLIBC/Wine e orquestrador de download da Steam.
- **Regra de Versionamento:**
  - **Project Zomboid:** O container (`zomboid-panel:latest` / `danixu86/project-zomboid-dedicated-server:latest`) DEVE permanecer `:latest` para manter compatibilidade com bibliotecas da Valve. O executável do servidor de jogo é atualizado via SteamCMD no startup (`app_update 380870 validate`).
  - **Valheim:** Wrapper fixado na major (`mbround18/valheim:3`) para estabilidade de scripts BepInEx, com atualização diária do jogo às 03:00 via SteamCMD interno.
  - **Minecraft (Dominium / Crafty 4):** Painel Crafty opera em `:latest` ou tag estável `:4`. A versão do servidor de jogo (Java Fabric 1.21.1) é 100% estática e controlada pelo ecossistema de mods e `.jar` em `/srv/data/minecraft/`.

### Camada 3: SemVer Flutuante por Major (`:1`, `:v2`, `:YYYY.MM`)
- **Critério:** Aplicações auxiliares, dashboards, indexadores de mídia e automações.
- **Regra de Versionamento:** Usar a tag de Major Version mais recente (ex: `uptime-kuma:1`, `adguardhome:v0.107`, `binwiederhier/ntfy:v2`, `grafana/grafana:11`).
- **Benefício:** O container recebe correções de bugs e patches de segurança automaticamente, mas fica blindado contra grandes reformulações de arquitetura que quebram retrocompatibilidade.
- **Exceções em `:latest` desta camada:**
  - **SearXNG (`searxng/searxng:latest`):** É um projeto rolling-release que depende de adaptações constantes a scrapers de mecanismos de busca. Roda isolado com Valkey próprio.
  - **Addons e Scrapers de Mídia (`aiostreams:latest`, `flaresolverr:latest`, `comet:latest`):** Devem rodar a versão mais recente para acompanhar mudanças de APIs de provedores externos.

### Camada 4: Utilitários Stateless de Infraestrutura
- **Critério:** Daemons de monitoramento, proxies de socket e ferramentas de limpeza que não guardam estado em disco.
- **Regra de Versionamento:** `:latest` com atualização contínua via Watchtower.
- **Serviços:** `containrrr/watchtower`, `willfarrell/autoheal`, `nicolargo/glances`, `tecnativa/docker-socket-proxy`.

---

## 3. Mapeamento Completo da Frota (5 Nós)

### 3.1. Nó `psicopompo` (Workstation / AI / Registro)

| Serviço / Container | Imagem Atual | Camada | Política Recomendada | Watchtower |
|---|---|---|---|---|
| `registry` | `registry:3` | Camada 1 | `registry:3` (Pinado) | Bloqueado |
| `steniorec` | `sumaenima-server:cuda` | Interna | Build local / CI | Manual |
| `glances` | `nicolargo/glances:ubuntu-latest-full` | Camada 4 | `:ubuntu-latest-full` | Habilitado |
| `watchtower` | `containrrr/watchtower:latest` | Camada 4 | `:latest` | Auto-gerenciado |
| `autoheal` | `willfarrell/autoheal:latest` | Camada 4 | `:latest` | Habilitado |
| `dockerproxy` | `tecnativa/docker-socket-proxy:latest` | Camada 4 | `:latest` | Habilitado |
| `node-exporter` | `prom/node-exporter:v1.9.0` | Camada 4 | `prom/node-exporter:v1` | Habilitado |
| `promtail` | `grafana/promtail:3.2.0` | Camada 4 | `grafana/promtail:3` | Habilitado |

### 3.2. Nó `kavure` (Dedicated Server / Swarm Manager)

| Serviço / Container | Imagem Atual | Camada | Política Recomendada | Watchtower |
|---|---|---|---|---|
| `sae-core_db` | `pgvector/pgvector:pg16` | Camada 1 | `pgvector/pgvector:pg16` | Bloqueado |
| `sae-core_umami-db` | `postgres:15-alpine` | Camada 1 | `postgres:15-alpine` | Bloqueado |
| `sae-core_valkey` | `valkey/valkey:8-alpine` | Camada 1 | `valkey/valkey:8-alpine` | Bloqueado |
| `n8n-postgres` | `postgres:16-alpine` | Camada 1 | `postgres:16-alpine` | Bloqueado |
| `searxng-valkey` | `valkey/valkey:9-alpine` | Camada 1 | `valkey/valkey:9-alpine` | Bloqueado |
| `n8n` | `docker.n8n.io/n8nio/n8n:stable` | Camada 3 | `:stable` ou `:1` | Bloqueado (manual) |
| `homeassistant` | `homeassistant/home-assistant:latest` | Camada 3 | `:2024.10` (SemVer mensal) | Bloqueado |
| `pihole` | `pihole/pihole:latest` | Camada 3 | `pihole/pihole:2024` ou `:latest` | Habilitado |
| `calibre` | `crocodilestick/calibre-web-automated:latest`| Camada 3 | `:latest` | Habilitado |
| `navidrome` | `deluan/navidrome:latest` | Camada 3 | `:latest` (ou `:0.53`) | Habilitado |
| `searxng-core` | `searxng/searxng:latest` | Camada 3 | `:latest` | Habilitado |
| `aiostreams` | `viren070/aiostreams:latest` | Camada 3 | `:latest` | Habilitado |
| `comet` | `ghcr.io/g0ldyy/comet:latest` | Camada 3 | `:latest` | Habilitado |
| `valheim-server` | `mbround18/valheim:3` | Camada 2 | `mbround18/valheim:3` (SteamCMD) | Bloqueado |
| `zomboid-panel` | `ghcr.io/fpsacha/zomboid-panel:latest` | Camada 2 | `:latest` (SteamCMD) | Bloqueado |
| `crafty-controller` | `registry.gitlab.com/.../crafty-4:latest`| Camada 2 | `:latest` (Engine Java estática)| Bloqueado |
| `monitoring-prometheus` | `prom/prometheus:v2.55.1` | Camada 1 | `prom/prometheus:v2` | Bloqueado |
| `monitoring-grafana` | `grafana/grafana:11.3.0` | Camada 1 | `grafana/grafana:11` | Bloqueado |
| `monitoring-loki` | `grafana/loki:3.2.0` | Camada 1 | `grafana/loki:3` | Bloqueado |
| `monitoring-alertmanager` | `prom/alertmanager:v0.27.0` | Camada 1 | `prom/alertmanager:v0.27` | Bloqueado |

### 3.3. Nó `kuaray` (Standby / Miracena / Media Stack)

| Serviço / Container | Imagem Atual | Camada | Política Recomendada | Watchtower |
|---|---|---|---|---|
| `miracena-wordpress` | `wordpress:6.6.2-php8.3-apache` | Camada 1 | `wordpress:6.6.2-php8.3-apache` | Bloqueado |
| `miracena-mariadb` | `mariadb:11` | Camada 1 | `mariadb:11` | Bloqueado |
| `miracena-postgres` | `postgres:16-alpine` | Camada 1 | `postgres:16-alpine` | Bloqueado |
| `miracena-redis` | `redis:7-alpine` | Camada 1 | `redis:7-alpine` | Bloqueado |
| `miracena-directus` | `directus/directus:latest` | Camada 1 | `directus/directus:11` | Bloqueado |
| `miracena-nginx-proxy-manager` | `jc21/nginx-proxy-manager:latest` | Camada 1 | `jc21/nginx-proxy-manager:2.11` | Bloqueado |
| `miracena-tunnel` | `tailscale/tailscale:latest` | Camada 4 | `:latest` | Habilitado |
| `prowlarr` | `lscr.io/linuxserver/prowlarr:latest` | Camada 3 | `:latest` | Habilitado |
| `transmission` | `lscr.io/linuxserver/transmission:latest` | Camada 3 | `:latest` | Habilitado |
| `lidarr` | `lscr.io/linuxserver/lidarr:latest` | Camada 3 | `:latest` | Habilitado |
| `slskd` | `slskd/slskd:latest` | Camada 3 | `:latest` | Habilitado |
| `soularr` | `mrusse08/soularr:latest` | Camada 3 | `:latest` | Habilitado |
| `flaresolverr` | `ghcr.io/flaresolverr/flaresolverr:latest` | Camada 3 | `:latest` | Habilitado |
| `syncthing` | `linuxserver/syncthing:1.29.7` | Camada 1 | `linuxserver/syncthing:1` | Bloqueado |

### 3.4. Nó `ybytu` (Cloud Edge / DNS)

| Serviço / Container | Imagem Atual | Camada | Política Recomendada | Watchtower |
|---|---|---|---|---|
| `adguardhome` | `adguard/adguardhome:latest` | Camada 3 | `adguard/adguardhome:v0.107` | Bloqueado (DNS core) |
| `uptime-kuma` | `louislam/uptime-kuma:latest` | Camada 3 | `louislam/uptime-kuma:1` | Habilitado |
| `ntfy` | `binwiederhier/ntfy:latest` | Camada 3 | `binwiederhier/ntfy:v2` | Habilitado |
| `homepage` | `ghcr.io/gethomepage/homepage:latest` | Camada 3 | `ghcr.io/gethomepage/homepage:v0` | Habilitado |
| `changedetection` | `dgtlmoon/changedetection.io:latest` | Camada 3 | `:latest` | Habilitado |

### 3.5. Nó `ybyra` (Cloud Edge / Ingress)

| Serviço / Container | Imagem Atual | Camada | Política Recomendada | Watchtower |
|---|---|---|---|---|
| `sae-edge_proxy` | `.../nginx-sumaenima:latest` | Camada 1 | Build do Repo SUMAENIMA-HUB | CI Deploy |
| `sae-edge_umami` | `.../sumaenima-umami:latest` | Camada 1 | Build do Repo SUMAENIMA-HUB | CI Deploy |
| `sae-edge_tunnel`| `tailscale/tailscale:latest` | Camada 4 | `:latest` | Habilitado |

---

## 4. Runbook de Operação: Como Atualizar com Segurança

### 4.1. Atualizando Serviços de Camada 1 (Bancos de Dados, CMS, Auth)
1. **Auditoria de Mudança:** Ler as release notes oficiais da versão alvo (verificar se há breaking changes ou migrações irreversíveis).
2. **Snapshot / Backup Preventivo:**
   ```bash
   config-backup
   # Para bancos de dados (ex: MariaDB na Miracena):
   sudo miracena-backup
   ```
3. **Edição do Compose:** Alterar a tag semântica no compose file (ex: `wordpress:6.6.2-php8.3-apache` → `wordpress:6.6.3-php8.3-apache`).
4. **Deploy Controlado:**
   ```bash
   docker compose pull <servico>
   docker compose up -d <servico>
   ```
5. **Verificação de Saúde:** Acompanhar os logs (`docker compose logs -f <servico>`) e verificar o status com `docker ps`.

### 4.2. Atualizando Servidores de Jogos (Camada 2)
- **Project Zomboid:**
  ```bash
  zomboid-restart # Executa RCON save prévio e reinicia; o SteamCMD atualiza a build 42
  ```
- **Valheim:**
  - O script interno do container checa updates via SteamCMD todo dia às 03:00.
  - Para forçar atualização manual imediata: reiniciar o container (`docker restart valheim-server`).
- **Minecraft:**
  - Atualizações de mods/loaders seguem o runbook de paridade Prism Launcher / Server via `sync_mods.py` (ver `mnemocine/services/crafty.md`).

### 4.3. Como Bloquear o Watchtower em Serviços Críticos
Para garantir que o Watchtower ignore containers de estado, declare a label explicitamente no `docker-compose.yml`:

```yaml
services:
  meu-banco-ou-cms:
    image: postgres:16-alpine
    labels:
      - "com.centurylinklabs.watchtower.enable=false"
```

---

## 5. Integração com o StênioSentinel

O motor de governança em Rust (`governance/stenio/src/infra.rs`) valida proativamente as regras de imagem através do código **`SEC-COMPOSE-PINNED-IMAGE`**:

- Emite **CRITICAL WARNING** se motores de banco ou CMS (`wordpress`, `mariadb`, `postgres`, `directus`) utilizarem `:latest` ou tags flutuantes sem SemVer.
- Aceita `:latest` em utilitários de telemetria e wrappers de servidores de jogos reconhecidos na taxonomia do homelab.
