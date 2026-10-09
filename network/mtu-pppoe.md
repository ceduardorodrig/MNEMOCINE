---
tags: [homelab, network, config]
---

# MTU / PPPoE — perda silenciosa em transferências grandes

Diagnóstico e correção do desencontro de **MTU** entre a LAN (`1500`) e o link de
**PPPoE** da operadora (`1492`), que causava falhas intermitentes (pacotes grandes
descartados em silêncio).

## Sintoma

- `cachy update` falhava de vez em quando, sem padrão (o repo `[punktfunk]` "não alcançava o database").
- Sites/apps que "travam e voltam"; downloads que só funcionam na 2ª tentativa.
- **Medido:** em **40 amostras** de 20 min, um download de **2 MB falhou 12 vezes (30 %)**
  — sempre **pendurando** no timeout (não dá erro: congela).

## Diagnóstico (medido 07/10/2026)

```
LAN (192.168.3.1):   1472 OK                       → MTU local = 1500
Internet (1.1.1.1):  1472 FRAG_NECESSÁRIO, 1464 OK → PMTU = 1492  ← PPPoE
Internet (8.8.8.8):  1472 FRAG_NECESSÁRIO, 1464 OK → PMTU = 1492
interface (psicopompo): mtu 1500                   ← divergente
```

O link é **PPPoE (1492)** mas a LAN/host usam **1500**. A conexão anuncia MSS 1460 → o
servidor remoto manda pacotes de até 1500 bytes → o enlace PPPoE precisa fragmentar; onde
o **ICMP "fragmentation needed" é descartado** (blackhole de PMTUD), o pacote grande
**some sem aviso** → a sessão congela. Por isso é **intermitente** e só atinge
**transferências grandes** (DNS, que é pequeno, passa ileso).

### Por que o automático não resolveu

| Mecanismo "automático" | O que deveria fazer | Por que falhou |
|---|---|---|
| **DHCP option 26** (Interface MTU) | o modem informar a MTU aos clientes | o host **pede** (`requested_interface_mtu = 1`), mas o modem **não responde** |
| **PMTUD** (ICMP) | roteadores avisarem "use menor" | ICMP bloqueado/descartado em parte do caminho → blackhole |

> O caminho limpo seria o **modem** anunciar a MTU (DHCP 26) ou fazer **MSS clamping**.
> O ONT Huawei da operadora **não expõe** nenhum dos dois.

## Alcance (quem é impactado)

O problema é uma propriedade do **link de casa**. Só é atingido quem **cruza esse link**:

| Quem | Tráfego geral | DNS |
|---|---|---|
| Dispositivos da **LAN de casa** (psicopompo, kuaray, kavure, desktop Windows, celulares, IoT) | ⚠️ **impactado** | ok |
| Nós **fora** (ybytu/ybyra/Oracle, celular no 4G) | ✅ não passa pelo link | ok |
| Pessoa leiga na tailnet (só Tailscale + DNS, sem exit node) | ✅ sai pela internet dela | ✅ ok na prática |
| Quem usar **kavure** como exit node | ⚠️ **impactado** (sai pelo link de casa) | — |

**Por que o DNS de todos não dói, apesar de centralizado no kavure** (o egress local
passa pelo link de casa — ver [`dns.md`](dns.md)):

1. DNS é tráfego **pequeno** → imune ao problema (medido **40/40 = 100 %**);
2. **Fallback DoT** do AdGuard (`tls://9.9.9.9`/`tls://1.1.1.1`) cobre queda do unbound/kavure;
3. Cache (Pi-hole 10 k + unbound 32m/64m).

## Correção

### Paliativo (aplicado nos hosts) — MTU 1492

O valor **1492** é o correto para PPPoE (a Arch Wiki: *"For PPPoE, the MTU should not be
larger than 1492"*). Efeito: o host anuncia MSS menor → os pacotes remotos cabem no PPPoE
→ **acaba a dependência do ICMP/PMTUD**.

| Host | Stack | Como | Status |
|---|---|---|---|
| **psicopompo** | NetworkManager | `nmcli con modify "Wired connection 1" 802-3-ethernet.mtu 1492` + `nmcli device reapply eno1` | ✅ 07/10/2026 |
| **kuaray** | NetworkManager | idem (`Wired connection 1`, `enp7s0`) | ✅ 07/10/2026 |
| **kavure** | **netplan** → systemd-networkd | `mtu: 1492` em `enp1s0` no `/etc/netplan/50-cloud-init.yaml` + `netplan apply` (backup `.bak-20261007-mtu`) | ✅ 07/10/2026 |

> ⚠️ **Nunca** ajustar a MTU em runtime com `ip link set` no psicopompo: o driver
> **`e1000e`** rebaixa o link (`NO-CARRIER` por ~30–60 s). Usar NetworkManager
> (`nmcli device reapply`, que **não** pisca) ou aplicar em boot.
>
> Reversão: `nmcli con modify "<conn>" 802-3-ethernet.mtu 1500` (ou remover o `mtu:` do netplan).

### Correção correta (borda) — futuro

O lugar certo é a **borda**, onde a LAN encontra o PPPoE — em **um** ponto, para **todos**
os dispositivos (inclusive Windows, celulares, visitas):

1. **Modem/ONT em modo bridge** (só converte fibra↔ethernet);
2. **Router/firewall próprio** (OPNsense/pfSense/OpenWrt) fazendo o **PPPoE + MSS clamping**;
3. Resultado: LAN de volta em **1500** e nenhum host precisa de ajuste.

Referência oficial do MSS clamping (Arch Wiki, [*Internet sharing*](https://wiki.archlinux.org/title/Internet_sharing)):
```bash
iptables -t mangle -A FORWARD -o ppp0 -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
```

> O modem da operadora (Huawei) **permite bridge**, mas **não** expõe campo de MTU/MSS na
> LAN. Daí a necessidade de um roteador próprio para a solução definitiva.

### Plano do roteador dedicado (mini-PC) — e a **reversão completa**

Caminho previsto (breve): **mini-PC** (ex.: Intel N100/N150, 2 NICs) com **OPNsense /
pfSense**, ou um roteador **OpenWrt**:

1. ONT Huawei em **bridge** (só conversor fibra↔ethernet);
2. o mini-PC disca o **PPPoE** e faz **MSS clamping**;
3. a LAN volta a **1500** e **nenhum host** precisa de ajuste.

**Quando o roteador dedicado entrar, reverter o paliativo** (nesta ordem):

```bash
# psicopompo (NetworkManager)
sudo nmcli con modify "Wired connection 1" 802-3-ethernet.mtu 1500
sudo nmcli device reapply eno1

# kuaray (NetworkManager, enp7s0)
sudo nmcli con modify "Wired connection 1" 802-3-ethernet.mtu 1500
sudo nmcli device reapply enp7s0

# kavure (netplan → systemd-networkd)
sudo cp -a /etc/netplan/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml.bak-YYYYMMDD-mtu
# remover a linha 'mtu: 1492' de enp1s0
sudo netplan apply
```

4. **Confirmar:** `ping -M do -s 1472 <destino>` volta a passar (1500 ponta a ponta) e o
   monitor de 2 MB dá **0 % de falha**;
5. **Atualizar a doc:** marcar esta nota como **histórico** e ajustar a
   [`tailscale.md`](tailscale.md).

> **Marcadores para não esquecer:** o paliativo está em **3 hosts** e é **reversível por
> comando** — nenhum arquivo de kernel/driver foi alterado, e nada foi mexido no modem.

## Verificação (A/B)

Script de medição (20 min, amostras de 30 s) medindo `punktfunk.db` (pequeno), **2 MB**
(Cloudflare, grande) e DNS:

| Fase | punktfunk (9 KB) | **2 MB (grande)** | DNS |
|---|---|---|---|
| **Antes** (MTU 1500) | 40/40 OK | **28/40 (30 % falha)** | 40/40 OK |
| **Depois** (MTU 1492) | 35/40 OK | 38/40 (5 % falha) | 40/40 OK |
| **Confirmação** (MTU 1492, assentado) | 16/20 OK | **20/20 OK (0 %)** | 20/20 OK |

**Leitura:** com o link assentado, a 3ª medição **não teve nenhuma falha** de 2 MB — a perda
em transferência grande caiu de **30 % → 0 %**. As falhas esporádicas do `punktfunk` que
apareceram durante a investigação eram **o próprio problema da MTU** (o handshake TLS —
pacote grande — travando na abertura), **não** o servidor de terceiros.

> **Conclusão (provada):** a correção **elimina** a perda em transferências grandes
> (**30 % → 0 %**) e o `cachy update` passou a rodar **liso**. Os **3 hosts** (psicopompo,
> kuaray, kavure) estão em MTU **1492**, persistente após reboot.

> **Correção da leitura (07/10/2026):** durante a investigação eu registrei os timeouts de
> conexão de 10 s (`punktfunk`, `extra.db`) como *"item separado, não é MTU"* e apontei
> `ParallelDownloads = 10` sob CGNAT como suspeito. **Era engano:** sem tocar em
> `ParallelDownloads`, o `cachy update` passou a rodar liso após a MTU 1492 — aqueles
> timeouts eram **o mesmo problema**. **Não há pendência separada.**

## Ver também

- [`dns.md`](dns.md) — cadeia de DNS e egress recursivo local (também depende do link de casa)
- [`tailscale.md`](tailscale.md) — exit nodes (kavure = link de casa; ybytu = Oracle)
- [`../servers/psicopompo.md`](../servers/psicopompo.md) — host onde o paliativo foi aplicado
