---
tags: [homelab, network, dns, tailscale]
---

# DNS Consistency Map — the whole fleet

Read-only audit of how **every** Mnemocine host resolves DNS, measured **2026-10-13**.
Purpose: verify the owner's pillar — *"we cannot run a different network topology on each
host; they must share one unified logic"* — against the canonical design in
[`../network/dns.md`](../network/dns.md), [`../network/tailscale.md`](../network/tailscale.md),
[`../services/unbound.md`](../services/unbound.md),
[`../services/adguard-home.md`](../services/adguard-home.md) and
[`../services/pihole.md`](../services/pihole.md).

> **Status: IMPLEMENTED & VERIFIED (2026-10-13).** The owner approved the unified logic and it was
> applied: `ybytu` (the divergent host) now runs the stub topology, and `ybyra` received the
> missing global fallback. All **five reachable hosts** were re-measured and now converge — see
> **§4.1** for the per-host before→after and the five-test evidence. `kururu` remains **unmapped**
> (it answers `tailscale ping` but exposes no administrative path from the audit session — see
> **§4.2**). Pending work stays in the single source [`../backlog.md`](../backlog.md) (`HB-013`
> carries the `ybytu` traceability); this map does **not** open a side queue.

> **Invariant (2026-10-13) — this is an invariant, not a preference.** Whatever changes, every
> tailnet device MUST keep resolving through the tailnet's own resolvers (`100.100.100.100`
> MagicDNS → Pi-hole on `kavure` + AdGuard on `ybytu`, racing in parallel, both forwarding to the
> local `unbound` with DNSSEC). A change that could cut that path — an **ACL**, **UFW**, a
> **resolver's bind**, or the **AdGuard/Pi-hole containers** — is a **regression**: verify it live
> and keep the ACL `tests` pinning `100.124.146.77:53` and `100.115.253.109:53` (grant **8**;
> evidence in [`acl-lockout-audit.md`](acl-lockout-audit.md) §4.1/§5b). The canonical architecture
> is [`../network/dns.md`](../network/dns.md); the rule is also written for agents in
> [`../../governance/multi-agent-workflow.md`](../../governance/multi-agent-workflow.md).

## 1. Method (read-only, reproducible)

Evidence was collected per host with the same probe script (no config/service was touched):

- `tailscale dns status` and `tailscale debug prefs` (`CorpDNS`) → which Linux DNS backend
  Tailscale chose.
- `systemctl is-active systemd-resolved`, `ss -tlnp | grep 127.0.0.53`, `/etc/resolv.conf`
  (`readlink -f` + content), `/etc/systemd/resolved.conf` + `resolved.conf.d/`.
- **`getent hosts doubleclick.net`** — the **libc** path, i.e. *how applications actually
  resolve* (NSS). This is the test that matters; `resolvectl query` alone can give a
  false-negative (the 2026-10-13 lesson).
- **`resolvectl query --cache=no doubleclick.net`** — the **systemd-resolved internal** path,
  which can differ from the libc path.

Hosts reached over Tailscale SSH: `psicopompo` (local), `kuaray`, `kavure`, `ybytu`
(`ybytu-vnic`), `ybyra`. **`kururu` was unreachable at the first pass** (`tailscale ssh` →
`502 Bad Gateway`, `dial tcp 100.127.188.45:22: i/o timeout`). Re-probed on the implementation
pass: it **answers `tailscale ping`** (`pong … via 192.168.3.55:45227` in 4 ms) and its Dropbear
listens on LAN `192.168.3.55:22`, but it runs **no Tailscale SSH server** and its Dropbear rejects
the audit key (`Permission denied (publickey,password)` — the only local key, `id_ed25519`, is
**passphrase-protected** and no agent is loaded). So it is **L3-reachable but still not
administrable** from the audit session — **unmapped** (see §4.2).

## 2. The map

`Mode` = the backend Tailscale selected (`resolvOwner()` → `dnsMode()`). `stub?` = is the
systemd-resolved stub answering on `127.0.0.53:53`? `libc` / `internal` = does a **blocked**
domain (`doubleclick.net`) come back filtered (`0.0.0.0`/`::`) on each path?

| Host | Tailscale `CorpDNS` | Mode | `/etc/resolv.conf` | resolved.conf `DNS=` | `DNSStubListener` / stub on `127.0.0.53` | libc filters? | internal (resolved) filters? | Matches the doc? |
|---|---|---|---|---|---|---|---|---|
| **psicopompo** | `true` | `systemd-resolved` | symlink → `/run/systemd/resolve/stub-resolv.conf` | `9.9.9.9#dns.quad9.net 1.1.1.1#cloudflare-dns.com` + `DNSOverTLS=opportunistic` | default (`yes`) · **yes** | ✅ `::` | ✅ `0.0.0.0` + `::` | ✅ (`dns.md` Node Profile) |
| **kuaray** | `true` | `systemd-resolved` | symlink → `stub-resolv.conf` | same | default · **yes** | ✅ `::` | ✅ `0.0.0.0` + `::` | ✅ (`tailscale.md` table) |
| **kavure** | `true` | `systemd-resolved` | symlink → `stub-resolv.conf` | same | default · **yes** | ✅ `::` | ✅ `0.0.0.0` + `::` | ⚠️ doc silent on the host's own resolver (Pi-hole role only) |
| **ybyra** | `true` | `systemd-resolved` | symlink → `stub-resolv.conf` | `9.9.9.9#dns.quad9.net 1.1.1.1#cloudflare-dns.com` + `DNSOverTLS=opportunistic` | default · **yes** | ✅ `::` | ✅ `0.0.0.0` + `::` | ✅ (fallback added 2026-10-13) |
| **ybytu** | `true` | **`systemd-resolved`** | symlink → `/run/systemd/resolve/stub-resolv.conf` | `9.9.9.9#dns.quad9.net 1.1.1.1#cloudflare-dns.com` + `DNSOverTLS=opportunistic` | default (`yes`) · **yes** (`127.0.0.53`) | ✅ `::` | ✅ `0.0.0.0` + `::` | ✅ (unified 2026-10-13) |
| **kururu** | — | — | — | — | — | — | — | **unmapped** (L3-reachable, no admin path — §4.2) |

Notes that refine the table:

- **The two paths now converge on every reachable host.** On `psicopompo`, `/etc/nsswitch.conf`
  is `hosts: mymachines resolve …` → libc goes through **nss-resolve** → systemd-resolved
  (same path as `resolvectl`). On `kuaray`/`kavure`/`ybyra`/`ybytu` it is `hosts: files dns`
  → libc reads `/etc/resolv.conf`. On **all five** that file is now the **stub** (`127.0.0.53`),
  which lands on the same resolved instance — so libc and internal agree. (Before the fix,
  `ybytu`'s `/etc/resolv.conf` was Tailscale's file (`100.100.100.100`) while resolved talked
  to `9.9.9.9` — the divergence this map reported, now removed.)
- All five hosts carry `"CorpDNS": true` and `"RouteAll": false`, and `tailscale dns status`
  shows the two race resolvers (`100.115.253.109` = AdGuard/ybytu, `100.124.146.77` =
  Pi-hole/kavure) plus the `ts.net.` split route — i.e. the **filter layer is identical
  everywhere**, and now the **host resolver topology** is too.
- Every host's `tailscale0` link shows `Current Scopes: DNS` with
  `DNS Servers: 100.100.100.100 fd7a:115c:a1e0::53` and
  `DNS Domain: chimaera-heptatonic.ts.net ~.`. (Before the fix, `ybytu`'s showed
  `Current Scopes: none` because Tailscale injected **no** DNS into resolved in `direct` mode.)

## 3. Divergences (host → what the doc says → what the host does)

> **Resolution status (2026-10-13):** items **1, 3 and 4 are fixed** (implementation in §4.1);
> item **2 is now moot** (the durable fix makes the workaround unnecessary); item **5** is benign
> drift. The original findings are kept verbatim below for the record.

1. **ybytu runs a parallel topology (the headline).** `tailscale.md` correctly documents
   `ybytu` as **`direct`** "because AdGuard Home binds `0.0.0.0:53`, so `DNSStubListener=no`".
   That is true today — but it is exactly the *different topology* the pillar forbids, and it
   has a live consequence: on ybytu the **systemd-resolved internal path does not filter**.
   `resolvectl query --cache=no doubleclick.net` returns the **real** Google IPs, and
   `resolvectl query kavure.chimaera-heptatonic.ts.net` returns **public IPs**
   (`2607:f740:f::684`, `199.38.181.54`, …) instead of the tailnet `100.124.146.77`, while the
   **libc** path (`getent`) filters correctly. So an app on ybytu that resolves through
   resolved (rather than libc) **leaks unfiltered** and **loses MagicDNS**.
   > **Resolved 2026-10-13.** AdGuard now publishes only on `100.115.253.109:53` + `127.0.0.1:53`
   > (no more `0.0.0.0:53`), the stub listener is active (`127.0.0.53`), and Tailscale re-detected
   > the **`systemd-resolved`** backend (`ret=systemd-resolved`). Both paths now filter
   > (`0.0.0.0`/`::`) and MagicDNS returns the tailnet IP — see §4.1.
2. **The documented HB-013 workaround is not installed.** `servers/ybytu.md` and
   `network/tailscale.md` say a `tailscaled` drop-in
   (`/etc/systemd/system/tailscaled.service.d/10-resolvconf-misdetect.conf`, an `ExecStartPre`
   re-linking `/etc/resolv.conf` before each start) is in place. It is **absent**:
   `/etc/systemd/system/tailscaled.service.d/` is empty and `systemctl cat tailscaled` shows
   only the vendor unit. ybytu is therefore exposed again to the
   [`tailscale/tailscale#19062`](https://github.com/tailscale/tailscale/issues/19062)
   boot-time regression (HB-013 remains **open** — "verify it persists across reboot").
   > **Moot 2026-10-13.** With `/etc/resolv.conf` a symlink to the stub, `resolvOwner()` returns
   > `systemd-resolved` and the drop-in is **unnecessary** — the directory stays empty on purpose.
   > HB-013's remaining step is the reboot-persistence check (owner's call).
3. **Leftover experiment artifacts on ybytu.** `/etc/systemd/resolved.conf.d/` contains
   `adguardhome.conf.bak-2026-10-13`, `.bak2-…` and `.bak3-…` — the **reverted parallel
   topology** (`DNS=127.0.0.1` + `Domains=~.` + `DNSStubListener=no`). They are inert
   (systemd only reads `*.conf`) but are test residue that should be deleted.
   > **Resolved 2026-10-13.** All three `.bak*` files were deleted; `resolved.conf.d/` is empty.
4. **ybyra's global fallback is missing.** The `dns.md` egress table states that "Hosts
   (systemd-resolved)" carry a **global fallback `9.9.9.9`/`1.1.1.1` with
   `DNSOverTLS=opportunistic`". `ybyra`'s `/etc/systemd/resolved.conf` is an **empty
   `[Resolve]`** — no `DNS=`, no `DNSOverTLS=`. It resolves via `tailscale0`
   (`100.100.100.100`, `~.`) and Oracle metadata DNS (`169.254.169.254`, domain
   `vcn06051818.oraclevcn.com`); functionally fine, but it does **not** match the doc's
   fleet-wide egress claim.
   > **Resolved 2026-10-13.** `DNS=9.9.9.9#dns.quad9.net 1.1.1.1#cloudflare-dns.com`,
   > `FallbackDNS=` and `DNSOverTLS=opportunistic` were added to `/etc/systemd/resolved.conf`
   > (canonical fleet text, identical to `kuaray`/`kavure`), and `systemd-resolved` restarted.
   > `resolvectl status` now shows the global fallback; `tailscale0` still owns `~.`.
5. **Minor, benign drifts.** `psicopompo` and `kavure` each carry **two** `+DefaultRoute`
   links (LAN `192.168.3.1` and `tailscale0`); `tailscale0` wins because it owns `~.`, so the
   LAN DNS never answers general queries — worth knowing, not a fault. `kavure`/`kuaray`/
   `ybyra`/`ybytu` use `nsswitch` `files dns` while `psicopompo` uses `resolve`; both end at
   systemd-resolved. `kavure`'s host-resolver mode is **not documented**
   at all (only its Pi-hole role is).

## 4. The unified logic — implemented (2026-10-13)

**The unified logic** is the one the fleet already ran on 4 of 5 hosts and the one
`dns.md`/`tailscale.md` implicitly assume (now true fleet-wide):

> `systemd-resolved` in **stub mode** (`/etc/resolv.conf` → `/run/systemd/resolve/stub-resolv.conf`,
> `DNSStubListener=yes`, `127.0.0.53` answering), with Tailscale in the **`systemd-resolved`
> backend** pushing `100.100.100.100` (`~.`) into `tailscale0`; the global `9.9.9.9#dns.quad9.net
> 1.1.1.1#cloudflare-dns.com` + `DNSOverTLS=opportunistic` list stays only as the Tailscale-down
> fallback. Filtering and MagicDNS are then identical on the libc and the resolved paths.

The plan for **ybytu** (the root fix) — executed exactly as recorded in §4.1:

| Step | Change | Why |
|---|---|---|
| 1 | Stop AdGuard Home binding `0.0.0.0:53`: in `/home/ubuntu/homelab/adguardhome/compose.yml` bind `100.115.253.109:53` (+ `127.0.0.1:53` if needed) instead of `0.0.0.0:53`; or set `dns.bind_hosts: [100.115.253.109, 127.0.0.1]` in `AdGuardHome.yaml` | Frees `127.0.0.53:53`. `0.0.0.0:53` is **not** required: the tailnet race reaches AdGuard at its tailnet IP, and `resolved.conf(5)` notes the stub auto-disables when its port is taken |
| 2 | Remove `DNSStubListener=no` from `/etc/systemd/resolved.conf` (back to the default `yes`) | Re-enables the stub → `127.0.0.53` answering |
| 3 | Point `/etc/resolv.conf` at `/run/systemd/resolve/stub-resolv.conf` (symlink) | This is the exact fix in [#19062](https://github.com/tailscale/tailscale/issues/19062): `resolvOwner()` then returns `systemd-resolved`, so the boot-time `openresolv` misdetection **cannot** recur — the `10-resolvconf-misdetect.conf` workaround becomes unnecessary |
| 4 | Delete the inert `/etc/systemd/resolved.conf.d/adguardhome.conf.bak*` files | Remove test residue |
| 5 | Restart `systemd-resolved`, then `tailscaled` | Apply; Tailscale should log `ret=systemd-resolved` |

**Do not** use AdGuard's official "`address already in use`" recipe
(`DNS=127.0.0.1` + `DNSStubListener=no` + `/etc/resolv.conf` → `/run/systemd/resolve/resolv.conf`)
— that is the **parallel topology** that was reverted, and it is the *opposite* of unification.

### 4.1 Implementation & verification (2026-10-13)

**ybytu — the root fix.** The mechanism is exact: AdGuard's Docker publish held the host's
`0.0.0.0:53`, which includes `127.0.0.53`, so `systemd-resolved`'s stub could not bind and was
implicitly disabled (`DNSStubListener=no`), leaving Tailscale in `direct` mode with its own
`/etc/resolv.conf` (the `#19062` trample loop). Changes, one step at a time:

| # | File | Before | After |
|---|---|---|---|
| 1 | `/home/ubuntu/homelab/adguardhome/compose.yml` | `"53:53/tcp"`, `"53:53/udp"` (→ `0.0.0.0:53`) | `"100.115.253.109:53:53/tcp|udp"` + `"127.0.0.1:53:53/tcp|udp"` |
| 2 | `/etc/systemd/resolved.conf` | `DNSStubListener=no` | line removed (default `yes`) |
| 3 | `/etc/resolv.conf` | regular file, Tailscale-written (`100.100.100.100`) | symlink → `/run/systemd/resolve/stub-resolv.conf` |
| 4 | `/etc/systemd/resolved.conf.d/` | `adguardhome.conf.bak-2026-10-13{,.bak2,.bak3}` | empty (deleted) |
| 5 | services | `tailscaled` in `direct` mode | `systemctl restart systemd-resolved` + `tailscaled` → **`systemd-resolved`** backend |

> **Why the AdGuard change is the compose file, not `AdGuardHome.yaml`'s `bind_hosts`.** The
> container's netns has no `100.115.253.109` (that IP lives in the host netns); `docker-proxy`
> forwards host `IP:53` → container `172.22.0.2:53`, so the in-container bind must stay
> `0.0.0.0`. The **host-publish** is the lever that frees `127.0.0.53`.
>
> **Why a `tailscaled` restart is mandatory.** `--accept-dns=false/true` reuses the *existing*
> DNS manager (still `direct`), so it re-tramples `resolv.conf`; only a fresh start re-runs
> `resolvOwner()`. The restart was run detached (it briefly drops Tailscale SSH) with a
> safety-net rollback. Startup log now reads
> `dns: [resolved-ping=yes rc=resolved resolved=file nm=no resolv-conf-mode=stub ret=systemd-resolved]`.

**Who used AdGuard on a non-tailnet interface?** **Nobody.** `ybytu` is an Oracle Cloud VM
with no `192.168.3.x` interface (its "LAN" is the VCN `10.0.0.136/24`); the home LAN reaches it
only through kavure's subnet router, i.e. at the **tailnet IP** — preserved. AdGuard's sampled
query log shows clients only `172.22.0.1` (the docker-proxy hop), `100.115.253.109` and
`127.0.0.1` — **no `10.0.0.x`, no public, no `192.168.3.x`**. The old `0.0.0.0` publish was in
fact a defect (Docker DNAT bypasses the host `INPUT` firewall), so narrowing it also closes
that exposure — the tailnet race path is untouched.

**ybyra — the fallback.** `/etc/systemd/resolved.conf` `[Resolve]` was empty; the canonical
three lines (`DNS=…`, `FallbackDNS=`, `DNSOverTLS=opportunistic`) were added and
`systemd-resolved` restarted. The `~.` route on `tailscale0` is unchanged.

**Verification (the five tests), per host touched:**

| Host | `tailscale dns status` (race) | `resolv.conf` | libc (`getent hosts doubleclick.net`) | internal (`resolvectl query --cache=no`) | MagicDNS (`kavure.…ts.net`) | health |
|---|---|---|---|---|---|---|
| **ybytu** | ✅ `100.115.253.109` + `100.124.146.77` | ✅ stub | ✅ `::` | ✅ `0.0.0.0` + `::` | ✅ `100.124.146.77` | ✅ clean |
| **ybyra** | ✅ both | ✅ stub | ✅ `::` | ✅ `0.0.0.0` + `::` | ✅ `100.124.146.77` | ✅ (only the benign `--accept-routes` note) |
| psicopompo / kuaray / kavure | ✅ both | ✅ stub | ✅ `::` | ✅ `0.0.0.0` + `::` | ✅ `100.124.146.77` | ✅ clean |

**Rollback:** pre-change copies of every edited file are in
`/root/dns-unification-backup-2026-10-13/` on `ybytu` (and the `resolved.conf` copy on `ybyra`).

### 4.2 kururu — unmapped (no administrative path)

`kururu` is **L3-reachable** (`tailscale ping` → `pong … 4 ms`; Dropbear on `192.168.3.55:22`)
but the audit session has **no admin path**: it runs **no Tailscale SSH server** (unlike the
other nodes) and its Dropbear rejects the audit key (the only local key is
**passphrase-protected** and no agent is loaded). Nothing was changed — by design ("do not
invent"). When it becomes reachable:

- The systemd-resolved stub recipe **does not apply verbatim**: `kururu` is **Alpine/musl**
  with **no systemd**. The portable equivalent is *Tailscale DNS enabled (`CorpDNS=true`) with
  the libc path (`/etc/resolv.conf`) pointing at a resolver that also receives the Tailscale
  config* — i.e. ensure `resolv.conf` is not a Tailscale-trampled static file and that MagicDNS
  answers. Its `HB-015` note already documents `--netfilter-mode=off` on this kernel.
- It stays **untagged** until it hosts a service (see `network/tailscale.md`).

**Doc follow-ups — ✅ resolved (2026-10-13):** the AdGuard `:53` bind was still stale in
`network/ports.md` §2.4, `services-catalog.md` line 155 and `guides/homelab-traps-2026-10.md` §9
(all now record the tailnet-IP + loopback publish). The admin console `0.0.0.0:3000` is unchanged
and remains the HB-047 re-bind item. `network/dns.md` and `services/adguard-home.md` were updated
with the fix.

**HB-013 linkage:** this map is the evidence that HB-013's root cause is fixed (stub mode
restored; the `direct`-mode trample loop is gone) and the `10-resolvconf-misdetect.conf`
workaround is obsolete. `HB-013` remains in `servers/ybytu.md` `pending:` only for the
**reboot-persistence** confirmation and backlog archival — both are the owner's step (this
change does not touch `backlog*.md`).

## 5. Official sources (what the doc mandates, and what upstream says)

- **Tailscale — DNS in Tailscale** ([tailscale.com/kb/1054/dns](https://tailscale.com/kb/1054/dns)):
  clients must opt in (`CorpDNS`); *"Tailscale either proxies all DNS requests (in which case
  Tailscale queries all nameservers in parallel and uses the quickest response) or defers to the
  operating system"*; on Linux *"DNS support uses a DNS server listening on `127.0.0.x`"*. This
  backs the parallel race in `dns.md` and the `100.100.100.100` forwarder.
- **Upstream bug** [`tailscale/tailscale#19062`](https://github.com/tailscale/tailscale/issues/19062)
  (open, `OS-linux`/`dns`): root cause confirmed by the reporter and by other commenters —
  `/etc/resolv.conf` as a **regular file** carrying Tailscale's own `resolvconf-overwrite`
  header makes `resolvOwner()` return `resolvconf`, `resolvconfStyle()` classifies the
  `resolvectl` shim as `openresolv`, and DNS breaks after an unclean stop/reboot. The fix that
  works is **`ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf`** (stub symlink)
  → `ret=systemd-resolved`. This is precisely step 3 above.
- **systemd-resolved** ([`systemd-resolved.service(8)`](https://man.archlinux.org/man/systemd-resolved.service.8.en)):
  four `/etc/resolv.conf` modes; *"the selected mode … is detected fully automatically,
  depending on whether `/etc/resolv.conf` is a symlink to `/run/systemd/resolve/resolv.conf`
  or lists `127.0.0.53` as DNS server"*; the **stub** mode is *"recommended"*. Also: linking
  `/etc/resolv.conf` to the **uplink** file makes clients *"bypass systemd-resolved and talk
  directly to the known DNS servers"* — the trap behind ybytu's internal leak.
- **`resolved.conf(5)`** ([man](https://man.archlinux.org/man/resolved.conf.5.en)): `DNS=`,
  `Domains=` (`~.` = route all to this link's servers), and **`DNSStubListener`**: *"the DNS
  stub listener is turned off implicitly when its listening address and port are already in
  use"* — which is why AdGuard on `0.0.0.0:53` forces `DNSStubListener=no`.
- **AdGuard Home FAQ** ([github.com/AdguardTeam/AdGuardHome/wiki/FAQ](https://github.com/AdguardTeam/AdGuardHome/wiki/FAQ),
  `bind: address already in use`): the official recipe is `DNS=127.0.0.1` + `DNSStubListener=no`
  + `/etc/resolv.conf` → `/run/systemd/resolve/resolv.conf`. **This is a different topology**
  (resolved forwards to AdGuard on loopback); it is what the owner reverted, and it conflicts
  with the "one unified logic" pillar — hence §4 uses the fleet standard instead.

## See also

- [`../network/dns.md`](../network/dns.md) — the canonical DNS architecture
- [`../network/tailscale.md`](../network/tailscale.md) — Tailscale DNS backend selection + HB-049
- [`../services/adguard-home.md`](../services/adguard-home.md) · [`../services/pihole.md`](../services/pihole.md) · [`../services/unbound.md`](../services/unbound.md)
- [`../servers/ybytu.md`](../servers/ybytu.md) — HB-013 (ybytu Tailscale DNS health)
