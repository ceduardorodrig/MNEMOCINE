---
tags: [homelab, service, transmission, download]
---

# Transmission

Cliente de torrent leve para servidor.

**Servidor:** kuaray
**Porta Web:** `9091`
**Porta DHT:** `51413` (TCP/UDP)
**URL:** `http://kuaray.chimaera-heptatonic.ts.net:9091`

## Stack

| Container | Imagem | Função |
|---|---|---|
| transmission | linuxserver/transmission:latest | Torrent client |

## Acesso

`http://kuaray.chimaera-heptatonic.ts.net:9091`

## Integração

- Recebe downloads do Lidarr via *arr stack
- Download direto via interface web
- Limitado por banda para não saturar o servidor

## Segredos

- **RPC password** no store sops (`TRANSMISSION_RPC_PASSWORD` — valor **hash+salt** do `settings.json`; restaurar verbatim preserva a senha). O `settings.json` é **excluído** do espelho `config-backup`. Restore após wipe: `inject-secrets.sh` (ver `guides/secrets-centralizados.md`).
