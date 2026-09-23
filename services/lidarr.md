---
tags: [homelab, service, lidarr, media, download, kuaray]
---

# Lidarr

Gerenciamento e download automático de música.

**Servidor:** kuaray
**Porta:** `8686`
**URL:** `http://kuaray.chimaera-heptatonic.ts.net:8686`

## Stack

| Container | Imagem | Função |
|---|---|---|
| lidarr | linuxserver/lidarr:latest | Gerenciamento de biblioteca musical |
| transmission | linuxserver/transmission:latest | Download por torrent (Prowlarr) |
| prowlarr | linuxserver/prowlarr:latest | Indexers |
| soularr | mrusse08/soularr:latest | Ponte Lidarr → Soulseek |
| slskd | slskd/slskd:latest | Cliente Soulseek |
| navidrome | deluan/navidrome:latest | Leitor da biblioteca |

## Fluxo físico dos arquivos (importante)

```
1) DOWNLOAD — disco LOCAL do kuaray (/dev/sdb1)
   - Transmission  → /mnt/storage/data/torrents/lidarr/      (torrents via Prowlarr)
   - slskd/soularr → /mnt/storage/data/downloads/soulseek/   (Soulseek)
   ├── rápido (disco local), porém /dev/sdb1 = HD com histórico de bad sectors (dados transitórios)

2) IMPORT AUTOMÁTICO (Lidarr) — copy+delete cross-filesystem
   - soularr dispara DownloadedAlbumsScan / ProcessMonitoredDownloads
   - move /mnt/storage/data/{torrents,downloads}/<álbum>
     → /mnt/storage/data/media/music/<artist>/<álbum>   (= NFS → psicopompo)

3) BIBLIOTECA — HD do psicopompo (btrfs, saudável)
   - /mnt/BACKUP/media/music  (NFS export, montado no kuaray em /data/media/music)
   - Navidrome lê daqui; Syncthing (folder `backup`) espelha p/ kuaray
```

> ⚠️ **Sem hardlinks/atomic move:** downloads (kuaray) e biblioteca (NFS/psicopompo) estão em **filesystems diferentes** → todo import é **copy+delete sobre NFS** (lento). Isso é um **trade-off deliberado**: a biblioteca foi movida pro NAS porque o HD do kuaray tem bad sectors. Ver [`network/nfs.md`](../network/nfs.md) (nota de performance/WiFi).

## Caminhos internos (containers)

| Container | Mount | Host (kuaray) |
|---|---|---|
| lidarr | `/config` | `/DATA/AppData/lidarr/config` |
| lidarr | `/data` | `/mnt/storage/data` (enxerga downloads + música) |
| lidarr | `/data/torrents` | `/mnt/storage/data/torrents` |
| transmission | `/data/torrents` | `/mnt/storage/data/torrents` |
| slskd | `/app/downloads` | `/mnt/storage/data/downloads/soulseek` |
| soularr | `/downloads` | `/mnt/storage/data/downloads/soulseek` |
| navidrome | `/music` | `/mnt/storage/data/media/music` |

- **Root folder do Lidarr:** `/data/media/music` (= NFS → psicopompo).
- **Download client Transmission:** host `100.94.209.99:9091`, urlBase `/transmission/`, categoria `lidarr` → downloads em `/data/torrents/lidarr/`. **Não há remote path mapping** (Lidarr e Transmission na mesma máquina).
- **Soularr:** `config.ini` em `/DATA/AppData/soularr/config/` (hosts/api_keys) — ver [`soularr-slskd.md`](soularr-slskd.md).

## Funcionamento (automático)

1. Artista marcado como monitored no Lidarr → álbuns faltantes viram `wanted/missing`.
2. **Soularr** (a cada 5 min) lê o wanted/missing, busca no Soulseek, enfileira no slskd e, ao completar, dispara o import no Lidarr.
3. **Lidarr + Prowlarr + Transmission** cobre torrents (RSS/search) — sujeito a rate-limit dos indexers (TPB/Knaben → desabilita temporariamente, auto-recupera).
4. Import move para a biblioteca NFS; Navidrome consome.

**Únicos passos manuais:** adicionar artistas e, quando um download ruim vai pro denylist do soularr, limpar o `failed_imports.json` (ver `soularr-slskd.md`).

## Troubleshooting

- **`/data/torrents/lidarr` "does not appear to exist"**: o diretório precisa existir no host (`/mnt/storage/data/torrents/lidarr`, dono `kuaray:kuaray`) — é o destino da categoria do Transmission. Se o aviso persistir na UI, revalidar o client (test) ou reiniciar o container.
- **Rescans completos (`RescanFolders`) penduram no WiFi**: a biblioteca NFS via link WiFi do kuaray é lenta/instável (3,6 MB/s). Evitar rescan completo; usar `RefreshArtist` pontual (também lento, mas progride). Quando houver **cabo de rede** no kuaray, um rescan limpo reconcilia o DB.
- **Álbum `0/x` no DB mas arquivos no disco**: reconciliação pendente do rescan (estado do DB oscila com NFS lento). Arquivos intactos; Navidrome toca normalmente.
- **`Artist with ID 0` no ManualImport**: payload da API exige `artistId` + `albumReleaseId` (além de `albumId`/`trackIds`) — ver `soularr-slskd.md`.
- **Import lento**: copy+delete via NFS/WiFi; ver `network/nfs.md` (async + cabo).

## Histórico relevante

- **2026-08-07:** limpeza geral — 131 torrents mortos removidos do Transmission, fila zerada, duplicatas/`failed_imports` apagadas, `failed_imports.json` (denylist) limpo, imports manuais via API (Damien Rice 9, Pink Floyd), soularr destravado.

## Segredos

- **API key** no store sops (`LIDARR_API_KEY`, 32-char — fonte `config.xml` `<ApiKey>`). O `config.xml` é **excluído** do espelho `config-backup` (nunca vai pro NAS). Restore após wipe: `inject-secrets.sh` (ver `guides/secrets-centralizados.md`).
