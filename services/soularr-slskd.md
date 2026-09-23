---
tags: [homelab, service, soularr, slskd, lidarr, media, download, kuaray]
---

# Soularr + Slskd

Download de música via Soulseek — alternativa para músicas não encontradas em torrents públicos (Prowlarr/Transmission).

**Servidor:** kuaray
**URL:** `http://kuaray.chimaera-heptatonic.ts.net:5030` (slskd) · `:8265` (soularr)

## Stack

| Container | Imagem | Porta | Função |
|---|---|---|---|
| slskd | slskd/slskd:latest | `5030` | Cliente Soulseek (baixa arquivos) |
| soularr | mrusse08/soularr:latest | `8265` | Ponte Lidarr → Soulseek (a cada 5 min) |

## Fluxo (como a música chega no Lidarr)

```
Lidarr (wanted/missing)
   │  soularr consulta a cada 5 min
   ▼
soularr  ── busca no Soulseek ──►  slskd ── baixa ──►  /data/downloads/soulseek/
   │                                                       (bind kuaray)
   │  download completo → dispara "DownloadedAlbumsScan"
   ▼
Lidarr importa de /data/downloads/soulseek/<álbum>
   ▼
/data/media/music  (root folder = NFS → psicopompo /mnt/BACKUP/media/music)
```

1. Soularr lê o wanted/missing do Lidarr (porta `8686`, api_key do `config.xml`).
2. Busca no Soulseek via API do slskd (`:5030`, api_key da bridge).
3. Slskd baixa para `/app/downloads/` = `/mnt/storage/data/downloads/soulseek/` (bind).
4. Ao completar, soularr aciona o **DownloadedAlbumsScan** do Lidarr apontando a pasta.
5. Lidarr importa para o root folder `/data/media/music` (NFS → psicopompo) e o Navidrome consome.

## Paths e mounts

| Container | Mount | Host (kuaray) |
|---|---|---|
| slskd | `/app/downloads` | `/mnt/storage/data/downloads/soulseek` |
| soularr | `/downloads` | `/mnt/storage/data/downloads/soulseek` |
| lidarr | `/data` | `/mnt/storage/data` (enxerga a mesma pasta como `/data/downloads/soulseek`) |

Configs:
- slskd: `/DATA/AppData/slskd/slskd.yml` + `/DATA/AppData/slskd/data/`
- soularr: `/DATA/AppData/soularr/config/config.ini` (hosts, api_keys, `rename_tracks`) + `soularr.log` + `failed_imports.json`

## Denylist de imports falhados (`failed_imports.json`)

- Quando o import automático falha, soularr **move a pasta** para `failed_imports/` e **denylista** o álbum (não tenta de novo automaticamente).
- Falhas comuns (download do Soulseek não casa exato com o álbum):
  - **`Has missing tracks`** — download incompleto (faltam tracks do álbum).
  - **`Has unmatched tracks`** — arquivos extras/duplicados que não casam (discos múltiplos, bonus).
  - **Álbum errado** — download que não é a obra (ex: "Flying Lotus - 1983" continha o álbum *Pooh - Tropico del nord*).
- Para destravar: remover a entrada do `failed_imports.json` (o soularr volta a tentar) e apagar a pasta de `failed_imports/`.
- Limpar o denylist inteiro é seguro: álbuns completos saem do wanted (soularr não re-busca) e álbuns parciais voltam a ser re-buscados para completar.

## Import manual via API (referência)

O comando `ManualImport` do Lidarr exige **todos** os campos por arquivo — omitir causa `Artist with ID 0 does not exist`:

```json
POST /api/v1/command
{
  "name": "ManualImport",
  "importMode": "move",
  "replaceExistingFiles": true,
  "files": [{
    "path": "/data/downloads/soulseek/<álbum>/01 - Track.flac",
    "artistId": 47,
    "albumId": 326,
    "albumReleaseId": 4206,
    "trackIds": [56103],
    "quality": {"quality": {"id": 10, "name": "FLAC"}, "revision": {"version": 1, "real": 0, "isRepack": false}},
    "indexerFlags": 0,
    "disableReleaseSwitching": false
  }]
}
```

- Preview (leitura, sem importar): `GET /api/v1/manualimport?folder=/data/downloads/soulseek/<álbum>` — retorna arquivos, `tracks` casadas, `quality` e `rejections`.
- Usar `trackIds` explícitos permite import **parcial** (álbum continua monitored → soularr completa depois).
- Arquivos sem `tracks` no preview (duplicatas) devem ser **pulados** — não incluir no payload.
- Import via API pode ser **lento** (cópia para o NFS): comandar e aguardar o status (`GET /api/v1/command/{id}`) até `completed`.

## Troubleshooting

- **"Indexer disabled till ... 429"** no log do Lidarr: limite de requisições do Prowlarr (TPB/Knaben). Disable automático; volta sozinho.
- **"Artists' root folder (/data/media/music) doesn't exist"**: se a pasta realmente existe, é aviso transiente (NFS). Verificar com `docker exec lidarr ls /data/media/music`.
- **Transmission "No data found"**: torrents a 100% cujos dados foram limpos do HD (já importados). Remover do Transmission.
- **Pastas presas na raiz do soulseek**: downloads órfãos que soularr ignora (álbum denylisted ou download não-iniciado por soularr). Mover para `failed_imports/` ou importar manualmente.
- **⚠️ Nunca apagar uma pasta de download enquanto o Lidarr está importando** — o import usa `move` + `replaceExistingFiles` e pode deletar arquivos da biblioteca no meio (lição do incidente do 2ª Via em 07/08/2026).

## Histórico relevante

- **2026-08-07**: limpeza geral — duplicatas removidas do `failed_imports/`; imports manuais via API de Damien Rice 9 (11/11) e Pink Floyd A Saucerful of Secrets (7/7); denylist limpo e soularr reiniciado (destravou fila). Álbuns parciais (Massive Attack Collected, Gorillaz Demon Days) re-baixados automaticamente pelo soularr para completar.
