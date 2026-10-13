---
tags: [homelab, network, tailscale, tutorial]
---

# Tailnet ACL Runbook — From Allow-All to Least Privilege

> **Goal:** move `chimaera-heptatonic.ts.net` from a single `grants {src:*, dst:*, ip:*}`
> allow-all rule to a tagged, least-privilege policy — **without locking anyone out**, not even
> for a minute.
>
> **Implements** the tailnet layer of [`security-baseline.md`](security-baseline.md) and the
> backlog item [**HB-049**](../backlog.md). The policy is **not** in this vault: it lives in the
> private repo `MNEMOCINE-ACL` and is deployed by GitOps. See
> [`../network/tailscale.md`](../network/tailscale.md) for the current inventory.

## 0. Why this is delicate

The tailnet is the **only** filter for tailnet traffic — the host firewall cannot see it
(Tailscale's `ts-input`/`ts-forward` accept `tailscale0` first; see the security baseline). So a
mistake in the policy is not "a port closes", it is **the fleet disappears at once**. This runbook
is therefore **additive-first**: every restrictive change is preceded by a permissive rule that
already covers the same path, so the moment the allow-all rule is removed nothing that should work
stops working.

## 1. Source of truth and guardrails

- **Repo:** `MNEMOCINE-ACL` (private), deployed by `tailscale/gitops-acl-action`
  (`action: test` on PRs, `action: apply` on `main`).
- **Console lockout is ON** ("Prevent edits in the admin console") — Git is authoritative; a
  console edit is overwritten on the next push. This is what makes the rollback in §8 a real
  rollback.
- **OIDC** uses `policy_file` scope; the subject is the immutable `owner_id/repo_id` form.
- **Never** edit the policy by hand on a host: `tailscale` CLI cannot modify ACLs, and the console
  is locked.

## 2. The critical trap: `autogroup:self` does not match tagged devices

The current `ssh` rule is:

```jsonc
{ "action": "accept", "src": ["autogroup:member"], "dst": ["autogroup:self"], "users": ["autogroup:nonroot", "root"] }
```

`autogroup:self` matches **only user-owned devices** — the official docs state it "does not apply
to tags". The moment a server carries `tag:server`, it **stops matching `autogroup:self`** and the
`accept` rule no longer covers it.

**Consequence:** if you tag the servers **before** a tag-based `ssh` rule exists, SSH to **every
server** is lost simultaneously.

**Rule of this runbook:** the tag-based `ssh` rule (`dst: ["tag:server"]`) MUST land **before** any
device is tagged. That is exactly why Phase 1 is additive and Phase 2 only tags.

## 3. Target tag taxonomy

Tags describe **purpose**, never ownership. User devices (phones, tablets, the Windows desktop)
stay **untagged** and are reached through `autogroup:member` / `autogroup:self` — the officially
recommended practice.

| Tag | Devices | Purpose |
|---|---|---|
| `tag:server` | `psicopompo`, `ybytu` (`ybytu-vnic`), `ybyra`, `kuaray`, `kavure` (+ future `ybytyra`); **`kururu` ONLY once it hosts a service** | The infra servers (the base role of every host). |
| `tag:edge` | `ybyra`, `ybytu`, `sumaenima`, `miracena` | Devices allowed to open a **public Funnel**. |
| `tag:subnet-router` | `kavure` | Advertises `192.168.3.0/24`. |
| `tag:exit-node` | `kavure`, `ybytu` | Advertise an exit node. |
| `tag:monitoring` | `kavure` (Prometheus/Grafana/Loki) + the exporter hosts | Observability stack and scrape targets. |
| `tag:registry` | `psicopompo` | The private Docker registry (`5000`). |

> **`kururu` is NOT tagged today.** It is a probe/WoL node, not a service host. **If `kururu` ever
> hosts a service another tailnet device must reach** (a Docker service, a listener, a subnet
> route), **tag it `tag:server` in the same change.** See
> [`tailnet-tagging.md`](tailnet-tagging.md) §1 for the general rule.

A device can carry several tags (e.g. `kavure` = `tag:server` + `tag:subnet-router` +
`tag:exit-node` + `tag:monitoring`). Ownership of every tag is `autogroup:admin` (the shorthand
`[]`).

**Human access** is `autogroup:member`, restricted to the **Homepage catalogue** — the ports the
dashboard actually exposes — **minus the infrastructure ports** that no human needs directly:
`2375` (docker-socket-proxy), `2049` (NFS), `2377/7946/4789` (Swarm control plane), `9092`
(ingress), `5000` (registry), and `22` (SSH, governed by the `ssh` section instead).

## 4. Phase 1 — Additive PR (keep allow-all)

Add the tags, the tag-based rules and the tests **while the allow-all rule still exists**. Nothing
can break: allow-all is a superset of everything below.

```jsonc
{
  "tagOwners": {
    "tag:server":        ["autogroup:admin"],
    "tag:edge":          ["autogroup:admin"],
    "tag:subnet-router": ["autogroup:admin"],
    "tag:exit-node":     ["autogroup:admin"],
    "tag:monitoring":    ["autogroup:admin"],
    "tag:registry":      ["autogroup:admin"],
  },

  "nodeAttrs": [
    // Only edge devices may open a public Funnel.
    { "target": ["tag:edge"], "attr": ["funnel"] },
  ],

  "grants": [
    // KEEP allow-all for now (removed in Phase 3).
    { "src": ["*"], "dst": ["*"], "ip": ["*"] },

    // (1) Members reach the Homepage catalogue, not the infra ports.
    // NOTE (verified against the live policy parser): a grant `ip` entry holds
    // ONE port/range — comma lists are rejected ("only one port range allowed").
    // Each port is therefore its own entry.
    {
      "src": ["autogroup:member"],
      "dst": ["tag:server"],
      "ip": [
        "tcp:80", "tcp:443", "tcp:3000", "tcp:3001", "tcp:3002", "tcp:3003",
        "tcp:4533", "tcp:5053", "tcp:5678", "tcp:8000", "tcp:8080", "tcp:8082",
        "tcp:8083", "tcp:8123", "tcp:8188", "tcp:8384", "tcp:8444", "tcp:8686",
        "tcp:8766", "tcp:9090", "tcp:9091", "tcp:9093", "tcp:9095", "tcp:9096",
        "tcp:9097", "tcp:9696", "tcp:18554", "tcp:18555", "tcp:25565", "tcp:61208",
        "udp:53", "udp:25565",
      ],
    },
    // (1b) The SHARED users are the game players. Shared machines do NOT advertise
    // subnets into the tailnet they are shared with, so the shared players reach
    // kavure only at its tailnet IP (100.124.146.77) — the tighten PR MUST keep
    // these ports for autogroup:shared or Twister/Onidsouza/Papaco/zepp are cut.
    {
      "src": ["autogroup:shared"],
      "dst": ["tag:server"],
      "ip": ["tcp:25565", "udp:24454", "udp:2456-2458", "udp:16261-16262"],
    },
    // (2) Exit nodes: members only — NEVER autogroup:shared.
    { "src": ["autogroup:member"], "dst": ["autogroup:internet"], "ip": ["*"] },
    // (3) The subnet router is a path AROUND port rules if left uncovered.
    { "src": ["autogroup:member"], "dst": ["192.168.3.0/24"], "ip": ["*"] },
    // (4) Preserve the peer relay (ybyra depends on it — verified live).
    {
      "src": ["autogroup:member"],
      "dst": ["100.115.253.109", "100.124.146.77"],
      "app": { "tailscale.com/cap/relay": [] },
    },
    // (5) Monitoring may scrape the exporters (one port per entry, as above).
    { "src": ["tag:monitoring"], "dst": ["tag:monitoring"], "ip": ["tcp:9100", "tcp:9090", "tcp:3100", "tcp:61208"] },
  ],

  "ssh": [
    // root → interactive check (least privilege; the plan removes the blanket accept).
    { "action": "check",  "src": ["autogroup:admin"], "dst": ["tag:server"], "users": ["root"] },
    // non-root → accept, admin only.
    { "action": "accept", "src": ["autogroup:admin"], "dst": ["tag:server"], "users": ["autogroup:nonroot"] },
    // KEEP the existing `autogroup:self` rule UNCHANGED (it grants each user SSH
    // to their own untagged devices). Rewriting it would drop `root` from the
    // self-rule and be a behaviour change — Phase 1 must stay purely additive.
    { "action": "accept", "src": ["autogroup:member"], "dst": ["autogroup:self"], "users": ["autogroup:nonroot"] },
  ],

  "tests": [
    // The admin path MUST stay open (pins the tag-based ssh rule BEFORE tagging).
    { "src": "ceduardorodrig@gmail.com", "accept": ["tag:server:22"] },
    // Members DO reach the catalogue.
    { "src": "ceduardorodrig@gmail.com", "accept": ["tag:server:3000"] },
    // NOTE (verified against the live policy parser):
    //  • a test `src` cannot be an autogroup → "unknown user or host"; use a
    //    concrete member e-mail (or a group);
    //  • a test destination cannot be CIDR (so `192.168.3.0/24:80` is invalid);
    //  • a `deny` pin is FALSE by construction while allow-all is present, so the
    //    deny pins (infra ports; exit node for shared) belong to the **Phase 3**
    //    PR that deletes allow-all — not here.
  ],
}
```

**Steps:**

1. Open a PR against `MNEMOCINE-ACL` with the block above.
2. CI runs `action: test` — the `tests` block **must pass**. A failure means the tag-based rule
   does not actually cover the admin path; fix it before merging.
3. Merge → `action: apply` deploys. Allow-all still in place: **nothing changed for users.**
4. Verify (§7).

## 5. Phase 2 — Tag the devices — ✅ APPLIED (2026-10-13)

Tagging is a **device** action (console / API / CLI), not a policy action — the console lockout
does not block it. The tags are applied; the live map and the full rules are in
[`tailnet-tagging.md`](tailnet-tagging.md). Applied result:

| Device | Tags |
|---|---|
| `psicopompo` | `server`, `registry` |
| `kavure` | `server`, `subnet-router`, `exit-node`, `edge`, `monitoring` |
| `kuaray` | `server` |
| `ybyra` | `server`, `edge` |
| `ybytu` (`ybytu-vnic`) | `server`, `exit-node` |
| `sumaenima`, `miracena` | `edge` (Funnel containers) |
| `kururu` + all user devices | *(none)* |

**Two things that had to be done *before* the tags landed (they are not optional):**

1. **The tag-based `ssh` rule first.** `autogroup:self` does not match tagged devices (§2), so the
   `dst: tag:server` ssh rule was deployed in Phase 1 before any device was tagged.
2. **A `tag:server → tag:server` ssh rule.** Learned live: **a tagged node connects out as its
   tag**, so `psicopompo` (itself `tag:server`) stopped matching the admin rule and SSH from it to
   every server broke. Commit `76b66fa` (rule `src: tag:server → dst: tag:server`, root+nonroot)
   fixed it. Servers administering servers is the intended trust zone.

> **Operational lesson — verify the deploy finished before you test.** Testing against a policy
> whose `action: apply` has not completed gives a false "it doesn't work". `gh run list --limit 1`
> can return the **previous** run; confirm the run for **your** commit is `completed success`
> first. An early test here was misread for exactly this reason — the rule was correct and live.

> **Funnel pre-tagging (PR [#7](https://github.com/ceduardorodrig/MNEMOCINE-ACL/pull/7)).** The
> `nodeAttrs` Funnel target was widened to `["autogroup:member", "tag:edge"]` **before** tagging
> `sumaenima`/`miracena`, so tagging them did not drop the public site (a tagged node no longer
> matches `autogroup:member`).

> **To tag a *new* device** (e.g. `kururu` when it hosts a service), follow
> [`tailnet-tagging.md`](tailnet-tagging.md) §6.

## 6. Phase 3 — Tighten (remove `src:*`) — ⚠️ PENDING

Open the second PR that **deletes** `{ "src": ["*"], "dst": ["*"], "ip": ["*"] }`. Everything that
must survive is then covered by the tag-based rules from Phase 1 and the tags from Phase 2 — **but
the 2026-10-13 audit found two grant gaps that MUST be closed in the same PR, or the tighten
breaks the spine:**

1. **`tag:monitoring → tag:server`** — today the monitoring grant is `tag:monitoring →
   tag:monitoring` only. Once the exporters live on `tag:server` devices, Prometheus (on `kavure`,
   `tag:monitoring`) can no longer scrape them. Add the scrape ports to a
   `tag:monitoring → tag:server` grant.
2. **`tag:server → tag:server`** — **does not exist today.** Without it, once allow-all is gone,
   the **NFS mount** (`2049`), the **Swarm control plane** (`2377`/`7946`/`4789`), **Loki** log
   shipping, the **private registry** (`5000`) and **`hl-infer`** (`9095`) all fall — every
   server↔server dependency rides the tailnet. Add a `tag:server → tag:server` grant for those
   ports.

Also in this PR:

3. **Enable the `deny` pins** with a **concrete member e-mail** (`autogroup` is not a valid test
   `src`): e.g. a member must **not** reach `tag:server:2375` (and `:2049`, `tag:registry:5000`),
   and `autogroup:shared` must **not** reach the exit node / a public address.
4. **Restrict the Funnel `nodeAttrs` to `tag:edge` only** — drop `autogroup:member` (today any
   member can open a public Funnel).
5. Regenerate `TS_AUTH_KEY` **with `tag:edge`** (Phase 4 / §8).

Steps:

1. PR → `action: test` (the denials now actually bite; the admin `accept` must still pass).
2. Merge → apply.
3. Verify (§7) **from a non-admin device too**, to confirm the denials hold.

> **If SSH breaks after this merge:** the tag-based `ssh` rule is missing or the device is not
> tagged. Roll back (§8) immediately, then re-check Phase 1/2.

> **Before testing, confirm the apply finished** (see Phase 2's operational lesson) — a test run
> against a not-yet-deployed policy reads as a false failure.

## 7. Verification

```bash
# Effective policy — the allow-all rule must be gone, the tagged rules present.
tailscale debug netmap | jq '.PacketFilter'

# Devices and their tags.
tailscale status --json | jq '.Self.Tags, (.Peer[] | {HostName, Tags})'

# The admin path (must succeed, across nodes — loopback to self is refused by design).
tailscale ssh root@kavure 'echo OK'
tailscale ssh root@ybytu 'echo OK'

# The catalogue (must succeed).
curl -sS --max-time 5 http://100.124.146.77:3000/ -o /dev/null && echo aiostreams-ok

# A denial (must FAIL).
curl -sS --max-time 5 http://100.124.146.77:2375/ -o /dev/null && echo "LEAK: docker-socket-proxy reachable" || echo "denied-ok"
```

The CI `action: test` is the primary gate; the commands above are the live confirmation.

## 8. Phase 4 — Regenerate `TS_AUTH_KEY` with a tag

The `sae-edge` stack authenticates a containerized `tunnel` with `TS_AUTH_KEY`. Today the key is
untagged, so any node it creates is an untagged member with key expiry.

1. In the console, create a **new** auth key with `tag:edge` (and, for standby, make it
   **ephemeral** so a decommissioned failover does not leave an orphan node record).
2. Update the secret in the SOPS store (`TS_AUTH_KEY`) — never inline it. (This also addresses
   HB-051: the key currently sits in plaintext in a running service spec.)
3. Redeploy the `sae-edge` stack so the container re-authenticates with the tagged key.
4. **Tagged devices have key expiry disabled by default** — the new node is born tagged and does
   not expire.

> ⚠️ **Key-expiry trap.** Never click **"Disable key expiry"** on an **already-expired** device.
> On an expired device that action *removes* the **"Temporarily extend"** recovery path, so the
> node can no longer be brought back without re-authenticating. Disable expiry **before** it
> expires, or re-auth with a tagged key instead.

## 9. Rollback

- **Preferred (GitOps):** `git revert` the tightening commit and push — `action: apply`
  re-deploys the previous policy. Because the console is locked, this is authoritative.
- **Emergency (console):** use **"Edit anyway"** to paste the previous policy back; it survives
  until the next Git push. Use only to restore access, then fix the PR.
- **Never** hand-edit the policy on a host — the `tailscale` CLI cannot write ACLs.

## 10. Tests to keep (regression pins)

Keep these in the policy permanently — they are what makes a future edit fail CI instead of
quietly re-opening the tailnet:

- a **member** must **not** reach `tag:server:2375` (and the other infra ports);
- an **admin** **must** reach `tag:server:22`;
- a member **must** reach the catalogue (`tag:server:3000`);
- `autogroup:shared` **must not** reach the exit node (`autogroup:internet` / a public address);
- the subnet `192.168.3.0/24` is reachable **only** because of its explicit grant.

## References

- [`security-baseline.md`](security-baseline.md) — the posture and the gaps this closes
- [`../network/tailscale.md`](../network/tailscale.md) — tailnet inventory, exit nodes, subnet router, peer relay, Funnels
- [`../services/sumaenima-edge.md`](../services/sumaenima-edge.md) — the `sae-edge` stack that consumes `TS_AUTH_KEY`
- [`secrets-centralizados.md`](secrets-centralizados.md) — the SOPS/age store
- [`../backlog.md`](../backlog.md) — HB-049 and HB-051
- Tailscale policy syntax: <https://tailscale.com/kb/1337/policy-syntax>
- ACL GitOps action: <https://github.com/tailscale/gitops-acl-action>
