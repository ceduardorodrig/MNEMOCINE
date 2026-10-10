---
tags: [homelab, monitoring, ntfy, tutorial, checklist]
---

# Notification Methodology (ntfy)

Rules so homelab notifications stay **actionable, readable and non-intrusive** — today and for
every new producer. Applies to every agent, session and service that publishes to ntfy.

**Server:** `ybytu:8083` · **Service doc:** [`../services/ntfy.md`](../services/ntfy.md)

## Principles

1. **An alert is a call to action.** If nobody must act, it is not a notification (it becomes a
   silent *digest* or stays on the dashboard only).
2. **One condition = one notification.** Never two producers notifying the same root cause.
3. **Anti-flap is mandatory.** Only notify after a *sustained* failure (retries/`for:`) — never on
   the first failed check.
4. **Priority = channel.** ntfy priority maps to an Android channel (sound/vibrate/popover). Only
   critical events make noise.
5. **Human-readable.** Short, specific title; body with what, where, when and an action link.
   No raw JSON, no stack traces, no label dumps.
6. **Group, don't multiply.** One cause (host down) = **one** message, not dozens.

## Notification path and single points of failure

```
                        ┌─────────────── homelab (LAN, kavure) ────────────────┐
 Prometheus (kavure) ──▶ Alertmanager ──▶ alertmanager-ntfy (bridge) ─┐
 Uptime Kuma (ybytu) ────────────────────────────────────────────────┼──▶ ntfy (ybytu:8083) ──▶ phone
 backup scripts ─────────────────────────────────────────────────────┘
                                                                          ▲
 changedetection (ybytu) ─────────────────────────────────────────────────┘
```

> ⚠️ **Single point of failure:** **ntfy runs on the same `ybytu` host as Uptime Kuma** — ybytu is
> both the *external witness* (detects the whole homelab going down) and the *notification hub*.
> If ybytu goes down, **no notification arrives at all** (not even about ybytu itself). Risk
> accepted (low likelihood), but recorded. **Optional improvement:** an external *dead-man's
> switch* (heartbeat to a third-party service) to cover exactly this case.

## Boundary: Uptime Kuma × Prometheus

Complementary layers — **not** alternatives. Do not remove one in favour of the other:

| | **Uptime Kuma** (ybytu / VPS, public IP) | **Prometheus + Alertmanager** (kavure / LAN) |
|---|---|---|
| Vantage point | **external** (independent of the homelab) | **internal** |
| Method | **black-box** synthetic (HTTP/keyword/port/ping/DNS) | **white-box** metrics (thresholds/trends) |
| Answers | "is it reachable and working from outside?" | "what is degrading and why?" |
| Whole homelab down | ✅ **the only one that detects it** | ❌ goes down with it |
| Depth (disk, RAM, backup freshness) | ❌ | ✅ |
| History/trends/dashboards | limited | ✅ (365d, Grafana) |

- **Kuma = edge/external reachability:** one ping per host, public entrypoints, DNS, certificates,
  user-facing services. **Few monitors, high signal.**
- **Prometheus = internal health:** resources, disks, systemd, containers, backups.
  (Future: `blackbox_exporter` for internal HTTP probes.)

### Deduplication candidates (decide in a future session)
Kuma monitors over **internal** tooling already covered by Prometheus — evaluate removal:
`Prometheus`, `Grafana`, `Loki`/`Alertmanager`, `n8n`, and the `backup` ones (covered by `BackupNotRun`).

## Topic contract

| Topic | Purpose | Typical priority | Producers |
|---|---|---|---|
| `alerts` | **Actionable** (down/critical) + warnings | 5 critical · 2 warning · 1 resolved | Alertmanager (via bridge), Uptime Kuma, `arm-hunt` |
| `backup` | Backup ops (failure high, OK low) | 4 failure · 2 OK | backup scripts (`config-backup`, `restic`, …) |
| `chimaera-heptatonic` | Page changes | 3 | changedetection.io |

> A new producer **only** publishes to an existing topic; creating a topic requires updating this
> table + [`ntfy.md`](../services/ntfy.md) + subscribing on the phone.

## Severity → priority matrix (ntfy ↔ Android channel)

| Severity | ntfy priority | Android behaviour |
|---|---|---|
| **critical / service down** | `urgent` (5) | sound + popover |
| **warning / degradation** | `low` (2) | silent |
| **resolved / recovery** | `min` (1) | silent |
| **info / digest** | `min` (1) | silent |

On Android each priority is a **channel** — sound/DND can be tuned per channel (e.g. `urgent`
overrides DND; `default/low/min` silent). This is configured on the phone, not on the server.

## Anti-flap (mandatory)

| Tool | Rule |
|---|---|
| **Uptime Kuma** | `maxretries ≥ 2` + `retry_interval` — only mark DOWN after N consecutive failures. Never `maxretries=0`. |
| **Prometheus** | use `for:` (≥ 5 min) on the alert — never fire on the first scrape. |
| **Alertmanager** | `inhibit_rules` + sensible `group_interval`/`repeat_interval`. |
| **Silence** | for a *known-bad* documented condition (e.g. a dying disk), with an explanatory `comment`. |
| **Kuma parent** | host as *parent* of its services → host down = 1 notification (not all of them). |

## Readability (producer standard)

- **Title:** `🚨 Fired: <summary>` / `✅ Resolved: <summary>` — the `summary` must state
  **what + where** (e.g. *"Disk /dev/sdb (kuaray) with defective sectors"*).
- **Body:** alert (name + severity) · host · start time · action link.
- **No** JSON blobs, stack traces or raw label names as the message body.
- **Link:** `X-Click` points to the relevant graph/dashboard.

## Digest & quiet hours

- **Batch informational output:** routine successes (e.g. backups OK) can be consolidated into a
  **single daily digest** instead of N messages (planned for `/backup`).
- **Quiet hours:** handled by Android channels (priority), not by disabling alerts.

## Adding a producer (checklist)

1. Does a topic exist for it in the **topic contract**? If not, justify and update the doc.
2. Which **severity/priority**? Apply the matrix (warning must **not** make sound).
3. Is there **anti-flap** (retries/`for:`)? Without it, it does not go to production.
4. Is the **title + body readable** (what, where, when, link)?
5. Does it **duplicate** an existing alert (check Kuma × Prometheus × scripts)?
6. Fire a **test notification** and verify title/priority on the phone.
7. Document it in `services/ntfy.md` (topic table) and in the service doc.

## Recurring audit

- [ ] Any producer at `maxretries=0` or without `for:`?
- [ ] Any condition with **two** producers notifying?
- [ ] Is the `/alerts` volume over the last 24h compatible with "few and actionable"?
- [ ] Any `warning` notification making sound (wrong priority)?
- [ ] Known-bad silences with `comment` and an expiry?

```bash
# recent volume per topic (ntfy in-memory cache)
curl -sS 'http://ybytu:8083/alerts/json?poll=1' | wc -l
```

## History and regressions

- **09/10/2026 — Uptime Kuma flood:** 100 messages in 4h37, 36 monitors flapping. Cause:
  **`maxretries=0`** (one failed check = DOWN) plus transient timeouts to kavure. Fixed to
  `maxretries=2` across all 51 monitors.
- **09/10/2026 — raw webhook in `/alerts`:** Alertmanager published the **raw JSON** (no
  template). Fixed with the `alertmanager-ntfy` bridge + severity-based priority.
- **09/10/2026 — `inhibit_rules`:** Alertmanager had **0** inhibition rules → a host down
  produced dozens of alerts. Two added (NodeDown/n8nDown inhibit the generic one; NodeDown
  inhibits the rest of the host).

## See also
- [`../services/ntfy.md`](../services/ntfy.md) — server, topics, integrations
- [`../services/monitoring.md`](../services/monitoring.md) — Alertmanager + bridge
- [`../services/uptime-kuma.md`](../services/uptime-kuma.md) — monitors and retries
