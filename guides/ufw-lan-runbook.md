---
tags: [homelab, network, docker, tutorial]
pending: [HB-059]
---

# UFW LAN Runbook — Enforcing Tailnet-Only on the Host Layer

> **Goal:** make the host firewall actually enforce **tailnet-only** on the LAN/public layer —
> including container-published ports — on every host, without cutting the tailnet.
>
> **Implements** the LAN/public layer of [`security-baseline.md`](security-baseline.md) and the
> backlog item [**HB-047**](../backlog.md). The tailnet layer is a separate job
> ([`tailnet-acl-runbook.md`](tailnet-acl-runbook.md)); the two must not be confused — **the host
> firewall cannot filter tailnet traffic** (Tailscale's `ts-input`/`ts-forward` accept
> `tailscale0` first). This runbook only closes the LAN/public hole.

## 0. The holes this closes (and the one a naive `INPUT DROP` opens)

1. **Docker published ports bypass UFW.** Docker DNATs the packet in `nat/PREROUTING` **before**
   it reaches the `INPUT` chain, so a UFW `deny` never sees it. `ufw deny 8080` does **not** stop
   `-p 8080:80`. This is documented Docker behaviour; the supported hook is the **`DOCKER-USER`**
   chain.
2. **Firewall state.** As of **2026-10-13** `psicopompo`, `kuaray` **and** `kavure` run UFW with the
   tailnet-aware `DOCKER-USER` block (steps 1–3 applied), and **all three** use
   `DEFAULT_FORWARD_POLICY="DROP"` — psicopompo's `ACCEPT` was switched to `DROP` the same day with
   the owner's go-ahead, re-verified afterwards (the tailnet stayed open, the Swarm stayed
   `Ready`). The *forwarded* container path is covered by `DOCKER-USER` regardless.
3. **The intra-host `INPUT` gap — found and fixed 2026-10-13 (HB-047 step 2, `kuaray`).**
   `DOCKER-USER` only covers **forwarded** traffic. A container reaching a service on **its own
   host** is **local delivery** and lands on the host's `INPUT` chain — which UFW owns. Enabling
   `INPUT DROP` without a rule for the Docker subnets therefore breaks every container→host call.
   Two shapes hit it, and both are dropped:
   - a **host service** the container calls (`network_mode: host`, no DNAT) — e.g. Prometheus
     scraping its **own** Node Exporter at `100.124.146.77:9100` on `kavure`;
   - a **default-bridge (`docker0`) published port** — Docker's `nat/DOCKER` rules carry a
     `! -i docker0` guard, so a `docker0` container's packet to the host's published port is
     **not DNAT'd** and stays a local-delivery packet — e.g. the `*arr` stack on `kuaray`
     (`prowlarr → 100.94.209.99:8686`, `soularr → 100.94.209.99:8686/:5030`, …). Containers on a
     **user-defined** bridge do **not** hit this: their packets *are* DNAT'd and take the
     `FORWARD`/`DOCKER-USER` path.

   The fix is a **scoped** `INPUT` allow for the Docker subnets (§3.2) — **not** a blanket one.

## 1. Approach: manual `after.rules`, not `ufw-docker install`

`ufw-docker` (chaifeng) is the canonical tool, and its `install` command does the right thing:

```bash
sudo ufw-docker install --docker-subnets 100.64.0.0/10 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16
```

The `--docker-subnets` set **must include `100.64.0.0/10`** (the tailnet): the default set is only
`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, which would **drop tailnet→container traffic**.

**But prefer the manual block.** In **Swarm mode** `ufw-docker` deploys a **global service**
`ufw-docker-agent` on every node — and `ybyra` is both a Swarm worker and the **public edge**, so
that lands a **privileged container on the Internet-facing host**. Editing `/etc/ufw/after.rules`
by hand has the same effect on the rules without that trade. The block below is the ufw-docker
rules with the tailnet added.

## 2. The `after.rules` block (tailnet-aware)

Append to `/etc/ufw/after.rules` (and the IPv6 twin, §2.2):

```text
# BEGIN UFW AND DOCKER (tailnet-aware)
*filter
:ufw-user-forward - [0:0]
:ufw-docker-logging-deny - [0:0]
:DOCKER-USER - [0:0]
-A DOCKER-USER -j ufw-user-forward

-A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
-A DOCKER-USER -m conntrack --ctstate INVALID -j DROP
-A DOCKER-USER -i docker0 -o docker0 -j ACCEPT

# Trusted internal sources. THE TAILNET MUST BE HERE, or tailnet->container is dropped.
-A DOCKER-USER -j RETURN -s 100.64.0.0/10
-A DOCKER-USER -j RETURN -s 10.0.0.0/8
-A DOCKER-USER -j RETURN -s 172.16.0.0/12
# ⚠️ NO `-s 192.168.0.0/16 RETURN` — this line was in the first draft and it does
# NOT close the LAN: the home LAN is 192.168.3.0/24 ⊂ 192.168.0.0/16, so the
# trusted RETURN lets LAN→published-container through (proven live 2026-10-13:
# 192.168.3.100:9092 was LAN-reachable while the trusted line was present, and
# was blocked the moment it was removed). The tailnet-only outcome REQUIRES
# omitting it. The 10/8 and 172.16/12 RETURNs STAY — those are the Docker
# subnet sources (container egress), never the LAN.

# Block NEW connections from anywhere else into the container subnets.
-A DOCKER-USER -j ufw-docker-logging-deny -m conntrack --ctstate NEW -d 10.0.0.0/8
-A DOCKER-USER -j ufw-docker-logging-deny -m conntrack --ctstate NEW -d 172.16.0.0/12
-A DOCKER-USER -j ufw-docker-logging-deny -m conntrack --ctstate NEW -d 192.168.0.0/16

-A DOCKER-USER -j RETURN

-A ufw-docker-logging-deny -m limit --limit 3/min --limit-burst 10 -j LOG --log-prefix "[UFW DOCKER BLOCK] "
-A ufw-docker-logging-deny -j DROP

COMMIT
# END UFW AND DOCKER
```

The `-s 100.64.0.0/10 … -j RETURN` line is the one that keeps the tailnet alive. The
`ufw-docker-logging-deny` rules match **`-d` = the container subnet**, so a tailnet packet to a
container (`src 100.x → dst 172.x`) would be dropped without that RETURN.

### 2.2 IPv6 (`after6.rules`)

If Docker IPv6 is enabled, mirror the block in `/etc/ufw/after6.rules` and add the tailnet ULA
`fd7a:115c:a1e0::/48` to the trusted `-s … -j RETURN` set (the netmap shows the tailnet IPv6 range
is `fd7a:115c:a1e0::/48`).

## 3. Host-side rules (INPUT)

The `DOCKER-USER` block only covers **forwarded** container traffic. Host sockets (node_exporter,
Pi-hole web, rpcbind, etc.) are governed by the normal `INPUT` chain, so also:

```bash
# Allow the tailnet as a source on every host (idempotent).
sudo ufw allow in on tailscale0

# Forward policy: let UFW manage routing (psicopompo is currently "allow (routed)").
sudo sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="DROP"/' /etc/default/ufw

sudo ufw reload
```

### 3.1 LAN exceptions that MUST be kept

These are legitimately reachable from the physical LAN and must be explicitly allowed from
`192.168.3.0/24` (or by interface):

| Port | Service | Why it stays on the LAN |
|---|---|---|
| `22000/tcp,udp` | Syncthing | Peer sync on LAN **and** tailnet. |
| ~~`139,445/tcp`~~ | ~~Samba/SMB~~ | **Deactivated 2026-10-15** (no fleet dependencies; UFW rule purged). |
| ~~`3389/tcp`~~ | ~~xrdp~~ | **Deactivated 2026-10-15** (remote access unified via Tailscale SSH/SFTP; UFW rule purged). |
| `9777/udp`, `47990`, `47992/47993/tcp` | Punktfunk | Native LAN/tailnet streaming discovery. |
| `5353/udp`, `1900/udp` | Home Assistant mDNS/SSDP | IoT discovery — `network_mode: host`, cannot be restricted. |
| `40000/udp` | Tailscale Peer Relay | Direct WireGuard relay underlay on nodes running `--relay-server-port=40000` (`kavure`). Tailscale auto-manages port 41641 in iptables, but custom relay ports require explicit host UFW allow (added 2026-10-29). |
| ICMP (netwatch `lan_*`) | Path probes | The observability probes to the gateway/LAN. |

Everything else defaults to deny. (The bind remediation in HB-047 — re-binding the `0.0.0.0`
sockets to the tailnet IP or loopback — is the complementary half: with correct binds, the
firewall is a second line, not the only one.)

> **Corrected 2026-10-13 — `25565/tcp` is NOT a LAN exception.** This table used to carry
> `25565/tcp | Minecraft (Dominium) | Local household players`. The owner **confirmed that nobody
> plays over the LAN**: every player connects through the **tailnet** and reaches `kavure` at its
> **tailnet IP** (`100.124.146.77`) — the shared players (`autogroup:shared`) have no LAN path at
> all ("shared machines do not advertise subnets"). `25565` therefore belongs to the **tailnet**
> layer (the `autogroup:shared` grant in [`tailnet-acl-runbook.md`](tailnet-acl-runbook.md) §4),
> **not** to this LAN allow-list. Do **not** re-add it when `kavure` is hardened.

### 3.2 Container → host (the intra-host `INPUT` gap)

The `DOCKER-USER` block (§2) filters **forwarded** traffic only. A container calling a service on
**its own host** does not traverse it — the packet is local delivery and lands on `INPUT`, which
UFW governs (see §0.3). Fix it with a **scoped** `INPUT` allow: the Docker subnets may reach the
host, but **only on the ports the containers actually consume**.

```bash
# kuaray — the *arr cross-service ports (prowlarr / lidarr / flaresolverr / transmission / slskd).
sudo ufw allow from 172.16.0.0/12 to any port 8686 proto tcp comment 'container->host Lidarr (*arr) HB-047'
sudo ufw allow from 172.16.0.0/12 to any port 9696 proto tcp comment 'container->host Prowlarr (*arr) HB-047'
sudo ufw allow from 172.16.0.0/12 to any port 8191 proto tcp comment 'container->host FlareSolverr (*arr) HB-047'
sudo ufw allow from 172.16.0.0/12 to any port 9091 proto tcp comment 'container->host Transmission (*arr) HB-047'
sudo ufw allow from 172.16.0.0/12 to any port 5030 proto tcp comment 'container->host slskd (*arr) HB-047'

# kavure — Prometheus scrapes its OWN Node Exporter (network_mode: host → no DNAT).
sudo ufw allow from 172.16.0.0/12 to any port 9100 proto tcp comment 'container->host Node Exporter (prometheus) HB-047'
```

- **Source `172.16.0.0/12`** is the Docker private range the `DOCKER-USER` block already trusts
  (§2). It matches both `docker0` and every user-defined `br-*`, so one rule shape covers every
  network on the host. It never matches the LAN (`192.168.3.0/24`), so the LAN stays closed.
- **Scope by port — do NOT use a blanket allow.** `ufw allow in on docker0` (or `allow from
  172.16.0.0/12` with no port) would let **any** container reach **every** host socket —
  including the Docker socket proxy (`2375`), i.e. a container→Docker escalation. Keep the rule
  to the ports the stack consumes; add a new port only when a new container→host dependency
  appears. Record each rule in [`../network/ports.md`](../network/ports.md) §5.
- **Container → LAN egress stays open (HB-059).** The `INPUT` allow fixes container→**host** only:
  a container reaching the **LAN** (`192.168.3.0/24`) is a **`FORWARD`** packet and rides Docker's
  pre-existing `DOCKER-FORWARD` chain. The §2 block **trusts the Docker subnet sources** (`-s
  172.16.0.0/12 … -j RETURN`), so it does **not** filter this — verified after the fix: `soularr`
  (kuaray, default bridge) reached `192.168.3.1:80` (the ISP router's web UI), a
  **lateral-movement path** kept open for container **egress** (downloads/HTTP). Whether to keep
  or close it is a **design decision** for the owner (tracked as **HB-059**).
- **Why not move the `*arr` to a user-defined network and use service names?** That is the
  Docker-idiomatic pattern for *container↔container*, and it would also dodge the `! -i docker0`
  guard — but it **cannot** fix a `network_mode: host` service (there is no container name to
  resolve), it means editing live app config/DBs, and it fragments the fix per stack. The scoped
  `INPUT` rule fixes **both** shapes uniformly and is one reversible line per host.

## 4. Rollout order

Do **one host at a time**, verifying (§5) before moving on. Order matters — least critical first,
Swarm manager last:

1. **`psicopompo`** — ✅ **applied 2026-10-13 (step 1).** UFW was already active; the
   tailnet-aware `DOCKER-USER` block (§2) was added. It is the NAS/registry, but the change is small.
2. **`kuaray`** — ✅ **applied 2026-10-13 (step 2).** UFW enabled (`sudo ufw enable`) with
   default deny incoming; the tailnet allowance plus the §3.1 host exceptions (Syncthing `22000`,
   Samba `139/445`, xrdp `3389`) are the only LAN paths. Standby mirror. **A regression surfaced
   here the same day and was fixed — see §3.2.**
3. **`kavure`** — ✅ **applied 2026-10-13 (step 3).** It is the **Swarm manager** and the **subnet
   router** (largest blast radius). UFW was enabled (default deny incoming, `DEFAULT_FORWARD_POLICY="DROP"`),
   the Swarm ports ride the tailnet (`ufw allow in on tailscale0`), and §2/§3 were applied — verified
   live: `DOCKER-USER` carries the `100.64.0.0/10` RETURN and no `192.168.0.0/16` RETURN. **Its
   own container→host break (Prometheus → Node Exporter) was fixed the same day — §3.2.**

> ⚠️ **Step 1 correction — do not repeat the first draft (2026-10-13).** The initial `psicopompo`
> block trusted `-s 192.168.0.0/16`, which **contains the home LAN `192.168.3.0/24`** — so it closed
> nothing (LAN→published-container still passed). The line was **removed the same day** and the
> block re-verified; it is the version shown in §2. The tailnet-only outcome **requires** omitting
> it (see §2's inline warning).
>
> ✅ **`psicopompo` forward policy — DONE (2026-10-13, later the same day).** The deferred
> `DEFAULT_FORWARD_POLICY="DROP"` (§3) **was applied** to `psicopompo` (backup
> `ufw.default.2026-10-13.bak`, `ufw reload`), re-verified afterwards (tailnet `:5000`/`:9095`
> open, Swarm 3/3 `Ready`, local `:9095/v1/health` → `ok`). **All three hosts now carry `DROP`.**
> See [`../network/ports.md`](../network/ports.md) §5.

> 🐞 **Regression found in step 2 and fixed the same day — the intra-host `INPUT` gap.** `kuaray`
> is the host where it hurt: the `*arr` stack calls the host's **tailnet IP** for its cross-service
> traffic (`prowlarr → 100.94.209.99:8686`, `soularr → 100.94.209.99:8686/:5030`), and with
> `INPUT DROP` and no rule for the Docker subnets those calls **timed out** (reproduced live; the
> pre-`ufw` date of the last working call was verified). The cause is §0.3: a `docker0` container's
> packet to a host published port is **not DNAT'd** (Docker's `! -i docker0` guard), so it lands on
> `INPUT`. **The same class broke `kavure`**: Prometheus scrapes its **own** Node Exporter
> (`network_mode: host`, `100.124.146.77:9100`). **Fix: the scoped `INPUT` allow in §3.2** —
> `kuaray` (ports `8686/9696/8191/9091/5030`) and `kavure` (`9100`); verified live (container→host
> `200`/`401`, dockerproxy `2375` and the LAN-only `3389` still `000`, tailnet and LAN unaffected).
> `psicopompo` needs **no** rule — it has no container→host dependency (every own-IP reference is a
> publish directive or a `network_mode: host` healthcheck). `ybytu`/`ybyra` run nftables and do not
> exhibit the break.

> `ybytu` and `ybyra` already use nftables and are not in scope here; keep them in sync if their
> INPUT rules ever change.

## 5. Verification per host

```bash
# 1. Swarm health (kavure, and any node that is part of the cluster).
docker node ls

# 2. The subnet route still works (through kavure's subnet router).
tailscale ping 192.168.3.1

# 3. The DOCKER-USER chain carries the tailnet RETURN.
sudo iptables -S DOCKER-USER

# 4. FORWARD chain order — see §6 (the hazard).
sudo iptables -S FORWARD

# 5. A published container port is reachable over the tailnet and NOT from the LAN.
curl -sS --max-time 5 http://100.124.146.77:3000/ -o /dev/null && echo tailnet-ok
curl -sS --max-time 5 http://192.168.3.41:3000/  -o /dev/null && echo "LEAK: LAN can reach it"

# 6. Container → host (the intra-host path, §3.2): the container reaches the host service it
#    depends on, and NOT a service it must not (000 = unreachable). Run from a container on the
#    host — for kuaray use a default-bridge container (docker0) so the `! -i docker0` guard applies.
docker exec soularr   curl -sS --max-time 5 -o /dev/null -w '%{http_code}\n' http://100.94.209.99:8686/ping   # 200
docker exec soularr   curl -sS --max-time 5 -o /dev/null -w '%{http_code}\n' http://100.94.209.99:2375/_ping  # 000 (dockerproxy stays closed)
docker exec soularr   curl -sS --max-time 5 -o /dev/null -w '%{http_code}\n' http://100.94.209.99:3389/       # 000 (LAN-only host service stays closed)
```

## 6. The chain-order hazard

The relative order of **`DOCKER-USER`** and **`ts-forward`** in the `FORWARD` chain decides whether
the `DOCKER-USER` rules even see tailnet traffic. **Verified on 2026-10-13:**

| Host | Order | Effect |
|---|---|---|
| **`kavure`** | `DOCKER-USER` → `ts-forward` | `DOCKER-USER` sees tailnet→container traffic → **needs the `100.64.0.0/10` RETURN** or it is dropped. |
| **`ybyra`** | `DOCKER-USER` → `ts-forward` | Same as `kavure`. |
| `ybytu` | `ts-forward` → `DOCKER-USER` | `ts-forward` accepts `tailscale0` first → `DOCKER-USER` never sees tailnet traffic. |
| `psicopompo` | (no Docker `DOCKER-USER` traffic to the tailnet by default) | Add the block for safety. |

This order is **not stable**: it depends on the order in which Docker, UFW and `tailscaled`
install their chains after a reload or reboot. Treat it as a **race** and re-check
`iptables -S FORWARD` **after every `ufw reload`, Docker restart, or reboot**. The `100.64.0.0/10`
RETURN makes the block correct in either order — keep it unconditionally.

## 7. Rollback (one command)

- **Host firewall:** `sudo ufw disable` — instant, permissive, no reboot.
- **The `DOCKER-USER` block only:** delete the `# BEGIN UFW AND DOCKER` … `# END UFW AND DOCKER`
  section from `after.rules` and `sudo ufw reload` (or flush the chain live:
  `sudo iptables -F DOCKER-USER`).
- **Full restore:** `ufw-docker` backs up `after.rules` before editing; restore that file and
  reload. Keep a copy of the pre-change `after.rules` for the whole rollout window.

> Reboot after reload if rules do not take effect: the upstream tool documents that UFW rules
> sometimes need a reboot to bind correctly.

## 8. Wake-on-LAN: the chicken-and-egg

Hosts can be powered off; then they have no firewall to reach — but they also cannot be woken if
the **recovery path** is cut. The Wake-on-LAN relay lives at **`tailnet:9096`** (`hl-wol-relay` /
`hl-wol-dispatcher`; loopback + `tailscale serve`). Keep it reachable:

- In the ACL catalogue grant, `9096` must stay allowed (it is in
  [`tailnet-acl-runbook.md`](tailnet-acl-runbook.md) §4).
- On each host, `ufw allow in on tailscale0` covers it.
- **Never** lock `9096` behind the LAN-only rule: waking a host over the LAN is not the recovery
  path — the tailnet is.

So the recovery order is: tighten the firewall **but keep `tailnet:9096`** → if a host fails to
come back, the WoL relay is still there to wake it.

## References

- [`security-baseline.md`](security-baseline.md) — the three layers and the gaps
- [`tailnet-acl-runbook.md`](tailnet-acl-runbook.md) — the tailnet layer (and the `9096` recovery path)
- [`../network/ports.md`](../network/ports.md) — the `⚠️ defect` rows this remediation targets (HB-047)
- [`../network/topology.md`](../network/topology.md) — firewall state per host
- [`../services/wol-relay.md`](../services/wol-relay.md) — the `:9096` recovery path
- [`../backlog.md`](../backlog.md) — HB-047
- Docker + UFW: <https://github.com/chaifeng/ufw-docker>
- Docker official — packet filtering & firewalls: <https://docs.docker.com/engine/network/packet-filtering-firewalls/>
- Docker official — bridge networks / embedded DNS (user-defined networks): <https://docs.docker.com/engine/network/drivers/bridge/>
