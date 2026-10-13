---
tags: [homelab, meta, tutorial, todo]
---

# Backlog Routine — Keeping the "Single Source" Alive

> The homelab backlog is split in two files: the **active queue**
> ([`../backlog.md`](../backlog.md)) and the **history**
> ([`../backlog-archive.md`](../backlog-archive.md)). This runbook defines the **linkage
> contract** that keeps them honest, the **rules** StenioSentinel enforces, and the **weekly
> routine** that nudges a review.

## Why a routine exists

Pending work used to live **hidden** inside each server/service note. The natural failure
mode was silent: nobody re-reads twelve notes, so items were forgotten, then rediscovered,
then duplicated. Moving everything into one index only fixes this while **both sides stay in
sync** — an index nobody updates simply becomes a *second*, disconnected list.

The second failure mode is the **opposite** one: an index that only ever grows. If closed
items stay in the queue forever, the list becomes a history book nobody reads and the
`pending:` field ends up listing work that is already done. So the queue stays **lean**
(only what is still open) and the history moves to the **archive** — which is also what makes
a **recurrence** visible ("this is the same problem again").

## The two-file model

| File | Holds | Role |
|---|---|---|
| [`backlog.md`](../backlog.md) | `open` · `in progress` · `blocked` | The **queue** — the priority. |
| [`backlog-archive.md`](../backlog-archive.md) | `resolved` · `discarded` (with date) | The **history** — the memory. |

**Invariant:** an `HB-xxx` lives in **exactly one** of the two files.

## The linkage contract

Two sides must agree, in both directions:

| Side | Lives in | Carries |
|---|---|---|
| **Index** (the list) | `backlog.md` / `backlog-archive.md` | one row per item: `ID · Item · Ref · Sev · State · Origin` (queue) / `… · Closed · Recurred-by` (archive) |
| **Detail** (the truth) | the area document | frontmatter field `pending: [HB-xxx, ...]` |

- The **index** points at the document via its `Ref` column.
- The **document** points back at the item via `pending:` — but **only while the item is open**.
  When an item is archived, its id **leaves** the document's `pending:` (the archive keeps the
  history).
- The **technical detail** (symptoms, commands, evidence) stays in the document — the index
  holds only the summary, the severity and the lifecycle state.

Because the **columns are read from the table header**, the layout can evolve (e.g. the
`Recurrence` column) **without touching the engine**.

## Recurrence — "this is the same problem again"

When a closed problem comes back, do **not** reopen the archived row. Open a **new** item in
the queue and pin the edge in **both** files:

```text
queue:   | **HB-019** | eno1 drops again | … | 🔵 | open | 2026-10-15 | ↻ HB-007 |
archive: | **HB-007** | eno1 drops       | … | 🔵 | resolved | 2026-10-12 | HB-019 |
```

- `Recurrence` (queue) points at the **archived** item; `Recurred-by` (archive) points at the
  **open** one. The engine verifies the pair (`DOC-BACKLOG-RECURRENCE`) — a memory is not
  evidence, a link is.
- **Finding** a recurrence is dynamic: `stenio --backlog --search <term>` greps the queue **and**
  the archive — a hit in **both** is a recurrence.

## Rules enforced by StenioSentinel

Run `stenio --scope homelab` (the backlog is also audited inside `--scope all`):

| Rule | Base severity | Catches |
|---|---|---|
| `DOC-BACKLOG-DRIFT` | **adapted** (see below) | a `Ref` pointing to a missing document; an **active** item's document not declaring it; a document declaring an id the queue lacks (or declaring an **archived** id) |
| `HOMELAB-BACKLOG-MALFORMED` | Warning | a row missing its `Ref`, an unknown severity, an invalid state, or a table with no recognizable header |
| `HOMELAB-BACKLOG-LIFECYCLE` | Warning | a closed item (`resolved` / `discarded`) with no closing date |
| `HOMELAB-BACKLOG-STATE` | Warning | an id in **both** files, or an item whose state does not match its file (a closed state in the queue, an active state in the archive) |
| `DOC-BACKLOG-RECURRENCE` | **adapted** | a `Recurrence` / `Recurred-by` pair that does not agree |

**Adaptive severity** — a traceability drift inherits the severity of the item it belongs to:

| Item severity | Traceability drift |
|---|---|
| 🔴 critical | **ERROR** (blocks `stenio --gate`) |
| 🟡 medium · 🔵 low · 💡 idea | **WARNING** (visible, non-blocking) |

A drift on an unknown ID (a document declaring `HB-999` that neither file contains) is always a
Warning — nobody can grade an item that does not exist. There is **no** `stenio-ignore` escape:
fix the link instead.

## The weekly routine

`hl-backlog-report.timer` runs **Mondays 09:00** (persistent) and does two things:

1. audits the traceability with `stenio --scope homelab`;
2. pushes a short digest to ntfy **`/alerts`**: open items by severity, the oldest open item,
   and any traceability drift.

- Script: `MNEMOCINE-OPS/provisioning/scripts/hl-backlog-report`
- Units: `MNEMOCINE-OPS/provisioning/systemd/hl-backlog-report.{service,timer}`
- Installed on `psicopompo` (`/usr/local/bin/`, `/etc/systemd/system/`).
- **Priority = channel** ([`notification-methodology.md`](notification-methodology.md)): the
  digest is informational → `min` (silent); a traceability drift raises it to `low` (still
  silent). It never makes noise — an *open* item is known state, not a new alert.

The digest is the **review trigger**, not the review: open the backlog, reassess severity,
close what finished, and promote ideas.

## Adding an item

1. Pick the next free `HB-xxx` and add a row to the queue table:

   ```text
   | **HB-026** | one-line symptom | [`services/foo.md`](services/foo.md) | 🟡 | open | 2026-10-12 — ntfy alert | — |
   ```

2. Declare it in the target document's frontmatter:

   ```yaml
   ---
   tags: [homelab, service, foo, ybytu]
   pending: [HB-026]
   ---
   ```

3. Write the **technical detail** in the document (not in the index).

## Closing an item

1. Mark the row `resolved` **with the date** and update the `Origin` cell
   (e.g. `2026-10-12 — threshold raised to >100`).
2. **Move the row** to [`../backlog-archive.md`](../backlog-archive.md) — it leaves the queue.
3. **Remove the id** from the document's `pending:` list.
4. Update the technical document in the same step.

## Manual runs and troubleshooting

```bash
# The audit alone
stenio --scope homelab --path /mnt/NVME_PCI/agentic-ai

# The queue, and a search across queue + archive
stenio --backlog
stenio --backlog --search "eno1 drops"

# The digest, without waiting for Monday
sudo systemctl start hl-backlog-report.service
journalctl -u hl-backlog-report.service -n 40 --no-pager

# A rule's rationale and examples
stenio --explain DOC-BACKLOG-RECURRENCE
```

| Symptom | Cause | Fix |
|---|---|---|
| `DOC-BACKLOG-DRIFT` on a doc | the document lost (or never had) its `pending:` field while the item is open | add `pending: [HB-xxx]` |
| `DOC-BACKLOG-DRIFT` on the index | `Ref` points at a moved/renamed file, or the doc declares an **archived** id | fix the `Ref` path, or drop the archived id from `pending:` |
| `HOMELAB-BACKLOG-MALFORMED` | a row is missing a column value, or the table header is gone | complete the row / restore the header |
| `HOMELAB-BACKLOG-STATE` | an id in both files, or a closed row left in the queue | move the row to the archive (or back to the queue) |
| `DOC-BACKLOG-RECURRENCE` | a `Recurrence` / `Recurred-by` pair does not agree | make the pair point at each other |
| Digest never arrives | timer inactive, or ntfy topic wrong | `systemctl list-timers hl-backlog-report.timer` |

## References

- [`../backlog.md`](../backlog.md) — the active queue (governance, severity, states)
- [`../backlog-archive.md`](../backlog-archive.md) — the history of closed items
- [`../AGENTS.md`](../AGENTS.md) — mandatory homelab agent conventions
- [`../services/ntfy.md`](../services/ntfy.md) — notification topic contract
- [`oracle-arm-capture.md`](oracle-arm-capture.md) — the ARM item (`HB-007`/`HB-008`) as a worked example
