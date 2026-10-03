---
tags: [homelab, network, tailscale]
---

# Tailscale

**Tailnet:** chimaera-heptatonic.ts.net

## Máquinas na Tailnet

| Máquina | IP Tailscale | Papel |
|---|---|---|
| psicopompo | `100.82.51.112` | Dev + GPU workers (StênioBOT) |
| ybytu | `100.115.253.109` | Exit Node, DNS, Peer Relay (`:40000/udp`) |
| ybyra | `100.66.224.34` | Cloud — borda primária |
| kuaray | `100.94.209.99` | Multimídia — Funnel Home Assistant |
| kavure | `100.124.146.77` | Servidor de serviços dedicado, Swarm Manager, Peer Relay (`:40000/udp`) |
| anansi | `100.71.232.79` | Android |
| kururu | `100.127.188.45` | Nó headless dedicado (Samsung SM-T110 / Alpine Linux) |

## Padrão de Acesso (Tailscale SSH)

**Método padrão de acesso aos servidores: Tailscale SSH** — usa autenticação da tailnet (WireGuard), sem expor porta 22 à internet.

```bash
tailscale ssh kavure@kavure
tailscale ssh root@kuaray
tailscale ssh ubuntu@ybyra
```

### Check mode → resolvido com `accept` para non-root (29/09/2026)

A **ACL padrão** do Tailscale usa `action: check` para conectar aos **próprios
dispositivos** → pede **reautenticação no navegador a cada 12h** (`checkPeriod`
default de 12h). Para humanos é aceitável; para **automação headless** é fatal — o
`deploy-swarm.sh` abre SSH e **não tem como clicar no link**.

**Fix aplicado na ACL do tailnet** (admin console → *Access controls* → **JSON
editor**), em **29/09/2026**: non-root passa direto; `root` continua exigindo SSO.

```jsonc
"ssh": [
  // 1) rotina/automação (non-root): aceita direto -> deploy não trava mais no re-auth
  {
    "action": "accept",
    "src":    ["autogroup:member"],
    "dst":    ["autogroup:self"],
    "users":  ["autogroup:nonroot"],
  },
  // 2) root segue exigindo check (padrão de mínimo privilégio da Tailscale)
  {
    "action": "check",
    "src":    ["autogroup:member"],
    "dst":    ["autogroup:self"],
    "users":  ["root"],
  },
],
```

**Por que `autogroup:self` e não `tag:server`:** o snippet anterior usava
`dst: ["tag:server"]`, mas **nenhum servidor do homelab tem tag** (`Tags: None` em
kavure/psicopompo/ybyra) → a regra era **inerte**. `autogroup:self` casa
automaticamente com os dispositivos do próprio dono, sem precisar taguear nada.

**Nuances verificadas na doc oficial** ([policy syntax](https://tailscale.com/kb/1337/policy-syntax)):

| Nuance | Detalhe |
|---|---|
| **Ordem de avaliação** | Regras de SSH são avaliadas da **mais restritiva** para a menos (*check* antes de *accept*) — mas a regra só casa se o **usuário SSH pedido** estiver na lista `users`. Como a regra `check` lista **só `root`**, uma conexão como `edu` não casa nela e cai no `accept` ✅ |
| **`checkPeriod`** | Existe **apenas nos planos Premium/Enterprise** → em plano pessoal o `Save` pode ser rejeitado. O default de **12h** já vale sem declará-lo |
| **`dst` de SSH** | Aceita apenas tag, `autogroup:self` ou um usuário nomeado — `*` é proibido |
| **Usuário no destino** | O Tailscale só usa **contas que já existem no host**: `ssh psicopompo` a partir do kavure falha com `tailnet policy does not permit you to SSH as user "kavure"` porque **não existe usuário `kavure` no psicopompo**. Correto é `ssh -l edu psicopompo` |
| **CLI** | O `tailscale` (1.102.4) **não altera ACL** — só o [admin console](https://login.tailscale.com/admin/acls) ou a API |

**Verificação (29/09/2026):**

```bash
ssh -o BatchMode=yes kavure 'echo OK'        # → OK, sem pedir link de autenticação
```

> **Acesso a partir do próprio host:** `ssh psicopompo` **no** psicopompo falha com
> `Connection refused` — o tráfego para o próprio IP da tailnet não passa pelo
> netstack do `tailscaled`. Testar sempre **de outro nó**.

> **GitOps da ACL — FUNCIONANDO desde 29/09/2026:** a política é versionada no repo
> **privado** [`ceduardorodrig/MNEMOCINE-ACL`](https://github.com/ceduardorodrig/MNEMOCINE-ACL)
> e aplicada pelo [`tailscale/gitops-acl-action`](https://github.com/tailscale/gitops-acl-action)
> (`action: test` em PR, `action: apply` em push na `main`). O repo é **privado por
> exigência da Tailscale** (a política contém PII). Clone local em
> `/mnt/NVME_PCI/homelab/mnemocine-acl`.
>
> **Credencial federada (OIDC)** criada no admin console com escopo **`policy_file`**
> (Issuer `GitHub Actions`). As três variáveis ficam no **cofre sops** como
> `TS_OAUTH_ID`, `TS_AUDIENCE` e `TS_TAILNET` (não são segredos — a doc: *"are not
> secrets and will be visible in the admin console"* — mas mantêm a fonte única), e são
> instaladas como secrets do repo via `gh secret set`.
>
> ⚠️ **Subject (formato IMUTÁVEL):** como o repo nasceu depois de **15/07/2026**, o
> GitHub emite o subject com `owner_id`/`repo_id`. O valor usado é:
> `repo:ceduardorodrig@276087739/MNEMOCINE-ACL@1396147999:*` — o `*` cobre push **e**
> pull request. O formato antigo (`repo:ceduardorodrig/MNEMOCINE-ACL:*`) **não casa**.
>
> **Fluxo:** `git switch -c acl/x` → editar `policy.hujson` → push → PR (o CI roda os
> `sshTests` e **não** altera nada) → merge → o CI **aplica**. Validado ponta a ponta:
> PR #1 com `test` verde, merge com `apply` verde, e `ssh kavure` seguindo OK.
>
> **Próximo passo (dono):** ligar **"Prevent edits in the admin console"** nas
> *Access controls*, com a *External reference* apontando para este repo — aí o repo
> passa a ser a fonte única e edição manual deixa de ser possível.
>
> ✅ **TRANCADO em 29/09/2026:** a opção foi ativada em **Settings → Policy file
> management** ([link](https://console.tailscale.com/admin/settings/policy-file-management))
> — **não** na página de *Access controls* — com a *External reference* apontando para
> `https://github.com/ceduardorodrig/MNEMOCINE-ACL`. A doc avisa que quem editar no
> console (via "Edit anyway", a válvula de escape) **tem a mudança sobrescrita** no
> próximo `apply` — o repo é a fonte única.
>
> ⚠️ **A técnica antiga de "comentário mágico" no HuJSON para travar o editor foi
> descontinuada em 03/06/2025**; a Tailscale migrou os tailnets para esse toggle.
> Nenhuma referência a ela no `policy.hujson`.
>
> **Prova de que o tailnet roda o repo:** o `etag` de controle passou a ser
> `1cc03d81185dde8567f6e00cb04750f8473698ad31bd1190d8d447b8f385d6d6` — o hash do
> **nosso arquivo** (antes o controle tinha o hash da política editada à mão).
>
> **Reversão, se necessário:** desligar o toggle em *Policy file management* e revogar
> a credencial federada em *Trust credentials*.
>
> 💡 **Detalhe do `gitops-pusher` (aprendido em 29/09/2026):** comparar os hashes
> `control` e `local` no log do action **não** serve como teste de sincronia quando a
> mudança é só de comentário — o conteúdo efetivo é o mesmo e o pusher **não reenvia**
> (o `apply` retorna `success` e o `etag` de controle não muda). O critério confiável
> é `outcome=success` **mais** o teste funcional (`ssh -o BatchMode=yes kavure`).
>
> **Melhoria futura:** guardar uma **API key** da Tailscale no cofre permitiria criar/
> rotacionar a credencial federada por API (`POST /api/v2/tailnet/-/keys`,
> `keyType: federated`) em vez do console.

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

## Tailscale Peer Relays (02/10/2026)

Os **Peer Relays** permitem utilizar dispositivos dentro da própria tailnet como servidores de relay de alta taxa de transferência (throughput) para conexões cliente-a-cliente quando conexões diretas não forem possíveis (ex: sob CGNAT severo ou firewall restritivo), antes de cair no fallback dos DERP públicos.

### Nós Configurados como Peer Relay

| Host | IP Tailscale | Porta UDP | Bind / Status |
|---|---|---|---|
| **ybytu** | `100.115.253.109` | `40000` | `0.0.0.0:40000` / `[::]:40000` (`tailscaled`) |
| **kavure** | `100.124.146.77` | `40000` | `0.0.0.0:40000` / `[::]:40000` (`tailscaled`) |

### Comandos de Configuração no Host

```bash
# Ativar porta de relay peer no tailscaled
sudo tailscale set --relay-server-port=40000

# Verificar se a porta foi gravada nas preferências
sudo tailscale debug prefs | grep RelayServerPort

# Verificar o listener UDP ativo
sudo ss -ulpn | grep 40000
```

### Autorização na Política de Acesso (ACL / Grants)

Para que outros nós da Tailnet sejam autorizados pelo control plane a rotear através dos nós de Peer Relay, a política de ACL (`policy.hujson` via GitOps no repo `MNEMOCINE-ACL`) deve conter a capability `tailscale.com/cap/relay`:

```jsonc
"grants": [
  {
    "src": ["autogroup:member"],
    "dst": ["100.115.253.109", "100.124.146.77"], // ybytu e kavure
    "app": {
      "tailscale.com/cap/relay": []
    }
  }
]
```

### Como Verificar o Uso

Quando um nó da tailnet estiver utilizando um peer relay para alcançar outro dispositivo:
```bash
tailscale status | grep peer-relay
```
O campo de conexão reportará `peer-relay` em vez de `relay` (DERP) ou `direct`.

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
