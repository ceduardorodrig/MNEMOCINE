---
tags: [homelab, service, steniobot, monitoring, docker, server, psicopompo, ybyra]
---

# Relatório: Auditoria de Topologia e Monitoria (Sumænimá INFRA)

> Status: **CONCLUÍDO** — 2026-06-28
>
> ⚠️ **Pós-migração (07/08/2026):** o core (`sae-core`) migrou do psicopompo para o **kavure** (100.124.146.77). O monitor #50 no Uptime-Kuma passou a apontar para `http://100.124.146.77:9090/api/health` (Kavure - Sumænimá API). O monitor #49 (backup health) aponta para `http://100.124.146.77:9092/health`. Ver `services/steniobot.md` e `network/topology.md`.
>
> ✅ **29/08/2026 — widget "Sumænimá Backup" corrigido:** o health server do backup (`backup_health_server.py`, BaseHTTPRequestHandler) não implementava `do_HEAD` — probes **HEAD** do Homepage/Uptime Kuma recebiam **501**, exibido como erro no dashboard. Adicionado `do_HEAD` (GET e HEAD → 200). Endpoint monitorado: `http://100.124.146.77:9092/health` (kavure).

---

## 1. Problema Resolvido: Nomenclatura Precária (Ybyra vs Psicopompo)

O monitor `Ybyra - Sumænimá API` foi renomeado para `Ybyra - Proxy API (Externo)` porque o container da API (`sae-core_api`) e o banco (`sae-core_db`) rodam fisicamente no Psicopompo, não no Ybyra.

### O que foi feito:

1. **Monitor #4 renomeado**: `Ybyra - Sumænimá API` → `Ybyra - Proxy API (Externo)` — monitora a entrega da API via proxy Nginx no Ybyra (`http://100.66.224.34/api/health`)
2. **Monitor #50 criado**: `Kavure - Sumænimá API (Interno)` — monitora a saúde física da API no kavure via Tailscale (`http://100.124.146.77:9090/api/health`)
3. **Porta 9090 publicada** no `sae-core_api` via `provisioning/stacks/core.yml` + `docker stack deploy` (estava apenas na overlay network)
4. **Notificação ntfy** associada ao novo monitor #50

---

## 2. Achados da Auditoria nos 4 Nós

### A. Psicopompo (Manager / Core)
| Item | Documentado | Real |
|------|-------------|------|
| Container da API | `steniobot_app` (standalone) | `sae-core_api` (Swarm service) |
| Porta 9090 | Publicada | **Estava apenas overlay, foi publicada** ✅ |
| Portainer | Rodando | **Exited** (removido) |
| RustDesk (hbbs/hbbr) | Rodando | **Não existe mais** |
| backup-sentinel | **Não documentado** | Novo serviço Swarm (porta 9092) |
| steniobot_vision/audio | **Não documentados** | 2 containers avulsos na overlay |

### B. Ybyra (Edge / VPS)
- **Swarm role:** `primary` — nó worker do Swarm
- Nginx roteia `/api/ → 100.124.146.77:9090` (kavure via Tailscale)
- API health via proxy: `HTTP 200` ✅
- Datavis, Umami, Tailscale roda como Swarm services

### C. Ybytu (Home Utility)
- Uptime Kuma: 41 monitores (não 37 como documentado)
- Ntfy notificação associada a TODOS os monitores ✅
- Sem divergências críticas

### D. Kuaray (Standby / DR)
- 21 containers rodando conforme documentado
- Nó Swarm com label `standby` (role não utilizada ativamente)

---

## 3. Documentação Atualizada

| Arquivo | O que foi alterado |
|---------|-------------------|
| `servers/psicopompo.md` | Swarm services, backup-sentinel, vision/audio adicionados; Portainer/RustDesk removidos |
| `servers/ybyra.md` | Adicionado Swarm role `primary` |
| `services/steniobot.md` | Stack Swarm, visão/audio, recovery via stack deploy |
| `services/uptime-kuma.md` | 41 monitores, monitores #4 e #50 documentados, divisão borda/física |
| `services/health-endpoints.md` | Este relatório |

## 4. Comandos Executados

```bash
# 1. Publicar porta 9090
docker stack deploy -c provisioning/stacks/core.yml sae-core

# 2. Renomear monitor #4 no Uptime Kuma
sqlite3 kuma.db "UPDATE monitor SET name='Ybyra - Proxy API (Externo)' WHERE id=4;"

# 3. Criar monitor #50
sqlite3 kuma.db "INSERT INTO monitor (...) VALUES ('Psicopompo - Sumænimá API (Interno)', ...);"

# 4. Associar notificação
sqlite3 kuma.db "INSERT INTO monitor_notification (monitor_id, notification_id) VALUES (50, 1);"
```

## 5. Validação

- API health local: `HTTP 200` ✅
- API health via Tailscale (100.124.146.77:9090): `HTTP 200` ✅
- API health via Ybyra proxy: `HTTP 200` ✅
