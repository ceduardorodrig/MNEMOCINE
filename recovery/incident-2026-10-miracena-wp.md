---
tags: [homelab, recovery, miracena, kuaray, log]
---

# Incident 2026-10 — Miracena WordPress compromise

**Detected/contained:** 2026-10-29 · **Host:** kuaray · **Stack:** `/srv/data/miracena` · **Status:** RESOLVED & CLOSED (Rebuild clean 2026-10-29).

## Verdict

Compromise is **confined to the `miracena-wordpress` container and the `wordpress` MariaDB schema**.
**No evidence of lateral movement** to psicopompo, kavure, ybytu, ybyra or the tailnet (see
[Lateral-movement evidence](#lateral-movement-evidence)). The *network path* existed, though (see
[What the security baseline did not stop](#what-the-security-baseline-did-not-stop)).

## Timeline

| Date | Event |
|---|---|
| 2026-09-17 | First attacker admin (`faaxd`) created; `wp-file-manager` 8.0.4 active (likely vector) |
| 2026-09-23 | Admins 2–4, `index.php`/`manga.php`/`sushi.php`, `wp-compat` + `rzadz` plugins, `.htaccess` rewritten, Google verification file planted, `wp-login.php` modified |
| 2026-09-23→26 | SEO-spam pages served; 84 crawler hits in NPM logs |
| 2026-09-28 | Admin `lesabken` created |
| 2026-10-29 | Funnel cut (`docker stop miracena-tunnel`), WP stopped, evidence preserved, secrets rotated |

## IOCs

- Root: `index.php`, `manga.php`, `sushi.php`, `wp-login.php` (modified), `wp-config-docker.php` (should not exist).
- Core (planted): `wp-admin/images/VXz9/wp-utility.php`, `wp-admin/js/polym/MWhfN/{wp-env-setup,update}.php`, `wp-includes/blocks/embeds/SqOl/wp-links-opml.php`, `wp-includes/SimplePie/lib/Wd/sim/index.php`.
- Plugins: `wp-compat`, `rzadz` (`rzadz3.php` 2.7 MB), empty `kg4`, `wp-file-manager`.
- **mu-plugins (fake 2020–2023 mtimes):** `site-compat-layer.php` (login via `?compat=verify&user&pass`), `wp-compat-layer.php` (self-restore from `raw.githubusercontent.com/m52873473/show/.../ben`, trigger `mu_protector=regain`), `sso-loader.php`.
- DB admins: `faaxd`, `oryafboq`, `root_jn2j14h`, `admin_gm7m23j74g`, `lesabken`; `admin_email` = `0xbrettanderson@gmail.com`.

## Evidence

`kuaray:/srv/data/miracena/_quarantine/2026-10-29/` (mode 700): `docroot.tgz`, `htaccess.tgz`,
`env.redacted`, `wordpress-db.sql.gz`, `SHA256SUMS`. Pre-rotation `.env` copies live in
`kuaray:/root/miracena-env.*-20261029` (root 0600, outside the NAS-synced tree).

## Lateral-movement evidence

| Check | Result |
|---|---|
| kuaray: SSH keys, cron, timers, new units | Only own keys and `hl-*` units |
| psicopompo / kavure / ybytu / ybyra: SSH, NFS, tailscaled and kernel logs for kuaray / `miracena` (100.82.64.78) | No connection from either |
| ybyra accepted SSH logins | Only public-key, all from the homelab's own egress block 179.48.47.x |
| NFS exports kuaray can write (`configs-homelab`, `repos/git`, `media/*`, `miracena offbox`) | No webshell-like or changed-suspicious files outside the contaminated WordPress mirror |
| Host escape | WP container: not privileged, only `html` mounted, no `docker.sock` |

**Limits of this proof:** no flow logs exist for the container's NAT'd traffic; absence of log lines is strong
but not absolute evidence. Re-check after the Tailscale key is revoked.

## What the security baseline did not stop

Probe from a throwaway container on `miracena_default` (same network/NAT as WordPress):
tailnet SSH on psicopompo, kavure, ybytu, ybyra and NFS (2049) on psicopompo were **reachable**
(source becomes kuaray after NAT); Redis (no auth), Postgres and MariaDB were reachable inside the
network. `DOCKER-USER` blocks 10/8 and 172.16/12 but not the tailnet `100.64/10` or `192.168/16`.

## Root causes

1. `wp-file-manager` 8.0.4 plus an admin password in cleartext in `.env`.
2. Public Funnel to an internet-facing CMS with `latest` image tags and no pin.
3. No egress restriction from the container network to the tailnet.
4. Redis without password; `root@%` in MariaDB.

## Rotated 2026-10-29 (verified: new login OK, old refused)

MariaDB `wordpress` + `root` (root@% dropped), Postgres `miracena`/Directus `DB_PASSWORD`, Directus
`KEY`/`SECRET`/admin password, NPM admin. All mirrored in the sops store as `MIRACENA_*` (2 recipients intact).

**Resolution & Closure (2026-10-29):**
- Tailscale Auth Keys revoked in admin console by owner; `miracena` node purged from tailnet.
- `TS_AUTH_KEY` in `/srv/data/miracena/.env` revoked.
- Contaminated backups moved to `_quarantine/` (offbox and NAS mirror sane).
- MariaDB dump and WordPress file sync safely re-enabled in `/usr/local/bin/miracena-backup` targeting clean docroot.
- Redis auth enabled with `--requirepass` and authenticated healthcheck.
- Egress containment guard installed via systemd service (`hl-miracena-egress-guard.service`, HB-084).
- Least-Privilege Envs implemented across Homelab (`sumaenima-edge.env` on ybyra, `env/directus.env`, `env/n8n.env`, `env/wordpress.env` on kuaray, HB-082).
- WordPress clean rebuild deployed from scratch (`wordpress:6.6.2-php8.3-apache`, uploads `.htaccess` execution guard, `DISALLOW_FILE_EDIT`, strictly bound to Tailnet IP, HB-083).
- Hourly access audit timer deployed (`hl-access-audit.timer`) checking authorized_keys against canonical inventory across all fleet nodes.
- Tailscale Funnel re-established safely: ephemeral node `miracena` with `tag:edge` pointing strictly to Nginx Proxy Manager (NPM).
- NPM WAF configured with Split-Horizon protection: `/wp-admin` and `/wp-login.php` blocked with HTTP 403 on the public Funnel URL; `/xmlrpc.php` and `wp-config.php` return HTTP 404. Direct Tailnet administration preserved.
- StênioSentinel v4.6.0 updated with native rules: `SEC-WORDPRESS-HARDENING`, `SEC-WORDPRESS-BANNED-PLUGIN`, `SEC-COMPOSE-PINNED-IMAGE`, `SEC-COMPOSE-LEAST-PRIVILEGE-ENV`, `SEC-COMPOSE-DOCKER-SOCK-RW`. All 80 self-tests passing. Incident officially CLOSED.
