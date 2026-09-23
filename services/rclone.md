---
tags: [homelab, service, rclone, storage, cloud]
---

# Rclone

Cliente de cloud storage (remotes: Google Drive, etc.) — CLI + mount.

**Servidor:** psicopompo

> **26/08/2026:** **Rclone Web GUI removido** — nunca usado (só o homepage monitorava a porta, e virou conexão órfã). O `rclone-webgui.service` (Rclone Web GUI + RC daemon, `:46295`) foi desativado e o unit deletado. O daemon RC rodava `--rc-no-auth` na Tailnet — remoção também reduz superfície de ataque. **CLI/backup/mount permanecem.**

## Componentes

| Unidade (systemd --user) | Função | Status |
|---|---|---|
| `rclone-webgui.service` | Rclone Web GUI + RC daemon | ❌ **removido (26/08)** — unit deletado |
| `rclone-mount.service` | Mount do `gdrive:` em `/home/edu/Google_Drive` | ✅ ativo |

## Configuração

- Config: `/home/edu/.config/rclone/rclone.conf`
- Remote: `gdrive:` (scope `drive`)
- Mount: `/home/edu/Google_Drive`

## Comandos

```bash
# Mount Google Drive
systemctl --user start rclone-mount.service

# Reautenticar o gdrive (token expirado) — exige navegador
rclone config reconnect gdrive:
```

## Pendências

- **Reautenticar o token do `gdrive:`** — o mount falha com `couldn't find root directory ID` (token expirado). Reauth manual: `rclone config reconnect gdrive:` e depois `systemctl --user start rclone-mount.service`.

## See also
- [[psicopompo]] — Servidor

## Off-site — BACKUP MNEMOCINE (09/08/2026)

- **Sync diário** do `/mnt/BACKUP` (221G) → `gdrive:BACKUP MNEMOCINE` via `/usr/local/bin/rclone-gdrive-backup` (cron `30 6 * * *` root).
- **Scheduler:** systemd timer **`hl-rclone-gdrive-backup.timer`** (diário `06:30`, `Persistent=true` — catch-up pós-reboot). Migrado do cron em **10/08**; cronie mantido instalado (uso futuro). Ver `automations/schedules.json`.
- **Sem criptografia** (decisão do dono). Deletados vão para `gdrive:_deleted/<data>/` (`--backup-dir`) + `--max-delete 200`.
- Exclui `.stversions/**`, **`.snapshots/**` (10/08)**, `.Trash-1000/**`, `.stfolder`.
- **1º sync** (221G) em background 09/08 — leva ~1-2 dias no upload atual; depois delta diário.
- **10/08:** sync interrompido pelo **reboot (~15:46)** (log sem resumo final, sem health) e **retomado manualmente** como root (15:57) — upload do delta restante (`zomboid-server-kavure/archive/migration-20260805`). Reboot deixa o sync inacabado até a próxima rodada do timer (06:30); retomar com `/usr/local/bin/rclone-gdrive-backup` (root) quando necessário.
- **Token**: `rclone config reconnect gdrive:` — **expirado/revogado em 09/08, 16/08 e 19/08 (~7 dias cada)**. `rclone.conf` espelhado no NAS (config-backup psicopompo) p/ reconectar em qualquer máquina.

> **🔴 Causa da expiração recorrente (19/08/2026):** o app OAuth do client_id próprio (`127604679023-...apps.googleusercontent.com`) estava com *publishing status = **Testing*** no Google Cloud Console → o Google **revoga o refresh token a cada ~7 dias** (política para apps em Testing). **Solução aplicada:** app publicado como **"In production"** em 19/08 (uso pessoal <100 usuários não exige verificação; o aviso "app not verified" no login é esperado e inofensivo). Com o app em produção, o refresh token **não expira mais semanalmente**. Doc oficial rclone: o `client_id` compartilhado do rclone será aposentado em 2026 — client próprio é o caminho recomendado (já usado).
- **Monitores**: ntfy `/backup` + health `/srv/health/rclone-gdrive-last-ok` + `rclone about gdrive:` (quota 5TB) no ritual.
- Registrado em `automations/schedules.json` e `backups/backup-rituals.md`.

## 🔴 Fix: `.snapshots` NÃO pode ir pro Drive (10/08/2026)

O 1º sync **não excluía o `.snapshots`** (subvol de snapshots do snapper em `/mnt/BACKUP`). Cada snapshot contém **cópia completa do backup** → o sync explodiu de ~221G para **640 GiB** (ETA 4h+). Aplicado:

1. **`--exclude ".snapshots/**"`** adicionado ao `/usr/local/bin/rclone-gdrive-backup` (script corrigido).
2. **`purge`** do `.snapshots` remoto (`gdrive:BACKUP MNEMOCINE/.snapshots`) — **297 GiB / 21.685 arquivos** removidos (vão para a lixeira do Drive; esvazia em ~30 dias ou manual — conta na quota até lá).
3. Sync reiniciado (PID novo) sem `.snapshots` → transferiu o delta restante (~3.6 GiB de git objects + cache navidrome).
4. **Guarda de root** adicionada ao script (execução manual não-root aborta sem alerta falso — igual config-backup).

> **Lição:** snapper + rclone nunca — o off-site deve ser um espelho do estado ATUAL, não dos snapshots históricos (esses ficam no btrfs local + restic).

## 🟡 Incidente: offsite sem sync 16→19/08 (resolvido 19/08)

- **Sintoma:** token gdrive inválido (`invalid_grant: token expired or revoked`) → o script falha no fail-fast (passo 1) **antes** de tocar log/health → `/srv/health/rclone-gdrive-last-ok` parou em 16/08 06:40, apesar do timer 06:30 estar ativo. O ntfy `/backup` alertava "OFFLINE" nos dias 17 e 18.
- **Causa:** app OAuth em "Testing" (expiração de 7 dias) — ver nota acima.
- **Correção:** publicado "In production" + `rclone config reconnect gdrive:` (reauth 19/08 14:09) + `sudo /usr/local/bin/rclone-gdrive-backup` manual (sync do delta 16→19/08: **8.86 GiB / 5003 arquivos, 51 min**, checks 153.5k OK, health atualizado 19/08 14:29). Timer segue ativo (06:30).
- **Lições:** (1) monitorar a `expiry` do token no `rclone.conf` (aviso antecipado via ntfy antes de expirar); (2) se rodar o backup manual com timeout curto, o wrapper pode morrer antes do `touch` do health (o rclone filho continua — rodar de novo para finalizar health).
