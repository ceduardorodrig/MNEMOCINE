---
tags: [homelab, service, punktfunk, gaming, psicopompo]
---

# Punktfunk

Streaming de jogos/desktop de baixa latência — host + clientes nativos.

**Servidor:** psicopompo
**Porta Host:** `UDP 9777` (punktfunk/1 QUIC)
**Porta Console:** `TCP 47992, 47993` (web console)
**URL Console:** `https://psicopompo:47992`

## Stack

| Componente | Tipo | Função |
|---|---|---|
| punktfunk-host | Serviço systemd user | Host de streaming (NVENC, virtual displays) |
| punktfunk-web | Serviço systemd user | Console web (TanStack, gerenciamento) |
| punktfunk-scripting | Serviço systemd user | Runner de plugins/scripts (bun) |

## Portas

| Porta | Protocolo | Função |
|---|---|---|
| 9777 | UDP | punktfunk/1 QUIC (controle nativo) |
| 5353 | UDP | mDNS discovery |
| 47990 | TCP | Management API (HTTPS, mTLS/bearer) |
| 47992 | TCP | Web console (HTTPS, login-gated) |
| 47993 | TCP | Plugin interfaces |

## Acesso

- **Console:** `https://psicopompo:47992` (via LAN ou Tailscale)
- **Primeiro acesso:** Gerar PIN de pareamento no console
- **Cliente Android:** Google Play → "Punktfunk" → descobrir host → parear com PIN
- **Cliente Linux:** `sudo pacman -Syu punktfunk-client` ou Flatpak
- **Moonlight:** Compatível (ativar `PUNKTFUNK_GAMESTREAM=1` em `host.env`)

## Configuração

- **host.env:** `~/.config/punktfunk/host.env`
- **GameStream:** Desativado por padrão (ativar com `PUNKTFUNK_GAMESTREAM=1`)
- **HDR:** Indisponível com KDE Plasma (SDR 8-bit apenas; HDR requer gamescope ou GNOME 50+)
- **Linger:** Ativo (serviços rodam sem sessão de login)
- **Grupo input:** Adicionado (gamepads virtuais via `/dev/uinput`)

## Firewall

```bash
sudo ufw allow punktfunk-native   # UDP 9777, 5353, TCP 47990
sudo ufw allow punktfunk-web      # TCP 47992, 47993
```

## Manutenção

- **Update:** `sudo pacman -Syu punktfunk-host punktfunk-web punktfunk-scripting`
- **Restart:** `systemctl --user restart punktfunk-host punktfunk-web`
- **Logs:** `journalctl --user -u punktfunk-host -f`
- **Status:** `systemctl --user status punktfunk-host punktfunk-web punktfunk-scripting`

## See also

- [[psicopompo]] — servidor host
- [[psicopompo-gaming]] — configuração Steam/Proton no Linux
- [Documentação oficial](https://docs.punktfunk.unom.io)
- [GitHub](https://git.unom.io/unom/punktfunk)

## Nota: sinks HDMI duplicados (GB207)

A placa de áudio NVIDIA GB207 do psicopompo gera 6 sinks HDMI duplicados no PipeWire (todos para o mesmo monitor C24F390). **Não é bug do Punktfunk** — comportamento do driver NVIDIA. Resolvido desabilitando a placa via WirePlumber (ver [[psicopompo#Áudio — GB207 HDMI desabilitado]]). O Punktfunk usa dispositivos virtuais próprios (`punktfunk-speaker-*`, `punktfunk-mic`) e não é afetado.
