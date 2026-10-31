---
tags: [homelab, network, tailscale, todo]
pending: [HB-087]
---

# kuaray decoupling — make kuaray exclusive to a client stack (Plan)

> **Status:** PLAN — nothing below is implemented. Opened **2026-10-30**.
> **Owner decision (2026-10-30):** `kuaray` becomes **exclusive to the client project hosted on it**.
> Every service that belongs to the homelab tailnet moves to another host. The client's own network,
> identity, DNS and licensing plan is **not** documented here: it lives in the client's private
> repository (this folder is published publicly every day at 04:45).

## 1. Principles

1. **One host, one network.** A host runs one `tailscaled`; it belongs to the homelab tailnet **or** to
   the client's network, never both.
2. **Additive first, destructive last.** `kuaray` leaves the homelab tailnet only after everything that
   depends on it has moved.
3. **Research → decide → document the why → implement**, one step at a time, with backup and rollback
   declared **before** each step ([multi-agent rites](../../governance/multi-agent-workflow.md)).
4. **Documentation follows ownership.** Homelab facts live here; client facts live in the client's
   repository. Cross-link with a neutral pointer, never by copying details.

## 2. Current state (verified 2026-10-30)

`kuaray` (`100.94.209.99`, behind CGNAT) runs two kinds of workloads:

| Belongs to | Services |
|---|---|
| **Client stack** (stays) | The containers prefixed `miracena-` and the sentinel daemon described in [`../services/miracena-stack.md`](../services/miracena-stack.md) |
| **Homelab tailnet** (must move) | `transmission`, `prowlarr`, `lidarr`, `slskd`, `soularr`, `flaresolverr`, `big-bear-vert`, `syncthing` (vault P2P), plus runtime infra: `autoheal`, `node-exporter`, `glances`, `watchtower`, `promtail`, `dockerproxy` (`:2375`, read by the Homepage on ybytu) |

Host-level homelab ties on kuaray: NFS client mounts (`/mnt/nas`), `hl-nic-power-tuning`, `cups`/`avahi`.

**Sizing of what must move (measured 2026-10-30):**

| Item | Size |
|---|---|
| `/mnt/storage/data` (torrents 2.2 GB, Soulseek downloads 13 GB) | ~15 GB |
| Service configs under `/home/kuaray/docker` | ~1 GB |
| **Total to move** | **~16 GB** |
| `/mnt/storage/backup` — Syncthing `backup` folder, **receive-only cold mirror of the NAS** ([`../services/syncthing.md`](../services/syncthing.md)) | **313 GB** — a separate homelab asset on the same disk (`/dev/sdb1`, 916 GB) |

## 3. Decisions to take before moving anything

| # | Question | Notes |
|---|---|---|
| **H1** | Where does the ~16 GB media stack land? | `kavure` has ~44 GB free on a disk at 80 % and ~5.6 GB RAM available: it fits only barely, so it needs a download quota. The alternative is `psicopompo`/NAS. |
| **H2** | What happens to the 313 GB cold mirror? | Decided 2026-10-30: it does not stay on the client host. Backups remain on the NAS and `psicopompo`; the Syncthing `backup` folder on kuaray is retired as part of the move, freeing the 916 GB disk. |

## 4. Phases

Each phase has an **exit criterion** and a **rollback**.

### Phase 1 — Decide H1 and size the target
**Exit:** a dated decision for H1 and a measured headroom on the target host.

### Phase 2 — Move the homelab services out of kuaray
One service at a time: low-risk first (`flaresolverr`, `big-bear-vert`), then the media chain
(`prowlarr` → `lidarr` → `slskd` → `soularr` → `transmission`), then `syncthing`, then the runtime infra.
Per service: backup config and data, bring it up on the target host, verify as the end user, update every
consumer, then stop (do not delete) the source for a cooling-off period.

**Surfaces to update in the same step as each move:**
- Homepage on **ybytu** — `services.yaml` tiles, `siteMonitor` targets and the `kuaray` Docker-socket entry.
  ⚠️ This config has **no repository copy today** ([`../services/homepage.md`](../services/homepage.md)); put it under version control as part of this phase.
- `services-catalog.md`, `network/ports.md`, `network/topology.md`, `servers/kuaray.md`, the target host's server doc, `services/*.md`
- Uptime Kuma monitors, Loki/promtail targets, Prometheus scrape jobs
- ACL repo `MNEMOCINE-ACL`: grants that reference kuaray
- Backups: `config-backup` coverage for the new host

**Exit:** nothing the homelab tailnet needs runs on kuaray. **Rollback:** start the stopped source containers.

### Phase 3 — kuaray leaves the homelab tailnet
Last and the only hard-to-reverse step, and it happens only once the client's own network is ready. Re-point
every consumer of `100.94.209.99`, then remove kuaray from the homelab tailnet and audit the lockout
([`../guides/acl-lockout-audit.md`](../guides/acl-lockout-audit.md)).
**Exit:** every consumer works from its own network; the lockout audit is clean.
**Rollback:** re-enroll kuaray in the homelab tailnet (keep its node key valid until the audit passes).

## 5. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| kavure disk (80 %) and RAM | Instability of existing kavure services | Decide H1 first; watch free space during each move |
| Consumers hard-coded to `100.94.209.99` | Silent breakage after Phase 3 | Inventory every consumer; re-point before the move |
| Cold mirror on kuaray's disk | kuaray not truly exclusive | Decision H2 above |
| Documentation published daily to a public repository | A client fact leaks | Documentation follows ownership (principle 4); see HB-087 |

## 6. Related

- [`kavure-migration-plan.md`](kavure-migration-plan.md) — the previous host migration, as a format reference
- [`tailscale.md`](tailscale.md) · [`topology.md`](topology.md) · [`../guides/acl-lockout-audit.md`](../guides/acl-lockout-audit.md) · [`../services/miracena-stack.md`](../services/miracena-stack.md) · [`../services/homepage.md`](../services/homepage.md) · [`../services/syncthing.md`](../services/syncthing.md)
