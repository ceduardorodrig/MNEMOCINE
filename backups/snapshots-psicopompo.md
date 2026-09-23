---
tags: [homelab, backup, snapshot, snapper, btrfs, psicopompo]
---

# Snapshots btrfs — psicopompo (snapper)

> Proteção anti-deleção acidental / "tempestade de deleção" dos discos do psicopompo.
> **Snapshot NÃO é backup** (mesmo disco) — é "voltar no tempo". O backup real está em `config-backup.md` + restic + Syncthing + off-site.

## Configs ativas (padronizado 06/09/2026)

> **Regra de ouro:** disco **reconstruível** → **sem** snapshot (só consome espaço/I/O); disco **não reconstruível** → timeline anti-deleção. Alinhado ao ArchWiki (timeline p/ dados de usuário; **não** p/ cache) e ao CachyOS (root padrão; demais subvolumes só com config explícita).

| Config | Subvolume | Conteúdo | Classificação | Timeline |
|---|---|---|---|---|
| `root` | `/` (subvol `@`) | Sistema | Sistema (padrão CachyOS) | desligada (snap-pac) |
| `nvme` | `/mnt/NVME_PCI` (toplevel) | vault, Docker, games, repos | Misto (**vault** não reconstruível) | ✅ 8/7/4/3 |
| `backup` | `/mnt/BACKUP` (toplevel) | NAS: mídia, backups, configs | **Não reconstruível** | ✅ 4/7/4/0 |
| ~~`hdd`~~ | ~~`/mnt/HDD_SATA`~~ | ~~Steam~~ | Reconstruível | ❌ removida 06/09 |
| _(sem config)_ | `/mnt/SSD_SATA` | cache Scryfall (kavure) | Reconstruível | ❌ sem config |

- **`root`**: snapshots pre/post automáticos em todo `pacman -Syu` via **snap-pac** (hooks). Boot/restore pelo menu **Limine** (limine-snapper-sync).
- **`nvme`/`backup`**: timeline horária (timer `snapper-timeline.timer` ativo) — protege vault, configs espelhadas, backups e dados.
- **`hdd` removida (06/09):** HDD_SATA = SteamLibrary (306G) — reconstruível, não merece snapshot. Config + 16 snapshots + `.snapshots` apagados (`snapper -c hdd delete-config`).
- **`ssd` sem config:** SSD_SATA = `@scryfall` (cache Scryfall p/ kavure) — reconstruível.
- **qgroups**: desabilitadas (sem lentidão). **Swap**: zram (ativo, pri 100) + swapfile `/swap` 48G (hibernação, pri 1) — subvolume `/swap` é **irmão de `/@`** (top-level), fora dos snapshots do `root`. **updatedb**: `.snapshots` em `PRUNENAMES`.

## Comandos

```bash
sudo snapper list-configs
sudo snapper -c nvme list
sudo snapper -c nvme create -c number --description "antes de X"   # manual
sudo snapper -c nvme delete <n>                                    # remover
# verificar órfãos (snapshots no disco fora do controle do snapper):
sudo btrfs subvolume list -o /mnt/NVME_PCI/.snapshots
```

## Restore

- **Arquivo/pasta**: copiar de um snapshot sem derrubar nada:
  ```bash
  sudo cp -a /mnt/NVME_PCI/.snapshots/<N>/snapshot/<caminho> <destino>
  ```
- **Subvolume inteiro de dados** (NVMe/BACKUP, em uso): parar serviços que usam → criar snapshot rw a partir do RO → trocar o subvolume → validar → start. Ver ArchWiki Snapper.
- **Root**: bootar o snapshot pelo menu Limine → diálogo de restore do limine-snapper-sync → reboot. (Cuidado: snapshot de kernel não é bootável — CachyOS wiki.)

## Observações

- **O `nvme` pinna dados Docker (importante):** o subvolume `/mnt/NVME_PCI` contém `containerd-data`/`docker-data`. Snapshots timeline **seguram (reflink) os extents** — ao podar o Docker, o espaço só volta ao `df` depois de apagar os snapshots antigos (`snapper -c nvme delete --sync <n>`). Em 06/09/2026 foram apagados 18 snapshots antigos (17 pré-limpeza + `snapshot-inicial-vault` #1) liberando ~110GB; restaram só 2 timeline recentes. Snapshots de dados Docker (reconstruíveis) não têm valor de rollback — deletar sem dó. Ver [`guides/docker-disk-cleanup.md`](../guides/docker-disk-cleanup.md).
- O mount NFS do kavure pode exibir o path antigo do export no `mountinfo` — é só rótulo cosmético; os dados caem no destino certo.
- Ajustar retenção: `sudo snapper -c nvme set-config TIMELINE_LIMIT_HOURLY=10 ...` (ver `snapper-configs(5)`).
