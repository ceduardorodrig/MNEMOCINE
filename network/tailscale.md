---
tags: [homelab, network, tailscale]
pending: [HB-049]
---

# Tailscale

**Tailnet:** `chimaera-heptatonic.ts.net`

## Tailnet Node Inventory

| Machine | Tailscale IP | Role |
|---|---|---|
| psicopompo | `100.82.51.112` | Workstation, Dev + GPU worker nodes (StênioBOT) |
| ybytu | `100.115.253.109` | Exit Node, DNS, Peer Relay (`:40000/udp`) |
| ybyra | `100.66.224.34` | Primary Cloud Edge Reverse Proxy |
| kuaray | `100.94.209.99` | Multimedia and Archive Storage Mirror |
| kavure | `100.124.146.77` | Dedicated Services Server, Swarm Manager, Peer Relay (`:40000/udp`), Subnet Router (`192.168.3.0/24`) |
| anansi | `100.71.232.79` | Android Mobile Device |
| kururu | `100.127.188.45` | Headless lightweight probe node (Samsung SM-T110 / Alpine Linux) |

## Tagging — the applied map + the rules for future devices

Since **2026-10-13** the tailnet is no longer flat: the infra devices carry **purpose tags**
(`tag:server`, `tag:edge`, `tag:subnet-router`, `tag:exit-node`, `tag:monitoring`, `tag:registry`)
and the policy targets them. The full guide is
[`../guides/tailnet-tagging.md`](../guides/tailnet-tagging.md); this is the short version.

**The applied map** (verified live 2026-10-13):

| Device | Tags |
|---|---|
| `psicopompo` | `server`, `registry` |
| `kavure` | `server`, `subnet-router`, `exit-node`, `edge`, `monitoring` |
| `kuaray` | `server` |
| `ybyra` | `server`, `edge` |
| `ybytu` (device `ybytu-vnic`) | `server`, `exit-node` |
| `sumaenima`, `miracena` | `edge` (Funnel **containers**, not VMs) |
| `kururu` | *(none)* — **not a server yet** |
| All user devices (phones, tablets, desktop) | *(none)* — by design |

> **The rule to remember:** a device that **hosts a service** another tailnet device must reach
> **must carry `tag:server`** (plus the matching role tag) — and that includes **`kururu`**: it is
> untagged **today** only because it is a probe/WoL node; **the moment `kururu` hosts a Docker
> service (or any listener/subnet route), tag it `tag:server`.** Consumers (phones, laptops,
> probes) stay untagged. Full wording and traps: [`../guides/tailnet-tagging.md`](../guides/tailnet-tagging.md) §1.

**Consequences of a tag** (documented Tailscale behaviour, verified here): it **removes the
device's user identity**; it makes the device **stop matching `autogroup:self`** (so the tag-based
`ssh` rule must exist *before* tagging); it is **effectively irreversible** ("you cannot remove
all tags"); and a tagged node **connects out as its tag** — which is why `psicopompo` (itself
`tag:server`) lost SSH until the `tag:server → tag:server` rule was added.

## Device visibility in the mobile app (why some users' devices are missing)

The Tailscale app's **Network Devices** list groups what it shows **by the owning user** plus a
single combined **"Tagged Devices"** group ([tailscale/tailscale#3183](https://github.com/tailscale/tailscale/issues/3183),
maintainer comment), and it lists only devices **in that node's netmap**. Netmap trimming is
**documented behaviour**: your node sees the devices it may connect to, the devices that may connect
to it, **its own user's** devices, and usable exit nodes — nothing else
([*What devices can connect to or know mine?*](https://tailscale.com/docs/concepts/device-visibility)).
So a phone that showed only **"Eduardo Rodrigues"** + the tagged group was **expected**, not a bug:
the least-privilege tighten (HB-049, phase 3, 2026-10-13) removed the allow-all grant, so `ann`'s
and `iza`'s devices had no permitted path to/from the owner's phone and were trimmed from the app's
netmap.

> ✅ **Resolved 2026-10-13 (D11 / [HB-063](../backlog.md), ACL PR [#14](https://github.com/ceduardorodrig/MNEMOCINE-ACL/pull/14)).**
> The owner decided the family should live in **one big LAN** (*"quero a gente vivendo em uma grande
> LAN"*) and the flat **`autogroup:member → autogroup:member`** grant was added — **members now see
> and reach each other's devices again** and the app no longer trims them. The **tagged servers stay
> OUT** of it (applying a tag removes the user identity, so a tagged node matches **neither** side of
> `autogroup:member`); their access remains the purpose-scoped `member → tag:server` catalogue.
> Verified live: on the tagged `psicopompo` the `netmap` `PacketFilter` is byte-identical to the
> pre-change filter **except** the removed dead `:8766`. Sources: [*What devices can connect to or
> know mine?*](https://tailscale.com/docs/concepts/device-visibility) (netmap trimming) and
> [policy syntax](https://tailscale.com/kb/1337/policy-syntax) (`autogroup:member` is valid as
> **both** `src` and `dst`). See
> [`../guides/design-decisions-2026-10.md`](../guides/design-decisions-2026-10.md) §D11 ·
> [`../guides/acl-lockout-audit.md`](../guides/acl-lockout-audit.md) §10.

The **admin console** Machines page (and the API) still lists **every** tailnet device
([filter](https://tailscale.com/docs/features/access-control/device-management/how-to/filter) ·
[export](https://tailscale.com/docs/features/access-control/device-management/how-to/export-list)).

## Access Standard (Tailscale SSH)

**Primary administration access method: Tailscale SSH** — leverages end-to-end WireGuard authentication within the tailnet without exposing TCP port 22 to the public internet.

```bash
tailscale ssh kavure@kavure
tailscale ssh root@kuaray
tailscale ssh ubuntu@ybyra
```

### Check Mode Mitigation → Non-Root `accept` Rule (2026-09-29)

Tailscale's **default ACL** applies `action: check` when connecting to **one's own devices**, requiring **browser re-authentication every 12 hours** (`checkPeriod: 12h`). While manageable for interactive human sessions, this broke headless automation runs: automated scripts like `deploy-swarm.sh` invoking remote SSH commands stalled waiting for interactive authorization links.

**ACL Policy Fix Applied via Tailscale Admin Console** (Access Controls → JSON Editor) on **2026-09-29**: non-root connections proceed directly without re-auth.

> ⚠️ **Correção 13/10/2026 — o doc estava desatualizado.** Este trecho descrevia **duas** regras
> (`accept` non-root + `check` root). O `policy.hujson` **real** tem **uma só**, e ela **aceita `root`
> também** — sem a checagem interativa (commit `dba0ea9` *"acl(ssh): accept root without 12h
> reauthentication check"*). O `sshTests` do próprio arquivo **afirma** isso. A política é **mais
> permissiva** do que este documento dizia.

```jsonc
// policy.hujson — estado REAL em 13/10/2026 (quatro regras; ver o guia de tagging)
"ssh": [
  // 1) user-owned devices (untagged): non-root AND root accepted directly (the 2026-09-29 fix).
  { "action": "accept", "src": ["autogroup:member"], "dst": ["autogroup:self"],  "users": ["autogroup:nonroot", "root"] },
  // 2) tagged servers, administered by an admin: root → interactive check; non-root → accept.
  { "action": "check",  "src": ["autogroup:admin"],  "dst": ["tag:server"],     "users": ["root"] },
  { "action": "accept", "src": ["autogroup:admin"],  "dst": ["tag:server"],     "users": ["autogroup:nonroot"] },
  // 3) server → server (a tagged node connects OUT as its tag, not as a user).
  { "action": "accept", "src": ["tag:server"],       "dst": ["tag:server"],     "users": ["autogroup:nonroot", "root"] },
],
"sshTests": [
  { "src": "ceduardorodrig@gmail.com", "dst": ["ceduardorodrig@gmail.com"], "accept": ["edu", "root"] },
],
```

> **`root` is now `check` on the tagged path** (rule 2) — the least-privilege recommendation is
> satisfied for tagged servers. The untagged `autogroup:self` path (rule 1) still accepts `root`
> directly, kept deliberately so headless automation (which cannot click a browser check link)
> keeps working. The three tag rules and the reason rule 3 exists are documented in
> [`../guides/tailnet-tagging.md`](../guides/tailnet-tagging.md) §4.

### SSH hardening — OpenSSH sem senha (2026-10-13)

**O que foi encontrado:** `kavure` e `kuaray` tinham **`PasswordAuthentication yes`** (efetivo) no
OpenSSH. Como a tailnet é *allow-all*, **qualquer device da tailnet** (inclusive os 5 dispositivos de
terceiros da família) podia forçar-bruta esses usuários — e a LAN também (as duas não têm firewall).

**O que foi feito:** drop-in `/etc/ssh/sshd_config.d/00-homelab.conf` com
`PasswordAuthentication no` + `KbdInteractiveAuthentication no` em **kavure** e **kuaray**.
O `00-` ordena **antes** do `50-cloud-init.conf` (que diz `yes`) e o `sshd_config` usa o **primeiro**
valor que obtém — por isso o drop-in vence.

**Verificado:** `sshd -T` → `passwordauthentication no`; teste pela **LAN** → `Permission denied (publickey)`
(o servidor deixou de oferecer o método `password`). Rollback: apagar o drop-in + `systemctl reload ssh`.

**⚠️ E uma clareza importante que isso revelou:** o `:22` **via tailnet** nestes hosts é servido pela
**Tailscale SSH** (`RunSSH: true`; o cliente autentica pela identidade da tailnet — `Authenticated …
using "none"`), **não** pelo OpenSSH. Logo:
- **fechar a senha do OpenSSH foi seguro** — nada usava aquele caminho (o acesso do dono é Tailscale SSH);
- o **OpenSSH só serve a LAN**, e é ali que a senha importava;
- as chaves em `authorized_keys` (`edu@psicopompo` na kuaray/kavure, `kavure` no psicopompo) **não
  autenticam** a chave atual (`id_ed25519`) → são **vestigiais** (candidatas a limpeza).

**psicopompo:** **não tem sshd do OpenSSH servindo TCP** (serviço `inactive`, **sem host keys**, nada
em `:22`) — o `:22` dele é **100% Tailscale SSH**. O drop-in foi deixado como *baseline defensiva*
(se o sshd algum dia subir, nasce sem senha). **Não havia senha a fechar ali.**

**Rationale for `autogroup:self` over `tag:server` (updated 2026-10-13):** the untagged
`autogroup:self` rule is what gives each **user** SSH to **their own** (untagged) devices, and it is
kept for exactly that. Earlier ACL drafts used only `dst: ["tag:server"]` when no machine carried a
tag (rendering tag-based policies ineffective); since **2026-10-13** the servers **do** carry tags,
so tag-based `ssh`/grants are live **and** `autogroup:self` remains for user devices. See
[`../guides/tailnet-tagging.md`](../guides/tailnet-tagging.md).

**Policy Syntax Nuances Verified via Official Documentation** ([Tailscale Policy Syntax](https://tailscale.com/kb/1337/policy-syntax)):

| Rule Nuance | Behavior |
|---|---|
| **Evaluation Order** | SSH rules evaluate from most restrictive to least (*check* before *accept*), but match only if the target SSH user is included in `users`. Since `check` lists only `root`, non-root sessions (e.g., `edu`, `kavure`) bypass `check` and match `accept` directly ✅ |
| **`checkPeriod` Attribute** | Available only on Premium/Enterprise plans. In personal accounts, declaring `checkPeriod` may reject policy saves; the 12h default operates implicitly |
| **SSH `dst` Targets** | Accepts tags, `autogroup:self`, or named users; wildcard `*` is prohibited |
| **Remote Username Mapping** | Tailscale authorizes connections only against pre-existing user accounts on the remote host. For example, connecting from kavure via `ssh psicopompo` fails with `tailnet policy does not permit you to SSH as user "kavure"` because no local user `kavure` exists on psicopompo. The correct invocation is `ssh -l edu psicopompo` |
| **CLI Limitations** | `tailscale` CLI (1.102.4) cannot modify ACLs directly — updates require the admin console or API |

**Automated Verification:**

```bash
ssh -o BatchMode=yes kavure 'echo OK'        # Returns OK immediately without web prompts
```

> **Loopback Connection Restriction:** Executing `ssh psicopompo` directly from within psicopompo fails with `Connection refused` because traffic addressed to the local Tailscale IP does not route through `tailscaled`'s netstack. Always test remote access across different nodes.

### ACL GitOps Pipeline (Operational Since 2026-09-29)

The tailnet access control policy is version-controlled inside the **private GitHub repository** [`ceduardorodrig/MNEMOCINE-ACL`](https://github.com/ceduardorodrig/MNEMOCINE-ACL) and deployed via [`tailscale/gitops-acl-action`](https://github.com/tailscale/gitops-acl-action) (`action: test` runs on pull requests; `action: apply` deploys automatically on commits to `main`).

- **OIDC Federated Credentials:** Configured with `policy_file` scope (Issuer `GitHub Actions`).
- **Subject Matching (Immutable Syntax):** Repositories created after July 2026 require the `owner_id/repo_id` format: `repo:ceduardorodrig@276087739/MNEMOCINE-ACL@1396147999:*`.
- **Console Lockout Active:** "Prevent edits in the admin console" is enabled under **Settings → Policy file management**, establishing Git as the single source of truth. Manual modifications in the web console are overwritten on subsequent Git pushes.

### Fallback: Classic Public-Key SSH

When Tailscale SSH cannot be utilized (such as specialized tools expecting raw keypairs), standard SSH with explicit host aliases is configured (`~/.ssh/config` on psicopompo):

```text
Host kavure
    HostName 100.124.146.77
    User kavure
    IdentityFile ~/.ssh/id_ed25519
    PreferredAuthentications publickey
```

> ✅ **Corrigido 13/10/2026 — o achado anterior estava ERRADO.** Este fallback **funciona**: a chave
> `~/.ssh/id_ed25519` (`SHA256:U3VF75ds…`) **está** nas `authorized_keys` da kavure **e** da kuaray, e o
> sshd **aceita** a chave (`ssh -vv` → *"Server accepts key"*). O teste inicial falhou porque a chave tem
> **passphrase** e o teste era **não-interativo** (`BatchMode=yes`) → sem agente/prompt a assinatura não
> acontece, e o cliente reporta `Permission denied (publickey)`.
>
> **Lição registrada:** um teste de chave não-interativo **não** prova que a chave está errada — o `-vv`
> é que diz a verdade (`Server accepts key` × `no mutual signature algorithm`).
>
> **O único item real:** a **kuaray** tem **2 entradas duplicadas antigas** (`SHA256:GLg5fhcl…`,
> comentário `edu@Psicopompo`, de maio/2026) — candidatas a limpeza; a atual fica. No **psicopompo**, a
> chave `kavure` (`SHA256:/Ry7Xvbk…`) é legítima (é a chave da própria kavure).

## Least-Privilege ACL Redesign (HB-049) — State (2026-10-13)

Moving the tailnet off the single **allow-all** grant (`{src:*, dst:*, ip:*}`) to a tagged,
least-privilege policy. The procedure is [`../guides/tailnet-acl-runbook.md`](../guides/tailnet-acl-runbook.md);
this section records **where it stands**.

> **State verified against the deployed policy (`MNEMOCINE-ACL`, `main`) and the live tailnet on
> 2026-10-13.** The policy is deployed by GitOps; the console is locked, so `main` **is** the live
> policy.

- **Phase 1 — additive — ✅ MERGED & DEPLOYED (2026-10-13).** PR
  [#5](https://github.com/ceduardorodrig/MNEMOCINE-ACL/pull/5) (`acl/least-privilege-phase-1`)
  merged at 17:05; CI (`acls`) green, `action: apply` succeeded. It added, **on top of** the still-
  present allow-all grant (so nothing changed for users):
  - `tagOwners` for `tag:server`, `tag:edge`, `tag:subnet-router`, `tag:exit-node`,
    `tag:monitoring`, `tag:registry` (ownership `autogroup:admin`);
  - the **catalogue-derived** `autogroup:member` grant (per-port, one port per `ip` entry — the
    parser rejects comma lists) and the `192.168.3.0/24` subnet grant;
  - the **exit-node** grant (`autogroup:internet`) for **members only** — never `autogroup:shared`;
  - the **`cap/relay`** grant preserved verbatim (ybyra relies on the peer relay);
  - the tag-based `ssh` rules **added on top of** the existing `autogroup:self` rule;
  - the **accept** `tests` that hold while allow-all is still present.
- **PR [#7](https://github.com/ceduardorodrig/MNEMOCINE-ACL/pull/7) — Funnel, pre-tagging.** Widened
  `nodeAttrs` to `target: ["autogroup:member", "tag:edge"]` **before** tagging the Funnel nodes, so
  tagging `sumaenima`/`miracena` did not drop the public site.
- **Commit `76b66fa` — the SSH hard lesson.** Added the `tag:server → tag:server` `ssh` rule after a
  live outage: a tagged node **connects out as its tag**, so `psicopompo` (itself `tag:server`) no
  longer matched the admin rule. See [`../guides/tailnet-tagging.md`](../guides/tailnet-tagging.md) §4.
- **Phase 2 — tag the devices — ✅ APPLIED (2026-10-13).** The map above is live. `kururu` and all
  user devices stay **untagged** (see the rule in the *Tagging* section).
- **The game players are shared users.** The players (`Twister`, `Onidsouza`, `Papaco`, `zepp`)
  arrive as **`autogroup:shared`**, and Tailscale's documented behaviour is that *"shared machines
  do not advertise subnets into the tailnet they are shared with"* — so they have **no LAN path**
  and reach `kavure` only at its **tailnet IP** (`100.124.146.77`). That is why the
  `autogroup:shared` grant covers exactly the game ports (`25565`/`24454`/`2456-2458`/`16261-16262`)
  and why `25565` is a **tailnet**, not a LAN, exception.
- **Phase 3 — tighten — ✅ MERGED & DEPLOYED (2026-10-13).** The allow-all grant is **gone**; every
  load-bearing path is now an explicit, purpose-scoped grant. Landed across three PRs:
  [#7](https://github.com/ceduardorodrig/MNEMOCINE-ACL/pull/7) (Funnel `nodeAttrs` → **`tag:edge`**
  only), [#8](https://github.com/ceduardorodrig/MNEMOCINE-ACL/pull/8) (the `tag:monitoring →
  tag:server` scrape and the `tag:server → tag:server` plane — NFS `2049`, Swarm `2377/7946/4789`,
  Loki `3100`, registry `5000`, `hl-infer` `9095`) and
  [#9](https://github.com/ceduardorodrig/MNEMOCINE-ACL/pull/9) (delete `{ "src": ["*"], "dst": ["*"],
  "ip": ["*"] }` + the `deny` pins with a concrete member e-mail). CI (`acls`) green, `action:
  apply` succeeded.
- **Post-Phase-3 fix — the peer relay lost its tagged sources — ✅ MERGED & DEPLOYED
  (2026-10-13).** PR [#10](https://github.com/ceduardorodrig/MNEMOCINE-ACL/pull/10)
  (`acl/relay-tagged-src`). The relay grant (`cap/relay`) still had `src: ["autogroup:member"]`, but
  tagging had **removed the infra devices from `autogroup:member`** — so `ybyra` (and the whole
  tagged fleet) silently **dropped the peer relay and fell back to DERP**
  (`tailscale status` → `ybyra … relay "sao"`; `cap/relay` absent from psicopompo's `AllCaps`).
  Fix: `src: ["autogroup:member", "autogroup:tagged"]` — **`dst` unchanged**. Verified live after
  the apply: `ybyra` now shows `peer-relay 64.181.168.251:40000:vni:1219` (relaying through
  **ybytu**). See the *Peer Relays* section below.

> `stenio --reconcile` still reports `POLICY-UNDERIVABLE` for the remaining `ip: ["*"]` grants
> (exit node, subnet, `autogroup:self`, server↔server) — expected: those are control planes on a
> trusted, WireGuard-encrypted mesh, not user-facing ports. The Phase-1 policy comments that said
> *"no device carries a tag yet"* are gone from the current policy.

## Exit Nodes

| Node | Advertises Exit Node | Egress Route | Operational Guidance |
|---|---|---|---|
| **ybytu** (`100.115.253.109`) | ✅ Yes | Oracle Cloud Transit | **Preferred default** — stable cloud gigabit uplink |
| **kavure** (`100.124.146.77`) | ✅ Yes | Residential WAN (PPPoE 1492) | ⚠️ Routes across local home link; subject to PPPoE MTU constraints (see [`mtu-pppoe.md`](mtu-pppoe.md)) |
| psicopompo | ❌ No | — | Workstation node |

### Exit Node Client Usage

```bash
# List available exit nodes across the tailnet:
tailscale exit-node list

# Route client traffic through ybytu (Oracle Cloud egress):
tailscale set --exit-node=ybytu

# Disable exit node routing:
tailscale set --exit-node=
```

## Subnet Routers (2026-10-05)

**kavure** serves as the authoritative **Subnet Router** for the physical residential LAN (`192.168.3.0/24`), enabling remote access to the home router management portal (`192.168.3.1`), local Tuya IoT hardware, and local network devices without requiring individual Tailscale clients.

| Subnet Router | Advertised Subnet | Local Interface | Route Authorization | NAT Mechanism |
|---|---|---|---|---|
| **kavure** (`100.124.146.77`) | `192.168.3.0/24` | `enp1s0` (Gigabit Ethernet) | `autoApprovers` via GitOps (`MNEMOCINE-ACL`) | Linux Kernel Masquerade (iptables/nftables) |

### Operational Details
- **Masquerade (SNAT):** Outbound traffic from the Tailnet into the home LAN is translated to kavure's local interface IP (`192.168.3.41`). Local devices (such as smart bulbs and the ISP ONT) see incoming requests originating directly from kavure, eliminating the need for custom static routes on the ISP gateway.
- **GitOps Auto-Approval:** The `autoApprovers.routes` stanza in `policy.hujson` automatically validates routes announced by administrative accounts (`autogroup:admin`, `ceduardorodrig@gmail.com`).

### Node Activation on kavure
```bash
# 1. Enable kernel packet forwarding (/etc/sysctl.d/99-tailscale.conf):
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# 2. Advertise the home subnet:
sudo tailscale set --advertise-routes=192.168.3.0/24
```

### Client Route Acceptance
- **Mobile Clients (Android / iOS):** Automatically accept advertised subnet routes.
- **Linux / macOS Clients:**
  ```bash
  tailscale set --accept-routes=true
  ```

### Linux Client Health Notice (`--accept-routes is false`)

Following subnet router deployment on kavure, local Linux nodes (`psicopompo`, `kuaray`, `kururu`) report:
```text
# Health check:
#     - Some peers are advertising routes but --accept-routes is false
```

> **Technical Decision (2026-10-09): Maintain `--accept-routes=false` on Local LAN Machines.**  
> Devices physically connected to the home switch already reside directly within `192.168.3.0/24`. Enabling `--accept-routes=true` on them causes kernel routing rules (`ip rule 5270 lookup 52`) to intercept local LAN packets and hairpin them needlessly through Kavure's tunnel interface. The health warning is advisory and benign; keeping it disabled on local nodes maintains peak physical network throughput.

## DNS management (MagicDNS) on Linux hosts

Tailscale picks its Linux DNS backend at **every `tailscaled` start** from the content of
`/etc/resolv.conf` (`resolvOwner()` in `net/dns/manager_linux.go`), then uses one of:
`systemd-resolved` (D-Bus, preferred), `NetworkManager`, `debian-resolvconf`, `openresolv`, or
`direct` (Tailscale rewrites `/etc/resolv.conf` itself). MagicDNS answers on
`100.100.100.100` (`fd7a:115c:a1e0::53`) regardless.

| Host | `/etc/resolv.conf` | Mode | Why |
|---|---|---|---|
| `psicopompo` | symlink → `/run/systemd/resolve/stub-resolv.conf` | **`systemd-resolved`** | stub listener active (`127.0.0.53`) |
| `kuaray` | symlink → `/run/systemd/resolve/stub-resolv.conf` | **`systemd-resolved`** | stub listener active |
| `kavure` | symlink → `/run/systemd/resolve/stub-resolv.conf` | **`systemd-resolved`** | stub listener active |
| `ybyra` | symlink → `/run/systemd/resolve/stub-resolv.conf` | **`systemd-resolved`** | stub listener active |
| `ybytu` | symlink → `/run/systemd/resolve/stub-resolv.conf` | **`systemd-resolved`** | AdGuard no longer binds `0.0.0.0:53` (tailnet IP + loopback only) → stub active (**fixed 2026-10-13**) |
| `kururu` | — (Alpine/musl, no systemd) | **unmapped** | no admin path from the audit session; see the map §4.2 |

> ⚠️ **`resolvconf` shim trap (upstream [`tailscale/tailscale#19062`](https://github.com/tailscale/tailscale/issues/19062)).**
> On Ubuntu/Debian the `systemd-resolved` package ships `/usr/sbin/resolvconf` as a symlink to
> `resolvectl`. If `resolv.conf` carries a `resolvconf` marker — **including Tailscale's own**
> `.../s/resolvconf-overwrite` header — `resolvOwner()` returns `resolvconf`, `resolvconfStyle()`
> classifies the shim as `openresolv`, and the openresolv manager calls `resolvconf -a tailscale`,
> which the shim rejects (`Failed to resolve interface "tailscale"`). `homelab_tailscale_health`
> drops to `0` and it **recurs on every boot** for hosts in `direct` mode. **Fixed 2026-10-13:**
> `ybytu` now runs the same stub topology as the rest of the fleet (`/etc/resolv.conf` →
> `stub-resolv.conf`), so `resolvOwner()` returns `systemd-resolved` and the regression cannot
> recur — the `10-resolvconf-misdetect.conf` workaround was never installed and is no longer
> needed. See [`../servers/ybytu.md`](../servers/ybytu.md) and
> [`../guides/dns-consistency-map.md`](../guides/dns-consistency-map.md) §4.1.

## Public Funnels & Tunnels

Tailscale Funnels expose designated local ports publicly via TLS without requiring inbound router port forwarding.

| Endpoint | Funnel URL | Target Service |
|---|---|---|
| kavure | `kavure.chimaera-heptatonic.ts.net:10000` | AioStreams (`kavure:3000`) |
| sumaenima (tunnel) | `sumaenima.chimaera-heptatonic.ts.net` | StênioBOT (via container tunnel `sae-edge_tunnel` proxying to `api:9090` on kavure) |
| miracena (tunnel) | `miracena.chimaera-heptatonic.ts.net` | WordPress (via container tunnel `miracena-tunnel` proxying to NPM `:80` → WordPress `:8085`) |

> **Security Policy:** Home Assistant remains **strictly restricted to the tailnet**: `http://100.124.146.77:8123`. No public Funnel is provisioned for Home Assistant.

### Managing Funnels via CLI

```bash
# Expose a local service via Tailscale Funnel:
tailscale funnel --bg 443 http://localhost:PORT

# Inspect active funnel mappings:
tailscale funnel status

# Tear down funnel endpoint:
tailscale funnel off
```

## Peer Relays (High-Throughput Relaying — 2026-10-02)

**Peer Relays** allow tailnet devices to act as high-speed relay intermediaries for peer-to-peer connections when direct UDP traversal is blocked by symmetric CGNAT or restrictive firewalls, routing traffic across private relays before falling back to public DERP servers.

| Host | Tailscale IP | UDP Port | Listening Socket |
|---|---|---|---|
| **ybytu** | `100.115.253.109` | `40000` | `0.0.0.0:40000` / `[::]:40000` (`tailscaled`) |
| **kavure** | `100.124.146.77` | `40000` | `0.0.0.0:40000` / `[::]:40000` (`tailscaled`) |

### Enabling Peer Relay on Host
```bash
sudo tailscale set --relay-server-port=40000
sudo tailscale debug prefs | grep RelayServerPort
sudo ss -ulpn | grep 40000
```

### ACL Capability Grant (`policy.hujson`)

The `src` must include **both** the members **and** the tagged nodes. Tagging removes a device from
`autogroup:member` (a device has a user identity *or* a tag, never both — see the *Tagging* section),
so an `autogroup:member`-only `src` **silently dropped the whole tagged fleet off the relay**.
`autogroup:tagged` is the documented complement of `autogroup:member`. The `dst` stays pinned to the
two relay nodes.

```jsonc
"grants": [
  {
    "src": ["autogroup:member", "autogroup:tagged"],
    "dst": ["100.115.253.109", "100.124.146.77"],
    "app": {
      "tailscale.com/cap/relay": []
    }
  }
]
```

> ⚠️ **Regression fixed 2026-10-13 (PR [#10](https://github.com/ceduardorodrig/MNEMOCINE-ACL/pull/10)).**
> With `src: ["autogroup:member"]` only, `ybyra` (`tag:server`, `tag:edge`) lost the relay and rode
> DERP (`relay "sao"`). The capability is **application-level** (`cap/relay`): it is delivered as a
> `PacketFilter` **`Caps`** entry (`tailscale.com/cap/relay-target`), **not** as an `ip:port` rule —
> which is why a `tests` assertion **cannot pin it** (tests only check network `accept`/`deny`; a
> test `src` *may* be a tag, but the relay has no `ip` to assert). It is therefore verified **live**.
> After the fix: `tailscale status` → `ybyra … active; peer-relay 64.181.168.251:40000:vni:1219`, and
> `tailscale ping ybyra` → `via peer-relay(64.181.168.251:40000:vni:1219)` (was `DERP(sao)`).
> `64.181.168.251` is **ybytu**'s public endpoint (`:40000`). Members keep the capability unchanged
> (the `src` still lists `autogroup:member`; the CI tests pin the member path with a concrete e-mail).

To verify active relay traffic:
```bash
tailscale status | grep peer-relay
```
The connection status displays `peer-relay` instead of `relay` (DERP) or `direct`.

## Edge Funnel Authentication (`TS_AUTH_KEY`)

The `sae-edge` stack provisions a containerized `tunnel` instance to publish the primary public gateway using a pre-authenticated Tailscale auth key:
- Centralized inside SOPS secret store (`TS_AUTH_KEY`) and passed into Compose via runtime environment injection (`set -a; source .env`).
- Ephemeral keys are recommended for standby failover instances to prevent orphaned node records upon decommission.
