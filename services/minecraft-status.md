---
tags: [homelab, service, crafty, gaming]
---

# minecraft-status

**Endpoint HTTP nativo** que reporta se o servidor Minecraft responde ao Server List Ping
(SLP). É o que dá ao chip do **Homepage** (e a monitores HTTP) o estado *real do jogo* —
não o do container.

**Servidor:** kavure
**Porta:** `9095` (HTTP, `0.0.0.0`)
**Serviço:** `minecraft-status.service` (systemd, nativo) · binário `/usr/local/bin/minecraft-status`
**Fonte:** `SUMAENIMA-HUB/provisioning/minecraft-status/` (Rust, sem dependências)

## Contrato

| Método | Servidor no ar | Servidor parado |
|---|---|---|
| `GET /` | **200** `up` | **503** `down` |
| `HEAD /` | **200**, cabeçalhos idênticos ao GET, **sem corpo** | **503**, idem |

- O SLP (handshake com protocol `-1` + status request) confirma `version`/`players`/`description`
  no JSON de resposta — **porta aberta que não é Minecraft não passa** como "up".
- Corpo em texto puro com `Content-Length`; `Connection: close` (sem keep-alive).

## Por que existe

O container `crafty-controller` fica **sempre up** (é o gerenciador) — um badge Docker
enganaria. O widget `minecraft` do Homepage renderiza painel de 3 campos, fora do padrão.
Solução: mini endpoint HTTP + `siteMonitor` → chip pequeno com o status real do jogo.

## Bug e correção (08/10/2026 — HEAD respondia com corpo)

**Sintoma:** o Homepage logava `<httpProxy> Error calling http://kavure:9095/` a cada ~30 s,
independentemente de o jogo estar ligado ou não.

**Causa (reproduzida):** o Homepage consulta `siteMonitor` com **HEAD**; o porte Python→Rust
(29/09) tratava `HEAD` como `GET` e respondia **com corpo** — violação da RFC 7231 §4.3.2. O
parser do Node abortava com `Parse Error: Data after \`Connection: close\`` → 500 no proxy. O
`GET` sempre funcionou (200/503) — por isso o sintoma **não** batia com o estado do jogo.

**Correção:** `main.rs` separa `GET` de `HEAD`; resposta de HEAD = **só cabeçalhos**
(`headers_only`), mantendo `Content-Length`. **9 testes** (2 novos para HEAD 200/503) verdes.
Binário anterior preservado: `/usr/local/bin/minecraft-status.bak-20261008-head`.

**Provas:**
- raw: HEAD agora termina em `\r\n\r\n` (sem `up`/`down`); antes mandava o corpo.
- Node (dentro do container do Homepage): `HEAD ×3` → `200`, corpo vazio, **0 erros** (antes:
  `Parse Error` em todas).
- log do Homepage: **0 `<httpProxy>`** em 100 s (≈3 ciclos de siteMonitor).

## Operação

```bash
systemctl status minecraft-status
curl -s -w " [%{http_code}]" http://127.0.0.1:9095/    # up|down + 200|503
journalctl -u minecraft-status -n 30 --no-pager
```

Rebuild/deploy: `cargo build --release` em `SUMAENIMA-HUB/provisioning/minecraft-status/` →
`install -m 755 target/release/minecraft-status /usr/local/bin/` (kavure) → restart da unit.

## Referências

- Servidor/painel: [`crafty.md`](crafty.md) · Dashboard: [`homepage.md`](homepage.md)
- Unit no HUB: `provisioning/systemd/minecraft-status.service`
