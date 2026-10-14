---
tags: [homelab, meta, network, tailscale, docker]
pending: [HB-052]
---

# Security Baseline — Mnemocine Homelab

> **This is a policy document, not a how-to.** It states the homelab's security posture: the
> layers that make up the attack surface, the control that governs each layer, what is enforced
> today, and where the gaps are. The *procedures* that close those gaps live in their own
> runbooks — [`tailnet-acl-runbook.md`](tailnet-acl-runbook.md) and
> [`ufw-lan-runbook.md`](ufw-lan-runbook.md).
>
> **Baseline as of 2026-10-13.** Facts here were verified by read-only reconnaissance across the
> fleet; the open gaps are tracked in the [homelab backlog](../backlog.md).

## 1. Threat model in one paragraph

The homelab is a single flat trust domain wrapped in one encrypted mesh. Every host, phone, and
container that joins the tailnet can, today, reach every other one on every port — including the
Docker control socket (`2375`), NFS (`2049`), and the Swarm control plane. The perimeter that
*matters* is therefore not "is it encrypted" (it is) but "who inside is allowed to reach what".
That question is answered in exactly one place: the **Tailscale ACL policy**. Host firewalls and
Docker's port publishing shape the *outer* edge; they do not police the tailnet.

## 2. The three layers

The homelab's reachability is decided by three independent layers. Each has one owner-control;
each is auditable separately.

| # | Layer | What it covers | Control that governs it |
|---|---|---|---|
| 1 | **Tailnet** | Traffic between tailnet peers over `tailscale0` / WireGuard | **Tailscale ACL policy** (`MNEMOCINE-ACL`, GitOps) |
| 2 | **LAN / public** | Host sockets on the physical LAN (`192.168.3.0/24`) and the open Internet | **Host firewalls** (UFW / nftables) + the OCI security list |
| 3 | **Docker** | Container-published ports and the Swarm overlay | **Docker's own iptables chains** (`DOCKER-USER`), *not* the host firewall by default |

### Layer 1 — The tailnet (Tailscale ACLs)

**Control:** the ACL policy, version-controlled in the private repo `MNEMOCINE-ACL` and deployed
via the official `tailscale/gitops-acl-action` (`action: test` on PRs, `action: apply` on `main`).
"Prevent edits in the admin console" is enabled, so Git is the single source of truth. See
[`../network/tailscale.md`](../network/tailscale.md).

**Current state (2026-10-13) — allow-all still present, tags now applied:**

- The effective packet filter **still includes** the allow-all rule (`grants {src:*, dst:*, ip:*}`
  — all tailnet sources **plus `192.168.3.0/24`** → all destinations, ports `0–65535`, protocols
  TCP/UDP/ICMP/ICMPv6). Phase 1 added the tag-based grants **on top of** it and Phase 2 applied the
  tags, so the policy now *declares* least privilege while the *effective* filter remains
  allow-all — **until Phase 3 deletes the rule** (the single remaining step).
- **The devices now carry purpose tags** (`tag:server`, `tag:edge`, `tag:subnet-router`,
  `tag:exit-node`, `tag:monitoring`, `tag:registry`); the applied map and the rules for future
  devices are in [`tailnet-tagging.md`](tailnet-tagging.md). **User devices stay untagged** — but
  note that under allow-all the family's **non-admin** devices were full tailnet members.
- `tagOwners` and the **accept** `tests` are now **live**; the **`deny` pins** are deliberately
  deferred to Phase 3 (a `deny` assertion is false by construction while an allow-all grant is
  present).
- The `ssh` section is now **four rules**: `autogroup:self` (untagged devices) accepts
  `root`+nonroot; tagged servers get `check` for `root` and `accept` for nonroot from an admin;
  and `tag:server → tag:server` — added after a live outage, because **a tagged node connects out
  as its tag**, so `psicopompo` (itself `tag:server`) no longer matched the admin rule.

**The single most important fact:** *the host firewall cannot filter tailnet traffic.* Tailscale
installs `ts-input` / `ts-forward` and accepts `tailscale0` **before** the user's INPUT/FORWARD
rules run. The Tailscale maintainers confirmed this is intentional: **the ACL is the tailnet
firewall.** So UFW or nftables rules are irrelevant to Layer 1 — tightening the tailnet *means
editing the ACL*, nothing else.

**Consequences of allow-all:**

- **~90% of inter-service dependencies ride the tailnet** and therefore depend on the ACL for
  authorization, not authentication: Swarm advertises tailnet IPs; NFS (`2049`) on psicopompo;
  Loki / Prometheus / Grafana; split-DNS (AdGuard / Pi-hole / unbound); the private registry
  (`5000`); the GPU gateway `hl-infer` (`9095`); SearXNG; and the **Wake-on-LAN relay**
  (`tailnet:9096`) that powers hosts back on.
- **The LAN is reachable *through* the tailnet.** `kavure` is a **subnet router** for
  `192.168.3.0/24` (auto-approved via `autoApprovers.routes`, but **no grant** authorizes the
  subnet itself) and an **exit node**; `ybytu` is also an **exit node**. Because the allow-all
  filter includes `192.168.3.0/24` as a source, the whole home LAN is today inside the same flat
  policy as the servers — a path *around* any per-port rule unless the subnet is granted
  explicitly.
- **`ybyra` depends on the peer relay** (`ybytu :40000`, verified live: `ybyra` shows
  `peer-relay …:40000`). The `cap/relay` grant is what makes this work; removing it breaks
  `ybyra`'s connectivity.
- **`kavure` is shared with users outside the tailnet** (Tailscale node sharing). Shared users
  arrive as `autogroup:shared`, and today nothing stops them from using `kavure`/`ybytu` as
  **exit nodes** — they must **not** get that.
- **The Funnel `nodeAttrs` still allows *any* member to open a public Funnel.** `tag:edge` was
  added on 2026-10-13 (so the tagged Funnel nodes `sumaenima`/`miracena` keep working) but
  `autogroup:member` was kept during the transition; Phase 3 drops it, making the Funnel
  `tag:edge`-only. Until then, any member device could publish a port to the open Internet — a
  tailnet→public escalation path.

### Layer 2 — LAN / public (host firewalls)

**Control:** the host's own firewall (UFW on Debian/Ubuntu, nftables on the OCI hosts) plus, on
the cloud nodes, the OCI security list.

| Host | Firewall state (verified) | Notes |
|---|---|---|
| `psicopompo` | **UFW active** + tailnet-aware `DOCKER-USER` block (**HB-047 step 1**, 2026-10-13) | Container-published ports are now **tailnet-only**; the `after.rules` block is in place **without** the `-s 192.168.0.0/16` trusted RETURN (the first draft carried it and closed nothing — see [`ufw-lan-runbook.md`](ufw-lan-runbook.md) §2). `DEFAULT_FORWARD_POLICY` was `ACCEPT` until **2026-10-13**, now **`DROP`** (owner's go-ahead, same day; the tailnet is unaffected — `ts-forward` accepts `tailscale0` first, and container egress rides the `DOCKER-USER`/`DOCKER-FORWARD` chains — verified: tailnet `:5000`/`:9095` open, Swarm 3/3 `Ready`, local `:9095` → `ok`). No OpenSSH listener. |
| `kavure` | **UFW active** (`tailnet-only`, **HB-047 step 3**, applied & verified 2026-10-13) | Default deny incoming + `DEFAULT_FORWARD_POLICY="DROP"`; the tailnet-aware `DOCKER-USER` block is in place (no `192.168.0.0/16` RETURN), so every published container port (incl. the Swarm ingress `9092`) is **tailnet-only**. No LAN exceptions needed (Samba/xrdp live on `kuaray`). |
| `kuaray` | **UFW active** (`tailnet-only`, 2026-10-13 — HB-047 step 2/3) | Standby mirror; its `0.0.0.0` service binds are now tailnet-only, with the §3.1 host services (Syncthing 22000, Samba 139/445, xrdp 3389) kept for the LAN. LAN SSH (`22`) is now closed — Tailscale SSH only. **Socket re-bind done 2026-10-13 (HB-047, defense-in-depth):** the 8 published container ports (`9696/8686/8191/9091/5030/8265/3030` + Node Exporter `9100`) and `rpcbind` (`111`) now bind the tailnet IP / loopback — see [`../network/ports.md`](../network/ports.md) §5. |
| `ybytu` | **nftables** (host INPUT accepts `tailscale0` + an explicit allow list) | No `ufw` binary. |
| `ybyra` | **nftables** (host INPUT accepts `tailscale0`, `22`, peer-relay UDP only) | No `ufw` binary. |

**What is LAN-only (must survive a tailnet-only hardening):** Syncthing transport (`22000`,
LAN **and** `tailscale0`), the netwatch `lan_*` path probes, Samba/SMB (`139/445`), `xrdp`
(`3389`), Punktfunk native (`9777/udp`, `47990`, `47992/47993`), and Home Assistant
mDNS/SSDP/Zeroconf discovery. These are legitimately reachable from the physical LAN and are the
exceptions a firewall policy must keep.

> **Corrected 2026-10-13 — `25565` (Minecraft) is NOT a LAN exception.** The owner confirmed that
> **nobody plays over the LAN**: every player reaches `kavure` over the **tailnet** (its tailnet IP
> `100.124.146.77`), and the shared players (`autogroup:shared`) have no LAN path at all
> ("shared machines do not advertise subnets"). `25565` is therefore covered by the **tailnet**
> grant, not by a host LAN allow-rule — see [`tailnet-acl-runbook.md`](tailnet-acl-runbook.md) §4.

**Public surface — deliberately tiny:** only **`sshd:22` on the two OCI hosts** (`ybytu`,
`ybyra`) plus **3 Tailscale Funnels** (`kavure:10000` → AioStreams, `sumaenima`, `miracena`).
Funnels are the sharp edge: they **bypass both the host firewall and the OCI security list**,
because the public listener is terminated inside `tailscaled`, not by a host socket. The only
control over them is the Funnel `nodeAttrs` in the ACL (see Layer 1).

### Layer 3 — Docker (published ports bypass the host firewall)

**Control:** Docker's `DOCKER-USER` iptables chain. The host firewall does **not** filter
container-published ports: Docker DNATs the packet in `nat/PREROUTING` **before** it reaches the
`INPUT` chain, so a UFW `deny` never sees it. This is documented Docker behaviour, and the
supported fix is the `DOCKER-USER` chain (e.g. via `ufw-docker`).

**Consequences:**

- A service published with `ports: - "8080:8080"` is reachable on **every** host interface —
  LAN and tailnet — even with UFW active. The `⚠️ defect` rows in
  [`../network/ports.md`](../network/ports.md) are exactly this class.
- Any Docker-aware firewall integration **must** whitelist the tailnet, or it cuts the tailnet
  itself. The `--docker-subnets` set must include **`100.64.0.0/10`** (plus the Docker internal
  ranges), otherwise `DOCKER-USER` drops legitimate tailnet→container traffic.
- Under **Swarm**, the automated `ufw-docker-agent` global service would place a **privileged
  container on the public edge** — a worse trade than editing `after.rules` by hand. See the
  [`ufw-lan-runbook.md`](ufw-lan-runbook.md).
- **Container → host is a *separate* path, and the host firewall *does* govern it.** A container
  reaching a service on its **own host** is local delivery → `INPUT`, not `DOCKER-USER`; with
  `INPUT DROP` this breaks every container→host call — a `network_mode: host` service (Node
  Exporter) and a **default-bridge** published port (Docker's `! -i docker0` guard leaves it
  un-DNAT'd). Fixed 2026-10-13 with a **scoped** `INPUT` allow — see
  [`ufw-lan-runbook.md`](ufw-lan-runbook.md) §0.3/§3.2 and [`../network/ports.md`](../network/ports.md) §5.

## 3. Controls in place (2026-10-13)

| Control | Where | What it buys |
|---|---|---|
| **OpenSSH key-only** | `kavure`, `kuaray` via `/etc/ssh/sshd_config.d/00-homelab.conf` (`PasswordAuthentication no`, `KbdInteractiveAuthentication no`) | Password brute force over LAN is closed; verified `sshd -T` → `passwordauthentication no` and a LAN test returns `Permission denied (publickey)`. |
| **fail2ban** | `ybytu`, `ybyra` (jail `sshd`) | Bans brute-force sources; `ignoreip` includes `100.64.0.0/10`, so tailnet peers are never banned. |
| **Tailscale SSH** | `RunSSH: true` on the servers | Tailnet admin access is authenticated by the tailnet identity, not by host keys — no `:22` exposure needed. |
| **Tailnet purpose tags** | applied live 2026-10-13 | `tag:server`/`edge`/`subnet-router`/`exit-node`/`monitoring`/`registry` on the infra devices; **user devices stay untagged**. Enables the tag-based grants and `ssh` rules; the *enforcement* lands with Phase 3. Map + rules: [`tailnet-tagging.md`](tailnet-tagging.md). |
| **OpenSSH is LAN-only** | `ybyra` | The `:22` seen over the tailnet is Tailscale SSH; the OpenSSH daemon only serves the physical LAN. |
| **`kuaray`/`kavure` OpenSSH is tailnet-only** | `kuaray`, `kavure` | HB-047 steps 2–3 (2026-10-13) enabled UFW with `:22` allowed **only on `tailscale0`**, so **LAN SSH is closed** on both — an **owner decision** aligned with tailnet-only (no LAN SSH is needed; the admin path is Tailscale SSH). Tailscale SSH is unaffected. **Reversal (one line):** `sudo ufw allow 22/tcp comment 'OpenSSH (LAN)'`. |
| **No OpenSSH on psicopompo** | `psicopompo` | `sshd` is inactive, has no host keys, and binds no TCP `:22` — the port is 100% Tailscale SSH. |
| **GitOps ACL + console lockout** | `MNEMOCINE-ACL` | Policy changes go through a reviewed PR; console edits are overwritten. |

## 4. Open gaps

Each gap is a tracked backlog item. The detail lives in the linked document.

| Gap | Backlog | Severity | In one line |
|---|---|---|---|
| Tailnet **allow-all grant still present** — tags applied and the least-privilege rules deployed (Phases 1+2), but the rule is not yet deleted; Funnel still `member`+`edge`; **two grant gaps** (`tag:monitoring → tag:server`, `tag:server → tag:server`) | [**HB-049**](../backlog.md) | 🔴 | The ACL/tag redesign — **Phase 3 (the tighten) is the remaining work**; runbook: [`tailnet-acl-runbook.md`](tailnet-acl-runbook.md) |
| **Secret hygiene** | [**HB-051**](../backlog.md) | 🟡 | Plaintext `TS_AUTH_KEY` in a running service spec; a static token in a service doc; vestigial SSH keys that break the documented key fallback |
| **Service catalogue + security baseline + Stênio reconciliation** | [**HB-052**](../backlog.md) | 🟡 | This document is part of it; the machine-readable catalogue and the reality-vs-declaration invariants remain |
| **LAN binds + host firewalls** | [**HB-047**](../backlog.md) | 🔴 | Re-bind the `0.0.0.0` sockets and enable UFW on `kavure`/`kuaray`; runbook: [`ufw-lan-runbook.md`](ufw-lan-runbook.md). **Progress 2026-10-13:** the **host-firewall rollout is COMPLETE 3/3** (`psicopompo`, `kuaray`, `kavure` — all tailnet-only, `DEFAULT_FORWARD_POLICY="DROP"`). The **socket re-bind half** is done on **`kuaray`** (8 container ports + rpcbind → tailnet/loopback) and reviewed on **`psicopompo`** (no live defect; Stremio accepted as a fixed bind) — see [`../network/ports.md`](../network/ports.md) §5. **Remaining:** the `⚠️ defect` rows on **`kavure`** and **`ybytu`** (parent-coordinated). Now **defense-in-depth**, not exposure (the firewall already removed the LAN reach). |

## 5. What good looks like (Tailscale official best practices)

The target posture, distilled from Tailscale's policy best practices. The ACL runbook implements
this checklist; this section is the acceptance criteria.

- [ ] **Least privilege** — grant only the ports/services actually consumed, derived from a real
      catalogue, never `* → *`.
- [ ] **Tags describe purpose, not ownership** — `tag:server`, `tag:edge`, `tag:monitoring`,
      `tag:registry`, `tag:subnet-router`, `tag:exit-node`; a device is tagged for *what it does*.
- [ ] **Never tag user devices** — phones/laptops stay untagged and are reached via
      `autogroup:member` / `autogroup:self` (the officially recommended practice).
- [ ] **`check` mode for sensitive SSH** — return SSH `root` to an interactive `check`; `accept`
      only for non-root.
- [ ] **Policy `tests`** — pin both the allowed admin path **and** the denials, so a future edit
      that re-opens the tailnet fails CI.
- [ ] **GitOps** — the policy lives in Git, changes land via reviewed PRs, console edits are
      locked.
- [ ] **Device approval** — new devices need explicit approval before joining.
- [ ] **Auth-key hygiene** — no long-lived reusable keys; scoped/ephemeral keys; regenerate keys
      **with a tag** so new devices are born tagged and key expiry is off for servers.
- [ ] **Remove unused keys and nodes** — a periodic sweep of stale devices and auth keys.

## References

- [`tailnet-acl-runbook.md`](tailnet-acl-runbook.md) — moving the tailnet from allow-all to least privilege
- [`ufw-lan-runbook.md`](ufw-lan-runbook.md) — making host firewalls enforce tailnet-only
- [`../network/tailscale.md`](../network/tailscale.md) — tailnet inventory, exit nodes, subnet router, Funnels, peer relays
- [`../network/ports.md`](../network/ports.md) — canonical port catalog and attack-surface matrix
- [`../network/topology.md`](../network/topology.md) · [`../network/nfs.md`](../network/nfs.md) · [`../network/dns.md`](../network/dns.md)
- [`secrets-centralizados.md`](secrets-centralizados.md) — the SOPS/age secret store
- [`../backlog.md`](../backlog.md) — the open items referenced above
- Tailscale policy best practices: <https://tailscale.com/kb/1337/policy-syntax> and the ACL GitOps action <https://github.com/tailscale/gitops-acl-action>
