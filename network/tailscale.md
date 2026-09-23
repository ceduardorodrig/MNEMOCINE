---
tags: [homelab, network, tailscale]
---

# Tailscale

**Tailnet:** chimaera-heptatonic.ts.net

## Máquinas na Tailnet

| Máquina | IP Tailscale | Papel |
|---|---|---|
| psicopompo | `100.82.51.112` | Dev + GPU workers (StênioBOT) |
| ybytu | `100.115.253.109` | Exit Node, DNS |
| ybyra | `100.66.224.34` | Cloud — borda primária |
| kuaray | `100.94.209.99` | Multimídia — Funnel Home Assistant |
| kavure | `100.124.146.77` | Servidor de serviços dedicado (Project Zomboid, painel, aiostreams, comet) |
| anansi | `100.71.232.79` | Android |

## Padrão de Acesso (Tailscale SSH)

**Método padrão de acesso aos servidores: Tailscale SSH** — usa autenticação da tailnet (WireGuard), sem expor porta 22 à internet.

```bash
tailscale ssh kavure@kavure
tailscale ssh root@kuaray
tailscale ssh ubuntu@ybyra
```

### Check mode (reauth periódica)

A **ACL padrão** do Tailscale usa `action: check` para conectar aos **próprios dispositivos** → pede **reautenticação no navegador a cada 12h** (`checkPeriod` default). É comportamento esperado.

- **Para usuários:** ok (confirmar no navegador a cada 12h).
- **Para agentes de IA/automação headless:** não conseguem clicar no link → resolver com regra **`action: accept`** na ACL (sem check) para o host do agente → `dst`. Ex:

```json
"ssh": [
  {
    "action": "accept",
    "src": ["user:ceduardorodrig@gmail.com"],
    "dst": ["tag:server"],
    "users": ["autogroup:nonroot"]
  }
]
```

### Fallback: SSH clássico com chave

Quando o Tailscale SSH não for viável (ex: automação, ferramenta que precisa de chave), usar **SSH clássico com chave por host** — padrão do repo (`~/.ssh/config` no psicopompo):

```
Host kavure
    HostName 100.124.146.77
    User kavure
    IdentityFile ~/.ssh/id_ed25519
    PreferredAuthentications publickey
```

> **IP fixo na LAN não é necessário** — o IP da tailnet (100.x) é fixo e estável, independente de DHCP.

## Exit Nodes

| Servidor | Status | Tráfego |
|---|---|---|
| psicopompo | ❌ (não oferece) | — |
| ybytu | ✅ Ativo (**único** exit node) | Tráfego da tailnet |

### Uso

Em qualquer máquina cliente da tailnet:

```bash
# Listar exit nodes disponíveis
tailscale exit-node list

# Usar ybytu como exit node (único exit node da tailnet)
tailscale set --exit-node=ybytu

# Parar de usar exit node
tailscale set --exit-node=
```

## Funnels

Funnels expõem serviços locais publicamente (via Tailscale) sem precisar abrir portas no roteador.

| Servidor | Funnel | Serviço Interno |
|---|---|---|
| kavure | `kavure.chimaera-heptatonic.ts.net:10000` | AioStreams (`kavure:3000`) |
| sumaenima (tunnel) | `sumaenima.chimaera-heptatonic.ts.net` | StênioBOT (via tunnel `sae-edge_tunnel`, proxy p/ `api:9090` no kavure) |
| miracena (tunnel) | `miracena.chimaera-heptatonic.ts.net` | WordPress (via tunnel `miracena-tunnel`, proxy p/ NPM `:80` → WordPress `:8085`) |

> **Home Assistant** é acesso **tailnet-only**: `http://100.124.146.77:8123`. Sem Funnel público — acesso restrito à tailnet por segurança.

### Configurar um Funnel

```bash
# Expor serviço local via funnel
tailscale funnel --bg 443 [--set-path /] http://localhost:PORTA

# Ver status
tailscale funnel status

# Remover
tailscale funnel off
```

### Tailscale Tunnel (container Docker)

Para serviços que precisam de um hostname próprio no Tailscale (ex: `miracena.chimaera-heptatonic.ts.net`), criar um container Tailscale dedicado:

```yaml
# Exemplo: miracena-tunnel
tunnel:
  image: tailscale/tailscale:latest
  container_name: miracena-tunnel
  hostname: miracena
  environment:
    - TS_AUTH_KEY=${TS_AUTH_KEY}
    - TS_HOSTNAME=miracena
    - TS_SERVE_CONFIG=/etc/tailscale/serve.json
    - TS_STATE_DIR=/var/lib/tailscale
    - TS_USERSPACE=false
  volumes:
    - ./tailscale:/etc/tailscale
    - tailscale_state:/var/lib/tailscale
  cap_add: [NET_ADMIN, SYS_MODULE]
  sysctls:
    - net.ipv4.ip_forward=1
    - net.ipv6.conf.all.forwarding=1
```

O `serve.json` define como o Funnel roteia o tráfego:

```json
{
  "TCP": { "443": { "HTTPS": true } },
  "Web": {
    "${TS_CERT_DOMAIN}:443": {
      "Handlers": { "/": { "Proxy": "http://servico:porta" } }
    }
  },
  "AllowFunnel": { "${TS_CERT_DOMAIN}:443": true }
}
```

**Limitação:** Tailscale MagicDNS não suporta subdomínios (`site.miracena.xxx` não resolve). Cada tunnel só registra um hostname. Para múltiplos serviços públicos, usar NPM como reverse proxy no destino do Funnel.

## Serve (rede interna)

Nenhum serve configurado atualmente (apenas funnels para exposição externa).

## Configuração dos Servidores

### IP Forwarding (para Exit Nodes)

Ativado em **ybytu** (único exit node):

```bash
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding=1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
```

### Key Expiry

Desabilitado nos servidores via admin console do Tailscale.
