---
tags: [homelab, meta, network, docker, tutorial]
pending: [HB-061, HB-086]
---

# Design Decisions — 2026-10 Dossier

> **What this is.** On **2026-10-13** the tailnet went deny-by-default, the host firewalls were
> turned on and several sub-agents worked the fleet in parallel. That produced a set of open
> *decisions* — not bugs — that are the owner's call. This document is the **dossier**: it states
> each one, the options and their trade-off, a candidate recommendation, and **the official source
> to read before deciding**. **D1–D10 are open**; each carries a `Decision:` line for the owner to
> fill in. **D11 was decided by the owner** (the *grande LAN*) and **implemented 2026-10-13**
> (ACL PR [#14](https://github.com/ceduardorodrig/MNEMOCINE-ACL/pull/14)) — recorded here as the reference.
>
> **The method (owner, 2026-10-13):** *research the official doc → **decide** → **document the why
> with the date** (so a reversal is cheap) → implement.* The date matters: a decision recorded with
> its rationale can be revisited in one line; an undocumented one costs a full re-investigation.
>
> **Linked item:** the mother row is [**HB-061**](../backlog.md) (D1–D10 are *siblings*: four of
> them already have their own backlog row and are **referenced here, not duplicated** —
> HB-059 (D4), HB-060 (D6), HB-047 (D9), HB-013 (D10)). **D11** had its own row,
> [**HB-063**](../backlog-archive.md) (**resolved 2026-10-13**). The detailed evidence for the network items lives in
> [`acl-lockout-audit.md`](acl-lockout-audit.md) §6, [`ufw-lan-runbook.md`](ufw-lan-runbook.md)
> §3.1/§3.2 and [`../network/ports.md`](../network/ports.md) §5.

## Summary

| # | Decision | Kind | Owner cost | Reference |
|---|---|---|---|---|
| D1 | Swarm ingress `tcp:9092` — open the tile click? | policy | 1 grant, reversible | this doc |
| D2 | Punktfunk `tcp:47990`/`47993` — does the SPA call them? | needs a live browser test | one probe | this doc |
| D3 | Punktfunk `udp:5353` mDNS — LAN, not tailnet | confirm | none | this doc |
| D4 | Container → LAN egress (`DOCKER-FORWARD`) | design | per-host rule | **HB-059** |
| D5 | Hub PRs #48 (Tailwind v4) / #49 (`edge.yml`) — merge? | release | review + QA | this doc |
| D6 | `kururu` has no administrative path | design/ops | per-node key or SSH server | **HB-060** |
| D7 | Stênio engine release (`757e434` untagged) | release | one tag | this doc |
| D8 | `TS_AUTH_KEY` — accept the risk (do **not** rotate) | security risk acceptance | durable fix later | this doc |
| D9 | `HB-047` re-bind of `kavure`/`ybytu` (defense-in-depth) | security hardening | one host at a time | **HB-047** |
| D10 | `HB-013` — reboot `ybytu` to prove persistence | proof | a reboot window | **HB-013** |
| D11 | Members reach each other's devices (the *grande LAN*) — **✅ implemented 2026-10-13** (PR [#14](https://github.com/ceduardorodrig/MNEMOCINE-ACL/pull/14)) | policy | 1 grant, reversible | this doc · **HB-063** |
| D12 | ComfyUI — interactive use **is allowed** outside the batch windows, via an `other`-kind lease (**✅ decided 2026-10-14**, owner) | GPU policy | verified live; may delay `image_gen` jobs | [`../services/comfyui.md`](../services/comfyui.md) · **HB-036** |
| D13 | The autopilot's **production** scheduler runs on `kavure` (24/7); `psicopompo` stays the dev/build host and the GPU fallback. Ollama is exposed to the tailnet through a **kernel-bound** forwarder — and the **tailnet ACL**, not UFW, is the enforcement point (**✅ implemented 2026-10-19**) | host topology + security | one drop-in + one socket unit + one ACL-scoped service | [`../services/autopilot.md`](../services/autopilot.md) · **HB-076/HB-077** |
| D15 | `SEC-SUDO` on `security/audit-access-fleet.sh` — keep `sudo -n` as a **reviewed** privilege point (**✅ decided 2026-10-30**, owner: option C) | security | none (no host change) | this doc · **HB-086** |
| D16 | `kuaray` becomes exclusive to a client stack; the homelab-tailnet services move out (**✅ decided 2026-10-30**, owner) | host topology | one service move at a time, each with a rollback | [`../network/kuaray-decoupling-plan.md`](../network/kuaray-decoupling-plan.md) · **HB-087** |

---

## D1 — Swarm ingress `tcp:9092` (the Sumænimá Backup tile)

**(a) What it is.** `tcp:9092` on `kavure` is the **Swarm ingress** published port (the backup
integrity healthcheck + the routing-mesh endpoint). The Homepage tile *"Sumænimá Backup"* links to
it. After the phase-3 tighten the tailnet ACL deliberately does **not** grant `autogroup:member`
`:9092` — the tile's **status** still works because Homepage probes it **server-side** over
`tag:server` (grant 5). Evidence: [`acl-lockout-audit.md`](acl-lockout-audit.md) §4.1 (*"Swarm
ingress — infra, runbook §3 … the tile status already works via grant (5)"*) and §6.

**(b) Options / trade-off.**

| Option | Trade-off |
|---|---|
| **(i)** Add `tcp:9092` to the member grant | The tile becomes clickable — but every member device gains a path to the **Swarm ingress mesh** (an infra endpoint), widening the member-reachable surface on a service the ACL was built to keep infra-only. |
| **(ii)** Leave it closed; rely on the tile **status** | Least privilege preserved; the tile click does nothing (the status dot still goes green). |
| **(iii)** Publish the service `mode: host` (or behind the tailnet-only firewall) and let the tile point at the host IP | The click works **without** exposing the ingress mesh and the host firewall already removes the LAN path — but it changes the stack's publish mode and needs a redeploy. |

**(c) Candidate recommendation.** Keep closed (ii) **unless the owner actually clicks through**;
if he does, prefer (iii) over (i) — it gives the click without adding ingress reachability.
**Decision:** _open — owner to decide (date: ____, why: ____)._

**(d) Official source to consult first.**
[Docker — *Use swarm mode routing mesh*](https://docs.docker.com/engine/swarm/ingress/) (ingress
vs `mode: host`) and [Tailscale policy syntax](https://tailscale.com/kb/1337/policy-syntax) (§ the
`ip:` field).

---

## D2 — Punktfunk `tcp:47990` / `tcp:47993` (management API + plugin)

**(a) What it is.** The Punktfunk **console** tile is `tcp:47992` (already granted and fixed in
PR #12). The host also listens on `tcp:47990` (**management API**, HTTPS + mTLS/bearer) and
`tcp:47993` (**plugin interface**). They are **not proven member-facing**: the console SPA *may*
call the management API from the browser. Evidence: [`acl-lockout-audit.md`](acl-lockout-audit.md)
§6 (*"the console SPA may call them from the browser — needs a live check before granting"*) and
[`services/punktfunk.md`](../services/punktfunk.md) (port table).

**(b) Options / trade-off.**

| Option | Trade-off |
|---|---|
| **(i)** Grant `47990`/`47993` to members now | Removes the "maybe it breaks" risk — but grants two ports **not proven** to be consumed; the management API is the higher-privilege surface. |
| **(ii)** Leave closed until a **live browser test** proves the SPA calls them | Nothing extra is exposed; the risk is that the console UI silently fails in-browser if it does call them. |

**(c) Candidate recommendation.** Do the **live test first** (see (d)): open the tile from a member
device with the browser network trace; grant **only** what the trace proves. Do not guess.
**Decision:** _open — owner/operator to run the probe, then decide (date: ____, why: ____)._

**(d) Official source to consult first.**
[Punktfunk — official docs](https://docs.punktfunk.unom.io) (management API vs console vs plugin
ports); the browser devtools **Network** panel is the actual evidence to capture.

---

## D3 — Punktfunk `udp:5353` (mDNS discovery)

**(a) What it is.** Punktfunk advertises itself on the **LAN** with `udp:5353` (mDNS). This is
**multicast discovery on the local segment** — it is not a tailnet path (Tailscale does not flood
multicast between peers). Evidence: [`acl-lockout-audit.md`](acl-lockout-audit.md) §6 (*"LAN
multicast discovery, not a tailnet path"*); the port is listed as a **LAN exception** in
[`ufw-lan-runbook.md`](ufw-lan-runbook.md) §3.1.

**(b) Options / trade-off.**

| Option | Trade-off |
|---|---|
| **(i)** Keep mDNS **LAN-only** (status quo) | Clients on the LAN auto-discover; tailnet clients connect to the known tailnet IP directly (no discovery). Nothing to change. |
| **(ii)** Try to make discovery work over the tailnet | Would need a unicast/advertise mechanism the protocol does not offer by default; added complexity for a convenience feature. |

**(c) Candidate recommendation.** Confirm (i): leave mDNS on the LAN and document that tailnet
clients reach Punktfunk by IP. **Decision:** _open — owner to confirm (date: ____, why: ____)._

**(d) Official source to consult first.**
[RFC 6762 — Multicast DNS](https://datatracker.ietf.org/doc/html/rfc6762) (mDNS is link-local) and
[Tailscale — *Subnet routers and traffic relay nodes*](https://tailscale.com/kb/1019/subnets)
(multicast is not carried across the tailnet).

---

## D4 — Container → LAN egress is open (`DOCKER-FORWARD`)

> **Referenced, not duplicated:** this is **[HB-059](../backlog.md)**. The full symptom, the exact
> chain and the `soularr → 192.168.3.1:80` reproduction are in
> [`ufw-lan-runbook.md`](ufw-lan-runbook.md) §3.2 and the backlog row.

**(a) What it is (one line).** A container reaching the **LAN** (`192.168.3.0/24`) is a **`FORWARD`**
packet and rides Docker's pre-existing `DOCKER-FORWARD` chain; the `DOCKER-USER` block trusts the
Docker subnet **sources**, so it does not filter this — a lateral-movement path kept open for
container **egress**.

**(b)/(c) Options + recommendation.** Keep the egress (downloads/HTTP need it) **or** close it
(`DOCKER-USER` negative rule for the LAN destinations) — the trade-off and the candidate
recommendation are in the HB-059 row. **Decision:** _open — owner (tracked by HB-059)._

**(d) Official source to consult first.**
[Docker — *Packet filtering and firewalls*](https://docs.docker.com/engine/network/packet-filtering-firewalls/)
(the `DOCKER-USER`/`DOCKER-FORWARD` chain order).

---

## D5 — The two open hub PRs: #48 (Tailwind) and #49 (`edge.yml`)

**(a) What they are.** Both are open on `SUMAENIMA-HUB`, **CI green** and **MERGEABLE**
(`gh pr view`, 2026-10-13):

| PR | Title | Size | Risk |
|---|---|---|---|
| **#48** | `chore(deps): migrate Tailwind CSS v3 → v4 (drops the braces advisory chain)` | 45 files, +604/−948 | Large frontend change; **not verified in a browser** (no headless browser on the host); CI runs only `tsc --noEmit` + `npm run build`. Removes the `high: 4` advisory (`braces`) → `high: 0`. |
| **#49** | `fix(edge): autenticar o tunnel com a chave tag:edge (TS_EDGE_AUTH_KEY)` | 4 files, +84/−11 | Small; `edge.yml` interpolated `${TS_AUTH_KEY}` which became a `tag:server` key → authenticating the edge with it would **remove `tag:edge`** and drop the public Funnel. The **live spec was already fixed**; the PR stops the **repo** from regressing on a future `stack deploy`. |

**(b) Options / trade-off.**

| Option | Trade-off |
|---|---|
| **Merge #49** | Tiny, CI green, prevents a real Funnel regression on the next deploy. No deploy in the PR (the live spec is already correct). |
| **Merge #48** | Removes a real advisory chain, but it is a 45-file CSS migration; CI cannot see the rendered UI, so a visual regression would land unseen. |
| **Merge neither** | Both stay as safe drafts; #49's protection is not in `main`. |

**(c) Candidate recommendation.** Merge **#49** (low risk, prevents a regression). For **#48**,
merge only **after** a browser QA pass on the routes the PR lists (`/`, `/rec`, `/arandu`, `/docs`,
`/quem-somos`, `/contato`, `/privacidade`, `/settings`) — the gate cannot substitute for eyes on the
render. **Decision:** _open — owner (date: ____, why: ____)._

**(d) Official source to consult first.**
[Tailwind CSS v4 — Upgrade guide](https://tailwindcss.com/docs/upgrade-guide) (the migration the PR
claims to follow); [Tailscale — Auth keys](https://tailscale.com/kb/1085/auth-keys) and
[Funnel node attribute](https://tailscale.com/kb/1223/funnel) (why a `tag:server` key drops
`tag:edge`).

---

## D6 — `kururu` has no administrative path

> **Referenced, not duplicated:** this is **[HB-060](../backlog.md)**, with the node detail in
> [`servers/kururu.md`](../servers/kururu.md) §DNS and
> [`dns-consistency-map.md`](dns-consistency-map.md) §4.2.

**(a) What it is (one line).** `kururu` is L3-reachable (`tailscale ping` → `pong … 4 ms`; Dropbear
on `192.168.3.55:22`) but runs **no Tailscale SSH server** and its Dropbear rejects the audit key
(the only local `id_ed25519` is passphrase-protected, no agent loaded) — so it cannot be audited or
patched from the tailnet and its resolver topology stays unmapped.

**(b)/(c) Options + recommendation.** (i) install a Tailscale SSH server (Alpine/musl) to match the
fleet, or (ii) provision a non-interactive (agent-loadable) key for Dropbear — the smaller change
for an audit path. Candidate recommendation and trade-off in the HB-060 row.
**Decision:** _open — owner (tracked by HB-060)._

**(d) Official source to consult first.**
[Tailscale SSH](https://tailscale.com/kb/1193/tailscale-ssh);
[Alpine Linux Wiki — Tailscale](https://wiki.alpinelinux.org/wiki/Tailscale);
[postmarketOS — Samsung Galaxy Tab 3 Lite 7.0 (`samsung-goyawifi`)](https://wiki.postmarketos.org/wiki/Samsung_Galaxy_Tab_3_Lite_7.0_(samsung-goyawifi)).

---

## D7 — The Stênio engine release (`757e434` is untagged)

**(a) What it is.** The engine `main` is at **`757e434`** (`feat(homelab): HB-054 align --health with
the port auditor; HB-020 HOMELAB-NAMING-SERVICE`), **one commit ahead** of the last release tag:

```console
$ git -C governance/stenio describe --tags
v4.5.0-1-g757e434          # HEAD is v4.5.0 + 1 commit
$ git -C governance/stenio log --oneline -1
757e434 feat(homelab): HB-054 … HB-020 …
```

Consumers call `…/STENIO-SENTINEL/.github/actions/stenio-check@v1`; the **`v1` action track** points
at the last **published release binary** (the `release.yml` moves `v1` on each tag). So the two new
rules in `757e434` (`HOMELAB-NAMING-SERVICE`, the `--health` port-view alignment) are **not** in the
consumers' CI until a new tag is published. Evidence:
[`guides/stenio-ci-unificado.md`](stenio-ci-unificado.md) §Tagging Conventions and
[`../../governance/release-policy.md`](../../governance/release-policy.md) §3b.

**(b) Options / trade-off.**

| Option | Trade-off |
|---|---|
| **(i)** Tag a release (e.g. `v4.5.1`) | The `v1` action moves and every consumer picks up the new rules — **all at once** (the declared risk of §3b). `release.yml` only publishes after `--self-test` and `--guardian` pass. |
| **(ii)** Leave untagged | Consumers stay on the old rules; the safety net for naming/health is not deployed. |

**(c) Candidate recommendation.** Tag (i) once `--self-test` + `--guardian` are green — it is one
command and the automation is designed for it.
**Decision:** _open — owner (date: ____, why: ____)._

**(d) Official source to consult first.**
[GitHub — *Releasing and maintaining actions*](https://docs.github.com/en/actions/how-tos/create-and-publish-actions/release-and-maintain-actions)
(moving the `v1` track) and [`../../governance/release-policy.md`](../../governance/release-policy.md)
§3/§3b/§3c.

---

## D8 — `TS_AUTH_KEY` — risk acceptance (do **not** rotate again)

**(a) What it is.** The store's `TS_AUTH_KEY` was **rotated 2026-10-13 (14:10)** and the running
`sae-edge_tunnel` spec now matches the store — but
[`secrets-centralizados.md`](secrets-centralizados.md) carries a **"⚠️ Rotate AGAIN"** because the
new values were **pasted into a chat session** and must be treated as exposed. **The owner decided
not to rotate again.** That decision is an **acceptance of risk** and is not yet written down, so
the doc still says the opposite.

**(b) Options / trade-off.**

| Option | Trade-off |
|---|---|
| **(i)** Rotate **again** (fresh console key → store → redeploy → revoke old) | Clears the exposure, but re-authenticates the edge once more (a brief Funnel interruption window) and the same chat-exposure could repeat. |
| **(ii)** **Accept** the risk; document it | No further interruption, but a possibly-exposed key keeps working until it is revoked/expires. |
| **(iii)** Do the **durable fix** — inject the key as a **Docker secret** (`TS_AUTHKEY_FILE`) so it leaves the service spec and the Swarm Raft log (already proposed, text-only) | Removes the *persistent* leak (spec/Raft/manager snapshots) on the next edge deploy — but it is a compose change to coordinate with the edge owner and does **not** clean the already-rotated value. |

**(c) Candidate recommendation.** Record the acceptance **(ii)** now — update
[`secrets-centralizados.md`](secrets-centralizados.md) from *"Rotate AGAIN"* to *"risk accepted
2026-10-13 by the owner; exposure is chat-only, the key was rotated the same day; revoke if the
exposure scope widens"* — and schedule the durable fix **(iii)** for the next edge deploy.
**Decision:** _open — owner to confirm the wording of the acceptance (date: ____, why: ____)._

**(d) Official source to consult first.**
[Tailscale — Auth keys](https://tailscale.com/kb/1085/auth-keys) (exposure/revocation) and
[Docker — Manage sensitive data with Docker secrets](https://docs.docker.com/engine/swarm/secrets/)
(the `*_FILE` injection pattern).

---

## D9 — `HB-047` re-bind of `kavure`/`ybytu` (defense-in-depth)

> **Referenced, not duplicated:** this is **[HB-047](../backlog.md)**. The firewall half is **done
> 3/3**; the remaining **socket re-bind** is documented in
> [`../network/ports.md`](../network/ports.md) §5 (*"Socket re-bind to the tailnet IP / loopback"*).

**(a) What it is (one line).** The host firewalls are already tailnet-only, so the remaining `0.0.0.0`
binds on **`kavure`** (`9097/9098/9095/443/80/111/9100/18555`) and **`ybytu`**
(`53/3000/8082/8083/9096/111/9100`) are now a **defense-in-depth** matter, not an active exposure.
`kuaray` (8 sockets + rpcbind) and `psicopompo` are already re-bound.

**(b)/(c) Options + recommendation.** Do the re-bind (a second layer) or leave it (the firewall is
the only layer). Candidate recommendation: do it one host at a time, verify from another node, keep
a per-compose backup — as `kuaray` was done. Trade-off and rollout order in the HB-047 row.
**Decision:** _open — owner (tracked by HB-047)._

**(d) Official source to consult first.**
[Docker Compose — `ports` long syntax](https://docs.docker.com/reference/compose-file/services/#ports)
(`host_ip:published:target`) and [Prometheus — Node Exporter `--web.listen-address`](https://github.com/prometheus/node_exporter).

---

## D10 — `HB-013` — reboot `ybytu` to prove persistence

> **Referenced, not duplicated:** this is **[HB-013](../backlog.md)**, detail in
> [`servers/ybytu.md`](../servers/ybytu.md) §*Tailscale DNS health*.

**(a) What it is (one line).** The `ybytu` DNS root cause was fixed 2026-10-13 (AdGuard freed
`127.0.0.53`; the `systemd-resolved` stub returns; `tailscaled` logs `ret=systemd-resolved`). The
item stays open only for the **owner's reboot-persistence confirmation** (the stub symlink + the
enabled unit are persistent config) and archival.

**(b)/(c) Options + trade-off.**

| Option | Trade-off |
|---|---|
| **(i)** Schedule a reboot of `ybytu` and re-check `tailscale status`/DNS after it | The **only** proof the stub + enabled unit survive a real boot; a short dashboard/DNS blip for the fleet (ybytu is edge DNS). |
| **(ii)** Close on the config-is-persistent argument | No blip, but no live proof ("a memory is not evidence"). |

**(c) Candidate recommendation.** (i) in a low-traffic window, then archive HB-013.
**Decision:** _open — owner to pick the window (date: ____, why: ____)._

**(d) Official source to consult first.**
[`systemd-resolved.service(8)`](https://www.freedesktop.org/software/systemd/man/latest/systemd-resolved.service.html)
(the stub listener + `resolvectl` pitfalls) and [Tailscale — *DNS in Tailscale*](https://tailscale.com/kb/1054/dns).

---

## D11 — Members reach each other's devices (the *grande LAN*)

**(a) What it is.** After the phase-3 tighten the only member-to-member path is
`autogroup:member → autogroup:self` (grant 7) — i.e. **each user reaches only their own devices** —
so **the family's devices no longer reach each other** and the Tailscale app hides them (the
*netmap trimming* recorded in [`../network/tailscale.md`](../network/tailscale.md) §*Device
visibility in the mobile app*). The owner decided the family should live in **one big LAN**:
*"quero a gente vivendo em uma grande LAN"*.

**(b) Options / trade-off.**

| Option | Trade-off |
|---|---|
| **(i)** Keep `autogroup:self` only | Strictest least privilege — a compromised member device cannot reach another member's devices — but the family cannot reach each other's devices and the app keeps hiding them: the exact friction the owner rejected. |
| **(ii)** Re-add one flat member↔member grant (`ip: ["*"]`) | The family sees and reaches each other's devices again (the *grande LAN*). Cost: every member device can reach every **other member** device on every port — a lateral path *among user devices* (this does **not** touch the tagged servers; see (c)). |
| **(iii)** Enumerate per-port member↔member paths | Narrower surface, but must be re-derived whenever a device/service changes — the maintenance the catalogue grants already cost. |

**(c) Candidate recommendation / the owner's decision.** **YES — the owner decided (ii).** The
candidate grant is:

```jsonc
{ "src": ["autogroup:member"], "dst": ["autogroup:member"], "ip": ["*"] }
```

**The care.** The **tagged servers stay OUTSIDE it**: a member's path to a service remains the
purpose-scoped `member → tag:server` grants, and each server's **strict regime does not change**
(a tagged node is removed from `autogroup:member`, so it is neither `src` nor `dst` here — see
[`tailnet-tagging.md`](tailnet-tagging.md)). Pinning it in CI is limited: a test `src` **cannot** be
an autogroup, so the member↔member path is verified **live** (two member devices), not by a `tests`
assertion ([`acl-lockout-audit.md`](acl-lockout-audit.md) §5b).

**Implemented 2026-10-13 — [HB-063](../backlog-archive.md).** The grant above landed in `MNEMOCINE-ACL`
**PR [#14](https://github.com/ceduardorodrig/MNEMOCINE-ACL/pull/14)** (one owner per repo): CI
`acls` green, `action: apply` success. The same PR dropped the **dead** `tcp:8766` from grant (1)
(`sae-core_asciline` never existed — [`../network/ports.md`](../network/ports.md) §2.2).

**Evidence (live, rite 8 — verified against the control plane, not the report).** The deployed
policy carries the grant. On the **tagged** `psicopompo` the `netmap` `PacketFilter` is
byte-identical to the pre-change filter **except** the removed `:8766`, and **none** of the 8
member IPs appears as a `dst` there — a tagged node stays **outside** the member↔member rule and
keeps the strict `tag:server ↔ tag:server` regime (grant 5 intact). DNS is untouched (`getent hosts
doubleclick.net` still filtered; MagicDNS resolves), the catalogue / Funnel / SSH paths are
unchanged, and the CI guard's `tests` still pass (`POST …/acl/validate` → `{}`). Reversal = delete
the grant. See [`acl-lockout-audit.md`](acl-lockout-audit.md) §4.1/§10.
**Decision:** _decided & implemented — owner, 2026-10-13: *"quero a gente vivendo em uma grande LAN"*._

**(d) Official source to consult first.**
[Tailscale — *What devices can connect to or know mine?*](https://tailscale.com/docs/concepts/device-visibility)
(why the mobile app trims the netmap) and
[Tailscale policy syntax](https://tailscale.com/kb/1337/policy-syntax) (`autogroup:member` as **both**
`src` and `dst`; the `ip:` field).

---

## References

- [`../backlog.md`](../backlog.md) — the mother row **HB-061** and the siblings HB-059 / HB-060 / HB-047 / HB-013; **HB-063** (D11) is closed in [`../backlog-archive.md`](../backlog-archive.md)
- [`acl-lockout-audit.md`](acl-lockout-audit.md) — §6 the owner decisions the tighten left open (D1–D3)
- [`ufw-lan-runbook.md`](ufw-lan-runbook.md) — §3.1 LAN exceptions, §3.2 container→LAN (D4)
- [`secrets-centralizados.md`](secrets-centralizados.md) — the `TS_AUTH_KEY` finding (D8)
- [`stenio-ci-unificado.md`](stenio-ci-unificado.md) · [`../../governance/release-policy.md`](../../governance/release-policy.md) — the engine release track (D7)
- [`../network/ports.md`](../network/ports.md) — §5 the re-bind changelog (D9)
- [`homelab-traps-2026-10.md`](homelab-traps-2026-10.md) — the day's field notes, incl. "confirm the CI `apply`" and the `allow-all`-hid-nine lesson

---

## D12 — ComfyUI: uso interativo fora das janelas (**decidido 2026-10-14**)

**Pergunta.** O `hl-infer` admite classes *batch* (`Triage`, `Create`, `ImageGen`) apenas dentro das
janelas fixas (06–07, 12–13, 18–19, 00–01); as *interativas* (`Transcribe`, `Other`) são servidas
sempre que a VRAM **medida** permitir. Um humano pode gerar imagem no ComfyUI **fora** dessas janelas?

**Decisão:** sim, via lease **`other`** — admitida sempre que a VRAM medida caiba.

**Por quê (a razão, não o palpite):** o que protege a GPU não é a janela, é o **livro de VRAM**: o
gateway só admite um job quando a sobra medida cabe, e ADR-020 já proíbe fallback de CPU. A janela
batch existepara o trabalho *em lote* do autopilot, não para dono da GPU ser uma agenda fixa. ComfyUI
é ferramenta **de pessoa** antes de ser etapa de pipeline — travar um humano às 22h para preservar
uma agenda que o livro de VRAM já garante seria trocar uma proteção real por uma burocrática.

**Custo aceito (conscientemente):** um lease humano pode **atrasar** os jobs `image_gen` do autopilot,
porque `other` tem a prioridade mais baixa (4) — mas ainda é admitido quando a VRAM cabe.

**Verificação ao vivo (2026-10-14, 11:16, fora de toda janela):**
`kind: other`, `required_bytes: 6 GiB`, `process: "python"` → estado **`admitted`** (`job-000001`);
liberado na sequência; o livro voltou a `{"unmanaged":0,"leases":[]}` (o processo do ComfyUI de volta
a 88 MB ocioso). Detalhe e receita em [`../services/comfyui.md`](../services/comfyui.md).

---

## D13 — The autopilot runs on kavure; Ollama is exposed through a kernel forwarder (**2026-10-19**)

**Decision.** The social-media engine's four timers move to **kavure** (always on). `psicopompo`
stays the **development/build host** and the only **GPU** host — `hl-infer`, `ollama` and `comfyui`
do not move. Ollama remains bound to `127.0.0.1:11434`; a `systemd-socket-proxyd` forwarder binds
the Tailscale IP so the engine on kavure keeps the local fallback.

**Why.** A workstation is not a scheduler: a reboot, a suspend or a kernel update at the wrong
minute loses a publication window, and `Persistent=false` deliberately never replays it (a burst
would land outside the window and look like a bot). The engine is CPU-only in its normal path, so
kavure does not need a GPU. The local fallback matters more than it looks: **Gemini is at HTTP 402**
(depleted prepayment), so the only working providers are `opencode` (free model, no auth needed) and
Ollama.

**Why a kernel forwarder and not `tailscale serve`.** `tailscale serve` runs inside tailscaled and
was verified to **bypass UFW** (the Syncthing 8384 listener answers from another host with no rule
and `Default: deny`). A kernel socket bound to the Tailscale IP is filtered normally. It also keeps
the `0.0.0.0` prohibition in [`../network/ports.md`](../network/ports.md) §1.

**The boundary, by design (owner decision 2026-10-19).** Tailscale inserts
`-A INPUT -j ts-input` as rule #1 and `ts-input` accepts everything arriving on `tailscale0`, so
**UFW is not the filter for tailnet traffic** — the ACL is. The owner confirmed this is the intended
model: the tailnet is a trusted mesh (members join only by authorization, and every tagged server is
one the owner runs), so grant (5) `tag:server → tag:server: *` stays exactly as it is. Ollama is
reachable by **tagged servers**, not by family devices (grant (1)'s port list does not include
`:11434`). What was wrong was the documentation claiming UFW scoped the tailnet; `ports.md` now says
otherwise. UFW remains defense-in-depth.

---

## D14 — Engine vs tenant: identity and credentials are deployment data (**2026-10-21**)

**Decision.** The autopilot repository is the **engine**. A **tenant** owns the persona packs, the
account identities, the engagement policy and the state. A pack declares the identity
(`channel.handle`) and the **names** of the environment variables that hold the secrets
(`app_password_env` for Bluesky, `x_env` for X); the engine never stores a handle or a secret. The
scheduler runs from `AUTOPILOT_TENANT_DIR`; the engine lives in `AUTOPILOT_DIR`.

**Why.** The old layout was one account per process (`BLUESKY_HANDLE` / `X_*` globals) and the
identity lived in **two** places: `channel.handle` fed the card/quality gate while `BLUESKY_HANDLE`
drove the login. That cannot serve several personas with different accounts, let alone customers.
With the identity in the pack and secrets named, one binary serves many tenants; the publisher
rejects a session for another account (`create_session_for_channel`), so a misconfigured deployment
fails loudly instead of posting from the wrong account. The tenant layout is documented in
[`services/autopilot.md`](../services/autopilot.md) and in the engine's `docs/tenancy.md`.

**Consequences.** The public engine ships `examples/` only; the real pack, the engage config and
`var/` stay in `/home/kavure/autopilot/tenants/sumaenima/` (and its NAS mirror). The public release
sanitized the history (the pack was tracked) and carries the **AGPL-3.0-only** license plus a
commercial option. The persona pack is the sellable unit; the engine is the delivery vehicle.

**Pre-existing exposure (resolved 2026-10-21).** The production handle appeared in the public
`MNEMOCINE` `backlog-archive.md` (HB-073). The autopilot public repository does not include it, and
the `MNEMOCINE` history was sanitized on 2026-10-21 (`git filter-repo`; pre-rewrite bundle
`/mnt/BACKUP/mnemocine-pre-sanitize-2026-10-21.bundle`). Old commits may remain reachable by SHA
until GitHub's garbage collection; the repository has no forks.

---

## D15 — `SEC-SUDO` on `security/audit-access-fleet.sh` (**decided 2026-10-30**)

**Decision.** Keep `sudo -n` in `security/audit-access-fleet.sh` as a **reviewed privilege point**
(owner: option C). The script keeps reading `/root/.ssh/authorized_keys` and the root crontab on the
five hosts. The `SEC-SUDO` warning stays in `stenio --scope vault` as a known, tracked finding. No
host configuration changes, and the Stênio rule and its regex are not touched.

**Why.** The privilege already exists: `psicopompo` lets `edu` run any command as root, and
`kuaray`, `kavure`, `ybytu` and `ybyra` let their host users do the same without a password, so
`sudo -n` works today. Narrowing that `ALL` to two commands was rejected because the operator runbooks depend on root
(Docker cleanup, UFW, snapshots, `config-backup`), and enumerating every root command is fragile. A
dedicated system account for the audit was rejected by the owner. The engine (`governance/stenio/`)
is immutable for application work, so the rule cannot be narrowed to clear the warning. Any attempt
to hide the call under another command name would be a detection bypass, so it is not an option.

**Consequences.** The warning is expected in every vault run until the audit moves to a model that
does not need root. Revisit this decision if the fleet adopts a dedicated automation identity or if a
host's `NOPASSWD` grant is narrowed for another reason.

**Reversal.** Cheap: replace `sudo -n` with a scoped sudoers rule for `cat /root/.ssh/authorized_keys`
and `crontab -l` on each host (with `visudo -c` and a backup first), then record the new decision here.

---

## D16 — kuaray becomes exclusive to a client stack (**decided 2026-10-30**)

**Decision (owner).** `kuaray` hosts only the client project's stack. Every service that belongs to the
homelab tailnet moves to another host, one at a time, each move with its own backup and rollback;
`kuaray` leaves the homelab tailnet last. The ~16 GB media stack leaves kuaray (target host still to be
chosen: `kavure` with a download quota, or `psicopompo`/NAS). The 313 GB cold NAS mirror does **not**
stay on the client host: backups remain on the NAS and `psicopompo`, and the Syncthing `backup` folder on
kuaray is retired as part of the move, freeing the 916 GB disk.

**Why.** The client project must not depend on the homelab tailnet (a personal, non-commercial plan) and
must be able to move to its own server later. Mixing the two on one host is what made the migration
risky: consumers are hard-coded to the host's tailnet address and the host's disk holds homelab data.

**Where the rest lives.** The client's own network, identity, DNS and licensing decisions are recorded
in the client's private repository, not here: this folder is published publicly every day (HB-089).

**Reversal.** Per phase; see the rollbacks in [`../network/kuaray-decoupling-plan.md`](../network/kuaray-decoupling-plan.md).
