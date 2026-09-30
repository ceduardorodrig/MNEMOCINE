---
tags: [homelab, recovery, storage, psicopompo]
---

# Plano de Contingência — Troca do disco do NAS (psicopompo)

> **Status:** documentado (13/09/2026) — **NÃO executado**. Disco atual do NAS está saudável.
> **Disparar quando:** `sda` do psicopompo (NAS `/mnt/BACKUP`) apresentar **Reallocated_Sector_Ct > 0** OU **Current_Pending_Sector > 0** — igual ao caso kuaray `sdb` (1 pending → alerta `SmartDiskError` firing). Monitorado automaticamente via smartd + Prometheus.

## Contexto

O NAS do homelab é o **`sda`** do psicopompo (`ST1000LM024 HN-M101MBB`, 931.5G, SATA 2.5"). Hospeda `/mnt/BACKUP` (mídia, backups off-box, configs) + serve NFSv4 para kavure/kuaray/ybytu/ybyra.

| | Atual (`sda`, no PC) | Candidato (`sdf`, SSHD-1TB USB) |
|---|---|---|
| Modelo | ST1000LM024 (SpinPoint M8) | ST1000LM014 (Laptop SSHD) |
| Tamanho | 931.5G | 931.5G |
| Formato | 2.5" SATA interno | 2.5" SATA (hoje via leitor USB) |
| Health (13/09) | ✅ 0 realloc, 0 pending | ✅ 0 realloc, 0 pending |
| Power-on | 17.285h | 22.656h |
| Vantagem | — | **Cache NAND** (leitura repetida mais rápida) |

Ambos são 2.5" SATA — o SSHD cabe no mesmo slot interno.

## Decisão (13/09/2026)

**Não trocar agora.** O `sda` está saudável (0 reallocated, 0 pending = nenhum remapeamento em curso). O Load_Cycle alto (275k) é característico de HDD 2.5" de laptop, não é sinal de morte. O SSHD ficará como **reserva pronta** para quando o `sda` der sinais.

## Procedimento (quando necessário)

> ⚠️ Downtime de **horas** — o NAS atende 4 hosts via NFS. Programar em janela de manutenção e avisar antes.

1. **Parar os clientes NFS:** avisar/parar uso em kavure (zomboid/minecraft/valheim/media/n8n/sumaenima), kuaray (música/lidarr), ybytu/ybyra (configs).
2. **Desmontar NFS:** `exportfs -au` no psicopompo + `umount` nos clientes (opcional — `soft` evita travar).
3. **Desligar o psicopompo.**
4. **Fisicamente:** conectar o SSHD (sdf) como disco SATA interno **no lugar do sda** (mesmo slot/energia). O sda sai.
5. **Ligar com mídia de recuperação** (o SSHD vem de leitor USB, pode não ter SO).
6. **Copiar dados:** `rsync -a --info=progress2 /mnt/BACKUP/ <destino>` ou clonar via dd/Clonezilla. 289G usados → várias horas.
7. **Validar:** `smartctl -a` (0 realloc/pending no novo), `btrfs check`/`fsck`, montar `/mnt/BACKUP`.
8. **Reexportar NFS** (`/etc/exports` mantido) + `exportfs -arv`.
9. **Re-montar nos clientes** + reiniciar containers afetados (bind NFS `rprivate`).
10. **Testar:** `df` nos clientes, serviços Up, acesso à mídia.

## Alternativa menos invasiva (avaliar na hora)

Se só o **setor de dados** do NAS estiver doente mas o sistema OK, considerar **adicionar o SSHD como disco extra** e migrar `/mnt/BACKUP` para ele por rsync (sem parar o SO), depois trocar o ponto de montagem. Mesmo resultado com downtime menor.

## Referências

- Monitores: [`services/monitoring.md`](../services/monitoring.md) (alertas `SmartDiskError`) · smartd `sda` no psicopompo
- Backups: [`backups/strategy.md`](../backups/strategy.md) · [`backups/snapshots-psicopompo.md`](../backups/snapshots-psicopompo.md)
- NFS: [`network/nfs.md`](../network/nfs.md)