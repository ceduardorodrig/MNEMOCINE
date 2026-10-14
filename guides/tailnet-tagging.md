---
tags: [homelab, network, tailscale, tutorial]
---

# Tailnet Tagging — Applied Map & Rules for Future Devices

> **Audience:** anyone — a human or an AI agent with **zero prior context** — who is about to
> add, or is wondering about, a device on the tailnet. Read this **before** you create a
> service on a node.
>
> **Status:** the map below was verified against the **live tailnet** and the **deployed policy**
> on **2026-10-13**. The policy itself is not in this vault: it lives in the private repo
> `MNEMOCINE-ACL` and is deployed by GitOps. The *procedure* is
> [`tailnet-acl-runbook.md`](tailnet-acl-runbook.md); this guide documents *what is applied* and
> *the rules*.

## 1. The rule that answers "does this device need a tag?"

> **If a device hosts a service another tailnet device must reach — a Docker service, a
> listener, a subnet route, an exit node, or a public Funnel — it MUST carry the matching
> `tag:server`-family tag, applied in the same change that introduces the service. A device that
> only *consumes* (a phone, a laptop, a probe) stays untagged.**

**Worked example — `kururu`.** `kururu` is a headless probe / Wake-on-LAN node
(`servers/kururu.md`). It is **deliberately untagged today**. The moment `kururu` hosts anything
that other tailnet devices must reach — e.g. a new Docker service, a listener, or a subnet
route — **tag it `tag:server`** (plus any role tag it takes on) in the same step you introduce
the service. Until then, leave it untagged. This mirrors the live decision recorded on
2026-10-13: *"`kururu` (not a server yet — if one day it hosts a Docker service, **then** it gets
`tag:server`)"*.

The same rule applies to any future node (e.g. the planned `ybytyra`): **a hosted service is the
trigger for the tag.** Conversely, never tag a device that only provides a user-facing endpoint to
*its owner* (that is what the untagged user identity is for — see §3).

## 2. The applied map (verified live, 2026-10-13)

`tailscale status --json | jq '.Self.Tags, .Peer[] | {HostName, Tags}'` on `psicopompo`:

| Device | Applied tags | Why |
|---|---|---|
| **psicopompo** | `tag:server`, `tag:registry` | Workstation + GPU + NAS; hosts the private Docker registry (`:5000`). |
| **kavure** | `tag:server`, `tag:subnet-router`, `tag:exit-node`, `tag:edge`, `tag:monitoring` | Swarm manager & core services; advertises `192.168.3.0/24`; exit node; hosts the AioStreams Funnel (`:10000`); observability stack. |
| **kuaray** | `tag:server` | Standby mirror / media — a plain server. |
| **ybyra** | `tag:server`, `tag:edge` | Cloud primary edge (nginx + Funnel). |
| **ybytu** (device name `ybytu-vnic`) | `tag:server`, `tag:exit-node` | Cloud DNS + exit node. |
| **sumaenima** | `tag:edge` | The **container** that terminates the public Funnel for the Hub site (not a VM). |
| **miracena** | `tag:edge` | The **container** that terminates the public Funnel for the Miracena site. |
| **kururu** | *(none)* | Probe / WoL node — **not a server yet** (see §1). |
| Every **user device** (phones, tablets, the Windows desktop) | *(none)* | Per Tailscale best practice — *"do not use tags to authenticate user-owned devices"*. |

Six tags exist in `tagOwners`, all owned by `autogroup:admin`:

```jsonc
"tagOwners": {
  "tag:server":        ["autogroup:admin"],
  "tag:edge":          ["autogroup:admin"],
  "tag:subnet-router": ["autogroup:admin"],
  "tag:exit-node":     ["autogroup:admin"],
  "tag:monitoring":    ["autogroup:admin"],
  "tag:registry":      ["autogroup:admin"],
},
```

Tag meanings: `tag:server` = the base role of an infra host; `tag:edge` = may open a **public
Funnel**; `tag:subnet-router` = advertises a subnet; `tag:exit-node` = may be used as an exit
node; `tag:monitoring` = observability stack / scrape targets; `tag:registry` = the Docker
registry. **Tags describe purpose, never ownership**, and a device may carry several.

## 3. What applying a tag actually does (read before you tag)

Documented Tailscale behaviour, confirmed on this tailnet:

1. **It removes the device's user identity.** A device has *either* a user identity *or* a
   tag-based identity, never both. Tagging a previously user-authenticated device drops the
   user's identity.
2. **It stops matching `autogroup:self`.** The `ssh` rule that gives every user SSH to *their
   own* devices is `src: autogroup:member → dst: autogroup:self`, and `autogroup:self` matches
   **only untagged, user-owned devices**. The moment a server is tagged it falls out of that
   rule and is governed by the tag-based rules instead.
3. **It is effectively irreversible.** *"You cannot remove all tags from a device"* — a
   tag-based identity must keep at least one tag. To go back to a user identity you must
   **re-authenticate** the device with a key/identity that carries no tag.
4. **It does not, by itself, change key expiry.** Per Tailscale: changing tags via the console,
   CLI or API *"will not change [key expiry] unless you re-authenticate"* — if expiry was on it
   stays on, if it was off it stays off; **after re-authentication, expiry is disabled**. See §4
   (trap 5) and the verified state below.
5. **A tagged device connects *out* as its tag, not as a user.** This is the subtle one: when a
   tagged node opens a connection, its `src` is the tag (e.g. `tag:server`), so rules written for
   `autogroup:member` / `autogroup:admin` **do not match it**.

## 4. Traps (all learned live on 2026-10-13)

> **Trap 1 — the tag-based `ssh` rule must land BEFORE the first device is tagged.**
> Because tagging removes a node from `autogroup:self` (see §3.2), if you tag the servers before a
> `dst: ["tag:server"]` ssh rule exists, **SSH to every server is lost at once**. Order: land the
> tag-based rules first, then tag.

> **Trap 2 — a tagged device connects out as its tag (the one that cost the most time).**
> `psicopompo` — the machine the agents and the owner operate from — is itself `tag:server`. So
> the admin ssh rule (`src: autogroup:admin → dst: tag:server`) **cannot match psychopompo**: its
> outgoing `src` is `tag:server`, not the user. SSH from psychopompo to every server failed until
> the policy added `{ "action": "accept", "src": ["tag:server"], "dst": ["tag:server"],
> "users": ["autogroup:nonroot", "root"] }`. **Servers administrating servers is the intended
> trust zone** — it must stay allowed (headless automation such as `config-backup` runs as root).

> **Trap 3 — confirm the GitOps `apply` actually finished BEFORE you test.** A test run against a
> not-yet-deployed policy gives a wrong "it doesn't work" answer. `gh run list --limit 1` can
> return the **previous** run; check that the run for **your** commit is `completed success`
> before drawing conclusions. An early test here was misread for exactly this reason; the rule
> itself was correct and live all along.

> **Trap 4 — you cannot "just untag".** There is no clean undo (§3.3). Plan the tag as permanent;
> use `tag:server` on real service hosts and leave consumers untagged.

> **Trap 5 — key expiry is toggled by re-authentication, not by tagging.** Changing tags through
> the API/console leaves the current expiry state alone. A node created from an **untagged** auth
> key is born *with* expiry (default 180 days) and will eventually go offline unless you disable
> expiry or re-authenticate it tagged.

> **Trap 6 — a Funnel node must already be `tag:edge` in the policy before it is tagged.**
> `nodeAttrs` controls who may open a public Funnel. It was widened to
> `target: ["autogroup:member", "tag:edge"]` **before** the `sumaenima`/`miracena` nodes were
> tagged; otherwise tagging them would have **dropped the public site** (a tagged node no longer
> matches `autogroup:member`). Tighten the target to `tag:edge` only once the last untagged
> Funnel is gone.

> **Trap 7 — tagging can silently drop an `app`-capability grant (the peer relay).** Any grant whose
> `src` is `autogroup:member` stops matching a device the moment it is tagged. That is how `ybyra`
> (and the whole tagged fleet) lost the **peer relay** (`tailscale.com/cap/relay`) and fell back to
> DERP on 2026-10-13 — the grant still said `src: ["autogroup:member"]`. Whenever you tag a device,
> re-check **every** grant it depends on whose `src` is `autogroup:member`; the fix for the relay was
> `src: ["autogroup:member", "autogroup:tagged"]` (PR
> [#10](https://github.com/ceduardorodrig/MNEMOCINE-ACL/pull/10)). Unlike an `ip` grant, an **`app`
> capability is not covered by a `tests` assertion** — verify it live (`tailscale status` →
> `peer-relay`). See [`../network/tailscale.md`](../network/tailscale.md) → *Peer Relays*.

## 5. Key expiry — verified state (2026-10-13)

```bash
tailscale status --json | jq -r '.Peer[] | "\(.HostName)\t\(.KeyExpiry // "disabled")"'
```

Result: **every tagged device shows expiry disabled** (the `KeyExpiry` field is absent), while
the untagged user devices still carry concrete expiries. `kururu` (untagged) also has expiry
disabled — set deliberately for the always-on probe.

- **Consequence for the fleet:** the servers do **not** need a re-auth to stay online — expiry is
  already off. There is no open "servers will expire" item.
- **Consequence for a future host:** if a new device is registered with an **untagged** auth key,
  it *will* expire. Either create it with a tagged auth key, or disable expiry / re-authenticate
  it tagged (Trap 5). Never click *"Disable key expiry"* on an **already-expired** device — that
  removes the *"Temporarily extend"* recovery path (`tailnet-acl-runbook.md` §8).

## 6. Runbook — tag a new device

**Preconditions:** the tag already exists in `tagOwners`, and any rule that depends on the tag
(e.g. the tag-based `ssh` rule) is already **deployed** (Traps 1/3/6).

1. **If the device hosts a Funnel**, first confirm `nodeAttrs` already includes `tag:edge`
   (Trap 6).
2. **Apply the tag.** The tag *owner* (here `autogroup:admin`) does it:
   - **Console:** Machines → the device → *Edit tags* → add → Save. (The console lockout only
     blocks policy edits, not device tagging.)
   - **API:** `curl -X POST https://api.tailscale.com/api/v2/device/<id>/tags -u "tskey-<key>" -H 'Content-Type: application/json' --data-binary '{"tags":["tag:server"]}'`
   - **CLI (on the Linux host itself):** `sudo tailscale login --advertise-tags=tag:server` (add
     `--force-reauth` if it is signed in as another identity).
3. **Verify the tag landed:** `tailscale status --json | jq '.Peer[] | select(.HostName=="<name>") | .Tags'`.
4. **Verify the paths the tag now gates:** the tag-based `ssh`
   (`tailscale ssh root@<name>`) and the grants the tag is expected to satisfy.
5. **Re-check key expiry** (§5) — if the device is a server and shows an expiry, re-authenticate
   it tagged to disable it.

Tagging is a **device** action; it does **not** go through the ACL repo or a PR.

## 7. Where the rest of the policy lives

This guide covers **tags**. The `grants` (which ports, which sources), the Funnel `nodeAttrs`,
the `ssh` rules and the `tests` are the policy itself — read
[`tailnet-acl-runbook.md`](tailnet-acl-runbook.md) for the phased procedure and the current
open phases (Phase 3 tightening, the two grant gaps, Funnel restriction), and
[`../network/tailscale.md`](../network/tailscale.md) for the tailnet inventory.

## References

- [`tailnet-acl-runbook.md`](tailnet-acl-runbook.md) — the phased policy procedure and remaining phases
- [`security-baseline.md`](security-baseline.md) — the security posture and the open gaps
- [`../network/tailscale.md`](../network/tailscale.md) — tailnet inventory, exit nodes, subnet router, Funnels, peer relays
- [`../servers/kururu.md`](../servers/kururu.md) — the untagged probe node
- Tailscale tags: <https://tailscale.com/docs/features/tags> · key expiry: <https://tailscale.com/docs/features/access-control/key-expiry>
