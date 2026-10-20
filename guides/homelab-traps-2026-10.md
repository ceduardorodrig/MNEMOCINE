---
tags: [homelab, network, tailscale, dns, docker, tutorial]
pending: [HB-071]
---

# Homelab Traps — Field Notes from 2026-10-13

> **Why this note exists.** On 2026-10-13 the tailnet was moved from allow-all to a tagged,
> least-privilege policy and the host firewalls were turned on. The day produced **eleven** traps that
> cost real time — several of them **twice** — and the owner's instruction was explicit: *document
> them so we stop asking the same questions and repeating the same mistakes.*
>
> **Scope.** This is a **cross-cutting lessons file**, not a runbook. Each trap states **what
> happened**, the **evidence** (the exact command and its output, or the official-doc line), and
> the **rule** to apply next time. The deep-dives stay in their own documents — this note links to
> them instead of restating them:
> [`tailnet-tagging.md`](tailnet-tagging.md) · [`tailnet-acl-runbook.md`](tailnet-acl-runbook.md) ·
> [`ufw-lan-runbook.md`](ufw-lan-runbook.md) · [`../network/tailscale.md`](../network/tailscale.md) ·
> [`../network/dns.md`](../network/dns.md) · [`../network/ports.md`](../network/ports.md).

---

## 1. Tagging a device **removes its user identity** — and four things follow

**What happened.** Applying `tag:server` (and role tags) to the fleet was treated as a label change.
It is not: a tagged device **has no user identity** — it is a service account. Four consequences
followed, and each one was learned the hard way on the same day.

| # | Consequence | Evidence |
|---|---|---|
| (a) | The device **stops matching `autogroup:self`** | Official: *"`autogroup:self` … Does not apply to tags."* ([policy syntax](https://tailscale.com/kb/1337/policy-syntax)). The `ssh` rule `src: autogroup:member → dst: autogroup:self` therefore no longer covers the server. |
| (b) | A tagged node **connects out as its tag**, not as a user | Official: *"From a tagged device to another tagged device (for any tags)"* and *"Devices with a tag-based identity can only SSH into other tagged devices."* ([tags](https://tailscale.com/kb/1068/tags)). `psicopompo` is itself `tag:server`, so its outgoing `src` is `tag:server` — the admin rule `src: autogroup:admin` **cannot match it**. |
| (c) | **Key expiry is only disabled by re-authentication**, not by tagging | Official: *"If you change the tags … the device's key expiry will not change unless you re-authenticate."* Verified live: all seven tagged devices report expiry **disabled**. |
| (d) | It is **practically irreversible** | Official: *"You cannot remove all tags from a device. A device with a tag-based identity must have at least one tag."* The API/console refuse an empty tag list — the only way back is re-authentication with an untagged key. |

**Evidence (c) — key expiry, live on `psicopompo`, 2026-10-13:**

```bash
tailscale status --json | jq -r '.Peer[] | "\(.HostName)\ttags=\(.Tags // "none")\texpiry=\(.KeyExpiry // "disabled")"'
# ybyra      tags=["tag:edge","tag:server"]                       expiry=disabled
# Kuaray     tags=["tag:server"]                                  expiry=disabled
# sumaenima  tags=["tag:edge"]                                    expiry=disabled
# ybytu-vnic tags=["tag:exit-node","tag:server"]                  expiry=disabled
# kavure     tags=["tag:edge","tag:exit-node","tag:monitoring","tag:server","tag:subnet-router"] expiry=disabled
# miracena   tags=["tag:edge"]                                    expiry=disabled
# (self)     tags=["tag:registry","tag:server"]                   expiry=disabled
```

**Rule.** Tagging is a **one-way identity change**, not a label. Before you tag: (1) land the
tag-based `ssh` rule **first** (consequence a); (2) add the `tag:server → tag:server` rule, because
servers administering servers is a real trust zone (consequence b); (3) after tagging, **verify
key expiry is off** (consequence c); (4) treat the tag as permanent (consequence d). Full procedure:
[`tailnet-tagging.md`](tailnet-tagging.md) §3/§4/§6.

---

## 2. Tagging can **silently drop an `app`-capability grant** — the peer relay

**What happened.** After the fleet was tagged, `ybyra` (and the whole tagged fleet) lost the
**peer relay** and fell back to public **DERP**. Nothing failed loudly: the grant
(`tailscale.com/cap/relay`) still said `src: ["autogroup:member"]`, and tagging had just removed
the infra devices from `autogroup:member` (trap 1).

**Evidence.**

```bash
tailscale status | grep -E 'ybyra|peer-relay'
# before fix: ybyra … active; relay "sao"          (DERP — the relay grant no longer matched)
# after fix:  ybyra … active; peer-relay 64.181.168.251:40000:vni:1219   (64.181.168.251 = ybytu)
tailscale ping ybyra     # → via peer-relay(64.181.168.251:40000:vni:1219)
```

**Fix.** `src: ["autogroup:member", "autogroup:tagged"]` — `autogroup:tagged` is the documented
complement of `autogroup:member`. PR
[#10](https://github.com/ceduardorodrig/MNEMOCINE-ACL/pull/10); detail in
[`../network/tailscale.md`](../network/tailscale.md) → *Peer Relays*.

**Rule.** When you tag a device, re-check **every** grant it depends on whose `src` is
`autogroup:member`. An `app`-capability is delivered as a `PacketFilter` **`Caps`** entry, not as an
`ip:port` rule — so it fails **silently** and is **not** covered by `tests` (trap 3).

---

## 3. `tests` only pin **network `ip:port`** — app-capabilities and some `deny` pins are not testable

**What happened.** Two different test surprises:

1. The relay (trap 2) **cannot be pinned** by a `tests` assertion. Official: `tests` *"make
   assertions about access policies (ACLs and **network-level** grants)"*
   ([policy syntax](https://tailscale.com/kb/1337/policy-syntax)). The relay has no `ip`, so it is
   verified **live** only.
2. A `deny` pin for a **member** against `autogroup:internet` reported **`want Drop, got Accept`**
   — correctly, because the member *is* granted the exit node by design. A `deny` pin only makes
   sense against `autogroup:shared` (who must never get the exit node). And a test **`src` cannot be
   an autogroup** (`unknown user or host`) — use a concrete member e-mail or a group.

**Evidence.** The CI `action: test` is the gate for the network rules; the relay was checked with
the live `tailscale status` above. The parser rejections (`autogroup` as `src`, CIDR as `dst`,
comma-lists in one `ip` entry) are recorded in [`tailnet-acl-runbook.md`](tailnet-acl-runbook.md) §4.

**Rule.** `tests` are for **network reachability**; write them with a **concrete** source. Anything
**application-level** (the peer relay, Funnel attributes) and every `deny` that contradicts a
deliberate grant is verified **live** — do not mistake "CI green" for "the capability works".

---

## 4. Confirm the CI **`apply` finished** before you test

**What happened.** A test was run against a policy whose `action: apply` had **not** completed, and
the conclusion "the rule does not work" was drawn — wrongly. The rule was correct and live all
along. `gh run list --limit 1` had returned the **previous** run.

**Rule.** Before testing a GitOps-deployed policy, confirm the run for **your** commit is
`completed success`. Testing a not-yet-deployed policy produces a false failure and invites panic
(here: a needless re-auth). This is the operational lesson in
[`tailnet-acl-runbook.md`](tailnet-acl-runbook.md) §5 and [`tailnet-tagging.md`](tailnet-tagging.md) Trap 3.

---

## 5. Test DNS **the way the apps test it** — not with `resolvectl`

**What happened.** `resolvectl query` consults `systemd-resolved` **directly**, which on `ybytu`
uses its own global upstreams (`9.9.9.9`/`1.1.1.1`) and **bypasses the AdGuard filter**. It looked
like `ybytu` was "leaking" unfiltered answers. It was not — `resolvectl` is simply the wrong probe.
Applications go through the **libc** → `/etc/resolv.conf` → `100.100.100.100` (MagicDNS → the
filtering resolvers). This was the **second** time the same mistake caused a wrong conclusion.

**Evidence (on `ybytu`, 2026-10-13):**

```bash
getent hosts doubleclick.net     # ::                        (AdGuard null-route — blocked)
curl -sS https://doubleclick.net # Failed to connect         (blocked, as intended)
resolvectl query doubleclick.net # 2800:3f0:4001:80b::200e   (FALSE NEGATIVE — resolved via Quad9)
```

**Rule.** Verify filtering with the **libc path**: `getent hosts`, `curl`, or a Python/`socket`
lookup — never `resolvectl query` (and `dig @…` only against the specific resolver you mean).
See [`../network/dns.md`](../network/dns.md).

---

## 6. In a systemd drop-in, `DNS=` **appends** — reset it with an empty `DNS=` first

**What happened.** The OCI cloud-init wrote `DNS=9.9.9.9#dns.quad9.net 1.1.1.1#cloudflare-dns.com`
into `/etc/systemd/resolved.conf`. A drop-in adding `DNS=127.0.0.1` did **not** replace it: `DNS=`
is a **list** option, and list entries are **collected** across files. The drop-in value landed
**third**, and Quad9 won the race.

**Evidence.**

```bash
# official (resolved.conf(5)): "for options which accept a list of values,
# entries are collected as they occur in the sorted files."
systemd-analyze cat-config systemd/resolved.conf | rg '^DNS='
# base  /etc/systemd/resolved.conf : DNS=9.9.9.9#dns.quad9.net 1.1.1.1#cloudflare-dns.com
# drop-in                          : DNS=127.0.0.1          ← appended, not replaced
```

The evolution is preserved in the disabled drop-ins on `ybytu`:
`adguardhome.conf.bak-2026-10-13` = `DNS=127.0.0.1` (appends — ineffective) →
`…bak2` = adds an **empty `DNS=`** reset before `DNS=127.0.0.1` (replaces) →
`…bak3` = `DNS=` + `DNS=100.100.100.100` + `DNS=127.0.0.1` + `Domains=~.`.

**Rule.** To **replace** a list in a drop-in, put an **empty assignment first**
(`DNS=` on its own line), then the values. Without it you are only appending.

---

## 7. The `127.0.1.1 <hostname>` trap in `/etc/hosts`

**What happened.** Debian's convention `127.0.1.1 <hostname>` makes a host resolve **its own name**
to `127.0.1.1` — a loopback **different** from the `127.0.0.1` where a service listens. The classic
symptom: *"it opens on the phone, but not on the host."* The **FQDN** (`host.tailnet.ts.net`) goes
through MagicDNS and escapes it.

**Evidence (on `psicopompo`, 2026-10-13):**

```bash
getent hosts Psicopompo                          # 127.0.1.1   Psicopompo      ← /etc/hosts
getent hosts psicopompo.chimaera-heptatonic.ts.net # 100.82.51.112 …          ← MagicDNS (FQDN)
curl -sS http://Psicopompo:8384/                 # Failed to connect (127.0.1.1 — nothing listens)
curl -sS http://localhost:8384/                  # 200            (127.0.0.1 — the real listener)
```

`/etc/hosts` on `ybytu` carries `127.0.1.1 ybytu-vnic ybytu-vnic`; on `psicopompo`,
`127.0.1.1 Psicopompo`.

**Rule.** When a service answers on the tailnet but not "locally", check `/etc/hosts` **before**
debugging the service. Test with the **FQDN**, `localhost`, or the bind IP — never the bare
hostname.

---

## 8. Host firewall + containers: intra-host traffic hits **`INPUT` via the Docker bridge**, not `tailscale0`

**What happened.** After `kuaray` got a default-deny UFW (`allow in on tailscale0` only), a
**container on the host** could no longer reach **its own host's tailnet IP**. The packet is
local-delivery, so it traverses the **`INPUT`** chain arriving on the **Docker bridge** (`docker0`,
`br-…`) — **not** on `tailscale0` — so `allow in on tailscale0` never matches and the default deny
drops it. The `*arr` stack calls sibling services through the host's tailnet IP
(`100.94.209.99`), so those calls began to time out.

**Evidence (on `kuaray`, 2026-10-13):**

```bash
# from the host itself / another node (src on tailscale0):
curl -sS http://100.94.209.99:61208/            # 200  (tailnet path OK)
# from inside a container (src 172.17.0.11, arrives on docker0):
docker exec prowlarr curl -sS --max-time 4 http://100.94.209.99:61208/
# curl: (28) Connection timed out …            (INPUT default-deny — no rule for the Docker subnet)
iptables -S INPUT | head -1                      # -P INPUT DROP
```

**Rule.** A host firewall must account for the **Docker subnets on `INPUT`**, or containers lose
their own host. The proper fix is a firewall/design decision (allow the Docker bridge on `INPUT`,
or stop the services from hairpinning through the host's tailnet IP). **This pattern is tracked
under [HB-047](../backlog.md)** and recorded in [`../network/ports.md`](../network/ports.md) §5
(*"⚠️ Regression found while verifying"*); the remediation is in flight and **not** repeated here.

---

## 9. Method — doc first, one logic, no divergent topology

**The rule the owner set, and it held.** For every change:

1. **Read the official documentation first** — find the **single underlying logic** (e.g. "a device
   has a user identity *or* a tag, never both") and let it explain the whole class of symptoms,
   instead of patching symptoms one by one.
2. **Implement the fix from the doc**, not from trial and error.
3. **Never leave a host with a divergent topology.** The near-miss of the day: `ybytu` almost kept
   `DNS=127.0.0.1` + `Domains=~.` — a resolved config **no other host has**. It was reverted; the
   drop-in survives only as a disabled `.bak`. A fleet works because its hosts are the **same**;
   a single divergent host is a future outage with a delayed fuse.

**Evidence.** `ybytu` now runs the **fleet-standard** base config, with the divergent drop-ins
disabled:

```bash
systemd-analyze cat-config systemd/resolved.conf | rg '^DNS='
# DNS=9.9.9.9#dns.quad9.net 1.1.1.1#cloudflare-dns.com
ls /etc/systemd/resolved.conf.d/    # only *.bak-2026-10-13 (disabled) — no active drop-in
```

> The deeper root cause of `ybytu`'s DNS mode was AdGuard binding `0.0.0.0:53`, which forced
> Tailscale's **`direct`** mode and the `resolvconf` shim error. **Fixed 2026-10-13:** AdGuard now
> publishes on the **tailnet IP + loopback** only, freeing `127.0.0.53`, so `ybytu` runs the
> fleet-standard **`systemd-resolved`** mode like the other hosts. Detail:
> [`../servers/ybytu.md`](../servers/ybytu.md) → *Tailscale DNS health (HB-013)*.

---

## 10. Green locally ≠ green **at the commit** — the WIP tree is not the commit

**What happened.** The governance engine (`governance/stenio`) was pushed to `main` and tagged
**`v4.6.0`** on a release commit whose `src/health.rs` (HB-054) called into symbols that lived
**only in the uncommitted working tree** of `src/ports.rs` (HB-048/HB-052). In the author's tree it
built — the WIP `ports.rs` was right there. The **commit alone** did not: `main`'s CI
(run `38446447947`) and the `v4.6.0` release both went red with `E0432`/`E0425`
(`PortExceptions`, `is_unauthorized_wildcard_bind`, `load_port_exceptions`) and `E0560`
(`PortEntry.defect`). No consumer was ever served the broken binary, because the **`@v1` action
track stayed on `v4.5.0`** — only the false `v4.6.0` tag was published.

**Evidence.**

```bash
# the COMMITTED health.rs depends on ports.rs symbols…
git show HEAD:src/health.rs | rg -c 'PortExceptions|is_unauthorized_wildcard_bind|load_port_exceptions'
# …that the COMMITTED ports.rs never defines (count = 0):
git show HEAD:src/ports.rs  | rg -c 'PortExceptions|is_unauthorized_wildcard_bind'   # 0
```

**Rule.** A build that succeeds in a tree still holding uncommitted work proves **nothing** about
the commit. Before pushing — and **always** before tagging a release — build from a **clean
checkout of the exact commit**, never the working tree:

```bash
git worktree add --detach /tmp/stenio-clean <ref>   # or: git archive <ref> | tar -x -C /tmp/stenio-clean
( cd /tmp/stenio-clean && cargo build && cargo test --all )
```

The lesson generalises: whenever WIP and `HEAD` coexist, **stage the dependency together with the
code that needs it** — otherwise the commit is a lie, and only the CI will tell you. Remediation:
the dependency was re-landed alone (`ee06e4f`) and `v4.6.0` re-cut on the green commit, which moved
the `@v1` track forward. The release pipeline this trap exercises is documented in
[`stenio-ci-unificado.md`](stenio-ci-unificado.md).

---

## 11. A **zombie DNAT rule** steals a host port that a host-networked container is listening on

**The trap (hit on `ybytu`, 2026-10-13 — the dashboard became unreachable).** `homepage` runs with
`network_mode: host` and `PORT=3001`, so it binds `*:3001` on the host. Yet `curl` from the tailnet
returned **"No route to host"** while `curl http://127.0.0.1:3001` **worked**. The `INPUT` chain and
the tailnet ACL were both fine — the culprit lived in the **`nat`** table:

```
-A PREROUTING -m addrtype --dst-type LOCAL -j DOCKER
-A DOCKER ! -i br-cefe9eb6b060 -p tcp --dport 3001 -j DNAT --to-destination 172.21.0.2:3000
```

A leftover rule from the **old bridge configuration** (`ports: 3001:3000`, before the 07/10 switch to
host networking) — and its container is **gone**, so `172.21.0.2` no longer exists. Because
`PREROUTING` rewrites the destination **before** the local listener is reached, every packet aimed at
`100.115.253.109:3001` was redirected to a **dead container IP**. Docker's `OUTPUT` jump excludes
`127.0.0.0/8`, which is precisely why **loopback still worked** and made it look like a firewall
problem. The same host had a second zombie on `:8083` (`→ 172.17.0.9:80`, also dead) that broke
`ntfy` identically.

**The tell:** a port that answers on `127.0.0.1` but refuses every other address on the same host —
`ip route`/`ss` clean, `ts-input` accepting. Suspect `iptables -t nat` before anything else.

**The rule:**
1. Diagnose with `iptables -t nat -S DOCKER` and check **each DNAT target against the live
   containers** (`docker inspect` → `NetworkSettings.Networks[].IPAddress`) — a target with no
   container is a zombie.
2. Fix **surgically** (`iptables -t nat -D DOCKER <rule>`) with `iptables-save` taken first —
   a `docker` restart also purges them, but it bounces every container on the host.
3. **After** changing a container from bridge (`ports:`) to `network_mode: host`, **re-check the nat
   table** — Docker does not always clean the rules up while it keeps running.
- **Root cause — and why the first audit missed it.** These rules are the residue of containers being
  **removed or re-created** while Docker did not clean `nat/DOCKER` — typically when a container's
  `ports:`/network changed while running (`ybytu`'s Homepage moving bridge → `host` on 07/10) or when
  a **network is recreated and Docker hands the freed IP to a different container**. Because IPs are
  dynamic, a stale rule's target can end up belonging to an **unrelated** container: on `ybytu` the
  dead rules pointed at `172.17.0.2`, which by then was **`autoheal`** — so they looked "alive" to a
  naive audit and silently stole the port from AdGuard, ChangeDetection and DNS.
  **The audit must therefore check the target against the container that actually *publishes* that
  host port**, not merely whether the IP exists. Verdict after the rigorous re-audit (2026-10-13,
  every Docker host): **0 ORFA, 0 DESVIO, 0 ZUMBI** — 8 + 18 + 23 + 0 + 3 DNAT rules, all matching
  their publisher.
- **A first diagnosis in this note was WRONG and is corrected here.** The `ybytu` `:3000`/`:8082`/`:3002`
  failure was first attributed to the `FORWARD` chain dropping DNAT'd traffic, and a
  `DOCKER-USER -i tailscale0 -j ACCEPT` rule was added to test that. It did **not** help, and the real
  cause was the **wrong-target DNATs** above; the traffic never even needed to be forwarded, because
  the publishes are also served by local `docker-proxy` listeners. The extra rule was **removed**
  (verified: everything still answers), so the host is back to its minimal state. `DOCKER-USER` stays
  the right place for a *legitimate* forward rule (Docker's documented, non-overwritten chain, and what
  `kuaray`/`kavure` get from `ufw allow in on tailscale0`) — but a rule there is only needed when a
  container is genuinely reached by its **bridge IP**.
- Verified fleet-wide (2026-10-13 — two audits run on every Docker host, `psicopompo`, `kuaray`,
  `kavure`, `ybytu`, `ybyra`): **10 wrong or dead DNAT rules removed in total** (`ybytu` 5 on the
  first pass + 5 more, `psicopompo` 3, `ybyra` 2), **0 remaining**.
- **Services recovered:** `ybytu:3000` (AdGuard UI, `302`), **`ybytu:8082` (ChangeDetection, `200` — the
  title proves the right service)**, `ybytu:3002` (`302`), **`ybytu:53` DNS (resolving *and* filtering:
  `doubleclick.net → 0.0.0.0`)**, `ybytu:3001` (Homepage), `ybytu:8083` (Ntfy), `psicopompo:9090`
  (StênioREC) and `ybyra:80` (public edge) — all **200/302**, with the two public **Funnels still 200**.
- **Safe and self-healing:** removing a rule whose container no longer exists is harmless — if a
  container with that published port ever starts again, Docker re-creates the rule from its config.
- **Recurrence incident (2026-10-19 — Homepage & Uptime Kuma):** On 2026-10-15, while configuring
  Syncthing (`22000`) on `ybytu`, `netfilter-persistent save` was invoked without auditing `nat/DOCKER`.
  This dumped the host's raw iptables state into `/etc/iptables/rules.v4` containing stale DNAT rules for
  `:3001` (`→ 172.21.0.2:3000`) and `:3002` (`→ 172.17.0.5:3001`). On the subsequent network/service
  reload, `netfilter-persistent` resurrected the zombie rules, breaking Tailnet access (`No route to host`)
  even though the containers ran healthy in `network_mode: host`.
- **How to prevent recurrence definitively:**
  1. **Audit before saving:** Never invoke `netfilter-persistent save` blindly. Always run
     `sudo iptables -t nat -S DOCKER` first and ensure no rules target deleted containers or host-networked ports.
  2. **Host-mode migration check:** Whenever changing any service from bridge (`ports:`) to `network_mode: host`,
     immediately verify that Docker cleaned its DNAT rule. If residual rules exist, delete them:
     `sudo iptables -t nat -D DOCKER <rule>`.
  3. **Persist only clean state:** Immediately after surgical removal, update the persistent storage:
     `sudo cp /etc/iptables/rules.v4 /etc/iptables/rules.v4.bak && sudo netfilter-persistent save`.
  4. **Fleet re-audit (2026-10-19):** After purging `ybytu`, all nodes (`psicopompo`, `kavure`, `kuaray`,
     `ybyra`) were scanned live — **0 zombie rules across all active nodes**. Tracking automation via **[HB-071](../backlog.md)**.


---

## Quick reference — the eleven, one line each

| # | Trap | Rule |
|---|---|---|
| 1 | Tagging removes the user identity | One-way; land the tag-based `ssh` rules (incl. server→server) **before** tagging; verify key expiry. |
| 2 | Tagging silently drops an `app`-capability (relay) | Re-check every `autogroup:member` `src` grant; fix with `+ autogroup:tagged`. |
| 3 | `tests` only pin network `ip:port` | App-capabilities and contradictory `deny` pins are verified **live**; test `src` must be concrete. |
| 4 | Testing before the CI `apply` finished | Confirm **your** commit's run is `completed success` first. |
| 5 | `resolvectl` is not how apps resolve | Test with `getent hosts` / `curl` (the libc path). |
| 6 | Drop-in `DNS=` appends | Reset with an empty `DNS=` before the values. |
| 7 | `127.0.1.1 <hostname>` in `/etc/hosts` | Use the FQDN / `localhost` / bind IP, never the bare hostname. |
| 8 | Container → own host tailnet IP blocked by `INPUT` | The packet arrives on the Docker bridge; the firewall must allow it. |
| 9 | Method | Doc first → one logic → fix from the doc → no divergent host. |
| 10 | Green locally ≠ green at the commit | Build the **clean commit** (`git worktree`/`git archive`), not the WIP tree, before pushing or tagging. |

## 12. A `ufw` rule on `tailscale0` restricts **nothing** — the ACL is the tailnet firewall

**The trap (hit on `psicopompo`, 2026-10-19 — exposing Ollama to the autopilot on kavure).** The
obvious move was `ufw allow in on tailscale0 from 100.124.146.77 to any port 11434`, then test from
kavure: `200`. Test from a **third** tagged server (`kuaray`): also `200`, even though the rule named
a single source IP.

**Why:** Tailscale installs `-A INPUT -j ts-input` as **rule #1**, and `ts-input` contains
`-A ts-input -i tailscale0 -j ACCEPT`. Every tailnet packet is accepted **before** UFW's chains run.
It is intentional (the maintainers call the ACL *the tailnet firewall*). `tailscale serve` has the
same property — the Syncthing `:8384` listener answers from another host with `Default: deny` and
**no** rule at all. This is the Layer-1 fact already stated in
[`security-baseline.md`](security-baseline.md).

**The tell:** a tailnet port answers from a host the UFW rule did **not** name. Check
`iptables -S | rg ts-input` and `iptables -L ts-input` before touching the firewall.

**The rule:**
1. To restrict a tailnet port, edit the **ACL** (`grants`) — not UFW, not nftables.
2. Keep the UFW rule only as **defense-in-depth**, and label it as such; never present it as the
   control.
3. Test from a **third** tagged server, not just the intended client: the client proves reachability,
   the third proves the restriction.
4. Docker-published ports are a separate layer (`DOCKER-USER`); do not mix the two.

## References

- [`tailnet-tagging.md`](tailnet-tagging.md) — the applied tag map, the tag traps, and the runbook to tag a device
- [`tailnet-acl-runbook.md`](tailnet-acl-runbook.md) — the phased least-privilege procedure and the `tests` caveats
- [`ufw-lan-runbook.md`](ufw-lan-runbook.md) — the host-firewall block, rollout order and chain-order hazard
- [`../network/tailscale.md`](../network/tailscale.md) — tailnet inventory, tags, peer relays, Funnels
- [`../network/dns.md`](../network/dns.md) — the DNS chain and the parallel resolver race
- [`../network/ports.md`](../network/ports.md) — the port matrix and §5 (the `INPUT`/Docker regression)
- [`../servers/ybytu.md`](../servers/ybytu.md) — `ybytu` `direct` DNS mode and the `resolvconf` shim (HB-013)
- Tailscale tags: <https://tailscale.com/kb/1068/tags> · policy syntax (incl. SSH + `tests`): <https://tailscale.com/kb/1337/policy-syntax>
- `resolved.conf(5)`: <https://man.archlinux.org/man/resolved.conf.5.en>
