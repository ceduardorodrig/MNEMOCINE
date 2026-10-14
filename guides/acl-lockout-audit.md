---
tags: [homelab, network, tailscale, tutorial]
---

# ACL Lockout Audit — what the Phase-3 tighten locked out

> **One question, per consumer:** after the tailnet went **deny-by-default** (HB-049 phase 3,
> 2026-10-13 — the blanket `{"src":["*"],"dst":["*"],"ip":["*"]}` grant was **deleted**), does every
> service a consumer actually uses still resolve? This document is the **map** of what the tighten
> cut, what was restored, and what is **deliberately** still denied.

**Status:** gaps fixed in `MNEMOCINE-ACL` PR [#12](https://github.com/ceduardorodrig/MNEMOCINE-ACL/pull/12)
(merged, CI green, `action: apply` success); the member game ports were fixed earlier in PR
[#11](https://github.com/ceduardorodrig/MNEMOCINE-ACL/pull/11). The **CI guard** that now pins the
expected-reach set (and the last gap it caught, WordPress `:8085`) is PR
[#13](https://github.com/ceduardorodrig/MNEMOCINE-ACL/pull/13) — see
[§5b](#5b-the-ci-guard-what-the-tests-now-pin). The **owner decisions** that remain are listed in
[§6](#6-owner-decisions-not-implemented).

## 1. The ruler is the *delta*, not the current state

Before phase 3 a single `allow-all` grant made the whole tailnet reachable. After it, a path works
**only if an explicit grant covers it**. So a *gap* is not "a port is closed" — it is a path that
**(a)** a consumer **expects** to reach (proven by the Homepage tiles, the Uptime Kuma monitors,
`services-catalog.md`'s *who depends on it*, `ports.md`, and the per-service docs) **and (b)** is
**not** covered by any grant. The audit is **per consumer**, because grants are keyed by `src`.

## 2. Method — how the next agent repeats this

The policy is **not in this vault**: it is `MNEMOCINE-ACL/policy.hujson` (`main`), deployed by GitOps
(`tailscale/gitops-acl-action`, `action: test` on PRs, `action: apply` on `main`; console lockout is
ON, so `main` **is** the live policy).

| Layer | Command | What it answers |
|---|---|---|
| **The policy (source)** | `gh api` / `curl -H "Authorization: Bearer $(sops-decrypt.sh TS_API_TOKEN)" https://api.tailscale.com/api/v2/tailnet/-/acl` | The raw grants, tags, tests (reformatted by the control plane — compare by content, not whitespace). |
| **The effective filter (oracle)** | `tailscale debug netmap \| jq '.PacketFilter'` **on each host** | The rules the control plane actually distributed. ⚠️ **It is per-node and INBOUND**: a host's `PacketFilter` only contains rules whose `dst` resolves to **that host**. To audit "can X reach service Y", read **Y's** netmap. |
| **Who uses what** | `services-catalog.md` (the *who depends on it* column) · `ybytu:/home/ubuntu/homelab/homepage/config/services.yaml` (**the tiles = what the owner/family expect to click**) · `ports.md` §4 · the per-service docs | The **intent** layer — the expected-reach set. |
| **The reality** | `ss -tlnp` / `ss -ulnp` per host · Uptime Kuma's monitors (`sqlite3 …/kuma.db "select name,type,url from monitor;"`) | What is actually listening / actually probed. |

**Procedure:** (1) expand each grant's `src`/`dst` from the netmap; (2) for each consumer class, diff
its *expected-reach* set against the ports its rules carry; (3) every expected-but-absent port is a
candidate gap; (4) confirm with a live probe; (5) a gap is **unambiguous** only when the use is
proven (a tile/monitor/doc) **and** it is not an intentionally-excluded infra port.

## 3. Consumer classes (live, 2026-10-13)

| Class | Identity in the policy | Members |
|---|---|---|
| **Members** | `autogroup:member` (untagged user devices) | 8 devices: `kururu`, `Anansi`, `morfosear`, `DESKTOP-3J1Q05G`, `A55 de Anna`, `Tab S10 FE de Izabele`, `A73 de Izabele`, `Pira-Nuya` |
| **Shared users** | `autogroup:shared` | 6 devices (the game players) |
| **Servers** | `tag:server` | `psicopompo`, `ybytu`, `ybyra`, `kuaray`, `kavure` |
| **Edge** | `tag:edge` | `ybyra`, `kavure`, `sumaenima` (100.75.200.18), `miracena` (100.82.64.78) |
| **Monitoring** | `tag:monitoring` | `kavure` (Prometheus/Grafana/Loki) |
| **Subnet-router users** | `192.168.3.0/24` via `kavure` | members only |
| **Exit-node users** | `autogroup:internet` via `ybytu`/`kavure` | members only |

## 4. The matrix (consumer × service × verdict × evidence)

### 4.1 Members (`autogroup:member` → `tag:server`, grants 1/1c)

| Service (tile / monitor) | Port | Verdict | Evidence |
|---|---|---|---|
| Homepage itself (ybytu) | `tcp:3001` | ✅ reaches | grant (1) |
| Syncthing web (psicopompo, kuaray) | `tcp:8384` | ✅ | grant (1) |
| **Punktfunk console** (psicopompo) | `tcp:47992` | ❌→✅ **fixed** | tile + Uptime Kuma monitor; port was absent |
| **Punktfunk streaming** (psicopompo) | `udp:9777` | ❌→✅ **fixed** | `services/punktfunk.md` ("via LAN or Tailscale") |
| hl-infer (psicopompo) | `tcp:9095` | ✅ | grant (1) |
| ComfyUI (psicopompo) | `tcp:8188` | ✅ | grant (1) |
| Glances (all hosts) | `tcp:61208` | ✅ | grant (1) |
| **Portal Sumænimá / API / Umami** (Funnel) | `tcp:443` → `tag:edge` | ❌→✅ **fixed** | MagicDNS resolves the name to the node's **tailnet** IP (`getent hosts sumaenima.chimaera-heptatonic.ts.net` → `100.75.200.18`); tile href |
| **Portal Miracena** (Funnel) | `tcp:443` → `tag:edge` | ❌→✅ **fixed** | same |
| Sumænimá Backup (kavure) | `tcp:9092` | ❌ stays (by design) | Swarm **ingress** — infra, runbook §3; Homepage checks it **server-side** (grant 5), so the tile *status* still works |
| StênioREC (psicopompo) | `tcp:9090` | ✅ | grant (1) |
| Docker Registry (psicopompo) | `tcp:5000` | ❌ stays (by design) | deny pin; infra |
| Zomboid Control Panel (kavure) | `tcp:3001` | ✅ | grant (1) |
| Crafty Controller (kavure) | `tcp:8444` | ✅ | grant (1) |
| Minecraft (kavure) | `tcp:25565` | ✅ | grant (1) |
| Valheim (kavure) | `udp:2456-2458` | ❌→✅ **fixed (PR #11)** | member games — the owner's own find |
| Zomboid game (kavure) | `udp:16261-16262` | ✅ | grant (1) after PR #11 |
| Minecraft voice (kavure) | `udp:24454` | ✅ | grant (1) after PR #11 |
| AioStreams (kavure) | `tcp:3000` | ✅ | grant (1) |
| Comet (kavure) | `tcp:8000` | ✅ | grant (1) |
| n8n (kavure, kuaray) | `tcp:5678` | ✅ | grant (1) |
| Grafana (kavure) | `tcp:3002` | ✅ | grant (1) |
| Prometheus (kavure) | `tcp:9091` | ✅ | grant (1) |
| **Loki** (kavure) | `tcp:3100` | ❌→✅ **fixed** | tile href |
| Alertmanager (kavure) | `tcp:9093` | ✅ | grant (1) |
| SearXNG (kavure) | `tcp:8080` | ✅ | grant (1) |
| Pi-hole admin (kavure) | `tcp:80`, `tcp:443` | ✅ | grant (1) |
| Unbound status (kavure) | `tcp:9097` | ✅ | grant (1) |
| Home Assistant (kavure) | `tcp:8123` | ✅ | grant (1) |
| Navidrome (kavure) | `tcp:4533` | ✅ | grant (1) |
| Calibre Web (kavure) | `tcp:8083` | ✅ | grant (1) |
| WordPress (kuaray) | `tcp:8085` | ❌→✅ **fixed (PR #13)** | Homepage tile (`href http://kuaray:8085`); this row wrongly claimed grant (1) — the CI guard found `:8085` was never granted |
| **Directus** (kuaray) | `tcp:8055` | ❌→✅ **fixed** | tile + Uptime Kuma |
| Nuxt 3 (kuaray) | `tcp:3003` | ✅ | grant (1) |
| **NPM admin** (kuaray) | `tcp:81` | ❌→✅ **fixed** | tile + Uptime Kuma |
| Transmission (kuaray) | `tcp:9091` | ✅ | grant (1) |
| Prowlarr (kuaray) | `tcp:9696` | ✅ | grant (1) |
| Lidarr (kuaray) | `tcp:8686` | ✅ | grant (1) |
| **slskd** (kuaray) | `tcp:5030` | ❌→✅ **fixed** | tile + Uptime Kuma |
| **Flaresolverr** (kuaray) | `tcp:8191` | ❌→✅ **fixed** | tile + Uptime Kuma |
| **Soularr** (kuaray) | `tcp:8265` | ❌→✅ **fixed** | tile + Uptime Kuma |
| **Vert** (kuaray) | `tcp:3030` | ❌→✅ **fixed** | tile + Uptime Kuma |
| AdGuard admin (ybytu) | `tcp:3000` | ✅ | grant (1) |
| Uptime Kuma (ybytu) | `tcp:3002` | ✅ | grant (1) |
| Changedetection (ybytu) | `tcp:8082` | ✅ | grant (1) |
| Ntfy (ybytu) | `tcp:8083` | ✅ | grant (1) |
| Glances (ybyra) | `tcp:61208` | ✅ | grant (1) |
| WoL tiles (ybytu dispatcher) | `tcp:9096` | ✅ | grant (1) |
| DNS (kavure, ybytu) | `udp:53`, `tcp:53` | ✅ | grant (8) |
| Syncthing transport | `tcp/udp:22000` | ✅ | grant (9) |
| Exit node | `autogroup:internet` | ✅ | grant (2) |
| LAN via subnet router | `192.168.3.0/24` | ✅ | grant (3) |
| A member's own devices | `autogroup:self` | ✅ | grant (7) |
| SSH to servers | `tcp:22` | ✅ (admin) | `ssh` section + grant (6) |
| KDE Connect | `tcp/udp:1716` | ✅ | grant (12) |
| **Another member's devices** (the *grande LAN*) | `autogroup:member` | ✅ **added 2026-10-13 (D11 / HB-063, PR [#14](https://github.com/ceduardorodrig/MNEMOCINE-ACL/pull/14))** | grant (7b); a **tagged** node is not a member, so the servers stay out of it — verified live (§10) |

### 4.2 Shared users (`autogroup:shared` → `tag:server`, grant 1b)

| Service | Port | Verdict | Evidence |
|---|---|---|---|
| Minecraft (kavure) | `tcp:25565` | ✅ | grant (1b) |
| Minecraft voice (kavure) | `udp:24454` | ✅ | grant (1b) |
| Valheim (kavure) | `udp:2456-2458` | ✅ | grant (1b) — **never cut** (unlike members) |
| Zomboid (kavure) | `udp:16261-16262` | ✅ | grant (1b) |
| Anything else / exit node | — | ❌ by design | no grant; exit node is members-only |

### 4.3 Servers (`tag:server` ↔ `tag:server`, grant 5, `ip:["*"]`)

**No gap.** Every host-to-host dependency rides this grant: NFS `2049` (psicopompo→kuaray/kavure),
Swarm raft `2377` / gossip `7946` / VXLAN `4789`, Loki `3100`, the registry `5000`, `hl-infer` `9095`,
`steniorec` `9090`, Syncthing `22000`, AdGuard→unbound `5053`, Homepage→dockerproxy `2375`,
Alertmanager→ntfy `8083`, SSH `22`.

### 4.4 Monitoring (`tag:monitoring` = kavure)

**No gap.** `prometheus.yml` scrapes node-exporter `9100` (all five hosts), `hl-infer` `9095`
(psicopompo) and n8n `/metrics` `5678` (kuaray, kavure) — all covered by grant (4). The reverse
direction (every host's promtail → Loki `3100`) is grant (4b). The in-host targets
(`cadvisor:8080`, `loki:3100`, `grafana:3000`, `alertmanager:9093`) never touch the tailnet.

### 4.5 Edge (`tag:edge`)

| Direction | Verdict | Evidence |
|---|---|---|
| members → edge `:443` (the Funnels) | ❌→✅ **fixed** | grant (1c) |
| `tag:server` → edge `:443` (Homepage portal check) | ✅ | grant (11) |
| edge → anywhere over the tailnet | n/a | the `sae-edge_tunnel` / `miracena-tunnel` proxy to their target **locally or over the Swarm overlay**, not the tailnet |

### 4.6 Subnet router & exit nodes

| Path | Verdict | Evidence |
|---|---|---|
| members → `192.168.3.0/24` | ✅ | grant (3) |
| a **server** → `192.168.3.0/24` | not needed | Uptime Kuma's monitors and the Homepage siteMonitors target **tailnet IPs / public names** only (checked `kuma.db` + `services.yaml`); the LAN-only hosts are physically on the LAN |
| members → exit node | ✅ | grant (2) |
| shared → exit node | ❌ by design | grant (2) is `autogroup:member` only |

## 5. The gaps (what was locked out) and the exact grant

Fixed in PR [#12](https://github.com/ceduardorodrig/MNEMOCINE-ACL/pull/12) — appended to grant (1)
(`autogroup:member` → `tag:server`) plus a new grant (1c):

```jsonc
// grant (1) additions
"tcp:47992",  // Punktfunk web console (psicopompo)
"udp:9777",   // Punktfunk native streaming (psicopompo)
"tcp:3100",   // Loki (kavure)
"tcp:8055",   // Directus (kuaray)
"tcp:81",     // Nginx Proxy Manager admin (kuaray)
"tcp:5030",   // slskd (kuaray)
"tcp:8191",   // Flaresolverr (kuaray)
"tcp:8265",   // Soularr (kuaray)
"tcp:3030",   // Vert (kuaray)
"tcp:8085",   // WordPress (kuaray) — missed by PR #12, caught by the CI guard (PR #13)

// new grant (1c)
{ "src": ["autogroup:member"], "dst": ["tag:edge"], "ip": ["tcp:443"] }
```

CI `tests` pin a concrete member e-mail on every restored port and on `tag:edge:443` — the full
list of what the guard now protects is in [§5b](#5b-the-ci-guard-what-the-tests-now-pin).

## 5b. The CI guard: what the tests now pin

**Why it exists.** Phase 3 proved that thin `tests` are worse than none: deleting the allow-all
grant silently cut nine catalogue tiles and the Valheim ports and CI stayed **green**. The owner's
rule, verbatim: *"da medo de perder acesso a serviços e ter que ficar pescando durante semanas o
que quebrou acesso e o que não."* The guard inverts that: a future tighten that cuts an expected
access now **fails CI**, and Tailscale **rejects the file** (nothing is applied).

**The expected-reach set** is the machine-readable "what the owner clicks" —
`ybytu:/home/ubuntu/homelab/homepage/config/services.yaml` (the tiles) plus the games and the admin
paths — cross-checked against the matrix in §4.
Everything pinned is a **static** port/tag (nothing that changes on its own).

| Consumer | Pinned paths |
|---|---|
| **Member** (concrete e-mail `ceduardorodrig@gmail.com`) | every Homepage-tile TCP port of grant (1) — 34 ports across psicopompo/kavure/kuaray/ybytu; the games (Minecraft + voice, Valheim, Zomboid — UDP) + Punktfunk QUIC; `tag:edge:443` (grant 1c); SSH `tag:server:22` (grant 6 + the `ssh` section); the subnet router (grant 3); the exit node (grant 2, pinned **positively**); DNS (grant 8); Syncthing transport (grant 9); KDE Connect (grant 12) |
| **Server plane** | the scrape `tag:monitoring → tag:server:9100`, the reverse `tag:server → tag:monitoring:3100`, server↔server `2049`/`2377`, the WoL relay `100.127.188.45:9096`, the Homepage→edge `tag:edge:443`, and the relay underlay `:40000` |

**How the guard is written** (three parser facts, each verified live — see
[`homelab-traps-2026-10.md`](homelab-traps-2026-10.md) §3):

- a test `src` **cannot be an autogroup** (`unknown user or host`) → member paths use the concrete
  owner e-mail;
- a test `dst` **cannot be a CIDR** → the subnet router is pinned with a **representative address
  inside the routed `/24`** (`192.168.3.1:22`);
- a test `src` **may be a tag** → the server plane uses `tag:server` / `tag:monitoring`.

**Mutation-tested — the guard is not inert.** Each mutation removes or changes one grant and is run
through the live validator (`POST /tailnet/-/acl/validate`, the same engine CI's `action: test`
uses); every one fails on the **exact** assertion:

| Mutation | Validator result |
|---|---|
| grant (1): delete `tcp:8055` (Directus) | ❌ `tag:server:8055` — want Accept, got Drop |
| grant (1c): edge `tcp:443` → `9999` | ❌ `tag:edge:443` — want Accept, got Drop |
| grant (1): delete Valheim `udp:2456-2458` | ❌ `tag:server:2456` — want Accept, got Drop |
| grant (6): SSH `tcp:22` → `9999` | ❌ `tag:server:22` — want Accept, got Drop |
| grant (3): subnet `ip:*` → `tcp:9999` | ❌ `192.168.3.1:22` — want Accept, got Drop |
| grant (2): exit node `ip:*` → `tcp:9999` | ❌ `198.51.100.8:22` — want Accept, got Drop |
| grant (9): Syncthing `tcp:22000` removed | ❌ `tag:server:22000` — want Accept, got Drop |
| the new `tcp:8085` removed | ❌ `tag:server:8085` — want Accept, got Drop |

The **first catch** was WordPress `:8085`: this document's §4.1 listed it as covered, but grant (1)
never carried the port — the Miracena "WordPress" tile was **down for every member**. PR #13 adds it
(additive; nothing else changes).

**What is deliberately NOT pinned (and why):**

- **Shared users' game ports** (grant 1b). `autogroup:shared` is rejected as a test `src`
  (`unknown user or host`), and naming a shared user's e-mail is accepted by the parser but the test
  engine **does not model shared access** — it asserts `want: Accept, got: Drop` for a path that
  works live ([tailscale#9259](https://github.com/tailscale/tailscale/issues/9259), re-verified
  2026-10-13 against `henrique.ams.souza@gmail.com`). The game ports are therefore guarded **live**
  (a shared player connects), not by CI.
- The **peer relay** capability (`tailscale.com/cap/relay`) and the **Funnel** attribute
  (`nodeAttrs.target`): application-level (no `ip`), invisible to network-layer `tests`; covered by
  the underlay pin + a live `tailscale status` check.

**Run it locally** (what CI does on the PR):

```bash
curl -sS -X POST -H "Authorization: Bearer $(/mnt/NVME_PCI/secrets/sops-decrypt.sh TS_API_TOKEN)" \
  -H "Content-Type: application/json" --data-binary @policy.hujson \
  https://api.tailscale.com/api/v2/tailnet/-/acl/validate   # → {} on success
```

## 6. Owner decisions (not implemented)

| Candidate | Why it was **not** auto-granted |
|---|---|
| `tcp:9092` (Sumænimá Backup tile, kavure) | Swarm **ingress** — the runbook §3 explicitly lists it as an infra port no human needs directly; the tile status already works via grant (5). **Open it only if the owner wants the click-through.** |
| `tcp:47990` / `tcp:47993` (Punktfunk mgmt API / plugin, psicopompo) | Not proven member-facing (the tile is `:47992`). The console SPA *may* call them from the browser — needs a live check before granting. |
| `udp:5353` (Punktfunk mDNS discovery, psicopompo) | LAN multicast discovery, not a tailnet path. |
| `tcp:16261` (Zomboid tile `href`) | No TCP listener exists on `16261` — the game is `udp:16261-16262` (already granted). The tile href is a game link, not a web service. |

## 7. Deliberately denied — confirmed still denied

| Port | Consumer | Mechanism |
|---|---|---|
| `2375` docker-socket-proxy | members | deny pin + absent from the member grant |
| `2049` NFS | members | deny pin + absent |
| `5000` registry | members | deny pin + absent |
| `2377`/`7946`/`4789` Swarm control plane | members | absent from the member grant |
| `22` SSH (raw path) | members | SSH is governed by the `ssh` section, not a blanket network grant |
| `9092` ingress | members | absent (infra — see §6) |
| exit node | `autogroup:shared` | grant (2) is members-only |

## 8. Adjacent lockout — host firewall, not the ACL

The 2026-10-13 host-firewall rollout (HB-047) introduced a **separate** regression, already recorded
in [`../network/ports.md`](../network/ports.md) §5: on **kuaray**, the host `INPUT` policy is `DROP`
with **no rule for the Docker subnets**, so a **container cannot reach its own host's tailnet IP** —
the `*arr` stack uses `100.94.209.99` for inter-service calls (`prowlarr`→Lidarr `:8686`,
`soularr`→Lidarr `:8686` / slskd `:5030`), which now time out. It is **independent of the ACL** and
needs a firewall/design decision, so it is out of scope for the ACL PR.

## 9. Verification

```bash
# The live policy (main == deployed; console locked).
curl -sS -H "Authorization: Bearer $(/mnt/NVME_PCI/secrets/sops-decrypt.sh TS_API_TOKEN)" \
  https://api.tailscale.com/api/v2/tailnet/-/acl | rg 'tcp:47992|tag:edge'

# The effective filter for a host (per-node INBOUND oracle).
tailscale debug netmap | jq '.PacketFilter'

# A restored path (member path can only be pinned by CI; probe from a server/tailnet host).
curl -sS --max-time 5 https://sumaenima.chimaera-heptatonic.ts.net/ -o /dev/null -w '%{http_code}\n'  # → 200
```

## 10. Residual findings reconciled (2026-10-13)

The D11 change (the *grande LAN*) also closed the **two residual findings** left by this audit, in
ACL PR [#14](https://github.com/ceduardorodrig/MNEMOCINE-ACL/pull/14):

| Finding | Verdict | Action |
|---|---|---|
| **`tcp:8766` (grant 1) — a dead port** | **removed** | The `sae-core_asciline` service does not exist — no container, image or published port on any node ([`../network/ports.md`](../network/ports.md) §2.2 correction). It was a dead grant entry, not a live tile; no `tests` assertion pinned it. Dropped from grant (1); the live `PacketFilter` on `psicopompo` no longer carries `:8766`. |
| **`ybyra:443` — doc vs reality** | **doc drift → [HB-052](../backlog.md)** | [`../network/ports.md`](../network/ports.md) §2.3 described `ybyra` `80`/`443` as a **native** *Nginx Reverse Proxy* (Certbot / Let's Encrypt). Live (2026-10-13): `:80` is the **containerized** `sae-edge_proxy` (`docker-proxy` → image `nginx-sumaenima`), and there is **no `:443` listener** on `ybyra` at all — the public TLS edge is the **Tailscale Funnel** (`sumaenima` / `miracena` / `kavure`), not `ybyra`'s own `443`. §2.3 corrected with the observed reality; the broader catalogue/baseline sweep stays [HB-052](../backlog.md). |

**Member ↔ member (D11).** Grant (7b) `autogroup:member → autogroup:member` (ip `*`) restores the
family's mutual visibility/reach (§4.1). It touches **no** consumer in §4.2–§4.6: a **tagged**
device is **not** a member (applying a tag removes the user identity), so the server class
(`tag:server`), the edge (`tag:edge`), monitoring and the relay are unaffected — verified live: on
the tagged `psicopompo` the `netmap` `PacketFilter` is identical to the pre-change filter **except**
the removed `:8766`, and **no** member IP is a `dst` there.

## References

- [`tailnet-acl-runbook.md`](tailnet-acl-runbook.md) — the phase-1/2/3 procedure and the additive-first rule
- [`tailnet-tagging.md`](tailnet-tagging.md) — the applied tag map and the tagging traps
- [`../network/tailscale.md`](../network/tailscale.md) — tailnet inventory, Funnels, subnet router, exit nodes
- [`../network/ports.md`](../network/ports.md) — the canonical port matrix (§4 accepted `0.0.0.0` binds)
- [`../services-catalog.md`](../services-catalog.md) — the *who depends on it* intent layer
- `MNEMOCINE-ACL/policy.hujson` — the policy itself (private; GitOps)
- PR [#12](https://github.com/ceduardorodrig/MNEMOCINE-ACL/pull/12) — this audit's fix
