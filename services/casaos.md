---
tags: [homelab, service, casaos, monitoring]
---

# CasaOS

Painel de gerenciamento do servidor kuaray — orquestração de containers e serviços.

> **⚠️ REMOVIDO (08/08/2026):** CasaOS desinstalado do kuaray (não era mais usado; SSH/docker é o suficiente). Porta 80 liberada, serviços systemd e arquivos removidos (`casaos-uninstall` + limpeza manual). Referências removidas do homepage e das docs. Esta doc fica como histórico.

**Servidor:** ~~kuaray~~ (removido)
**Porta:** ~~`8800`~~

## Serviços Systemd

| Service | Função |
|---|---|
| casaos.service | Painel principal |
| casaos-gateway.service | Proxy reverso interno |
| casaos-app-management.service | Gerenciamento de apps |
| casaos-local-storage.service | Gerenciamento de disco |
| casaos-message-bus.service | Barramento de mensagens |
| casaos-user-service.service | Gerenciamento de usuários |

## Funcionamento

O CasaOS gerencia os containers Docker do kuaray através de uma interface web simplificada. Ele substitui o Portainer como camada de gerenciamento visual neste servidor.

## Acesso

`http://kuaray.chimaera-heptatonic.ts.net:8800`

## Manutenção

```bash
systemctl status casaos.service
systemctl restart casaos-gateway.service
```
