---
tags: [homelab, network, checklist, tutorial, guide]
---

# 📦 Plano Operacional de Mudança & Adaptação de Roteador — Mnemocine

Guia mestre para realocação física do homelab em uma nova residência e adaptação de roteadores (do roteador da operadora ao roteador dedicado definitivo), garantindo **operação 100% plug-and-play**, **zero reconfiguração nos servidores** e **preservação total do isolamento Zero Trust**.

---

## 1. O Princípio de Ouro: "Adapte o Roteador ao Homelab, Nunca o Homelab ao Roteador"

No Mnemocine, regras de firewall no kernel (`ufw`), daemons de Wake-on-LAN (`hl-wol-relay`), descoberta local de streaming (`Punktfunk`) e sincronização peer-to-peer (`Syncthing`) dependem da sub-rede local física **`192.168.3.0/24`** e de IPs fixos específicos.

Se você tentar mudar o homelab para caber na sub-rede arbitrária que o modem da operadora traz por padrão (como `192.168.1.1` ou `192.168.0.1`), você precisará reescrever regras de firewall em 4 máquinas, reconfigurar scripts de WoL, ajustar configs de containers e re-parear dezenas de dispositivos inteligentes.

**A Solução Plug & Play (5 minutos de configuração no roteador):**
Configure o roteador da nova residência para assumir o IP **`192.168.3.1`**, cadastre as 4 reservas DHCP dos servidores e mantenha o mesmo SSID/senha do Wi-Fi. No instante em que os cabos de rede forem plugados no switch gigabit, **tudo funcionará no primeiro segundo, sem tocar em uma única linha de código nos servidores**.

---

## 2. Matriz Canônica de Reservas DHCP (Tabela de MACs)

Cadastre estas reservas estáticas (DHCP Reservation / Static Leases) na interface de gerenciamento do roteador:

| Host | Interface Física | Endereço MAC | IP LAN Obrigatório | Papel Crítico na LAN |
|---|---|---|---|---|
| **`kururu`** | `mlan0` (Wi-Fi) | `24:f5:aa:7c:e3:1e` | **`192.168.3.55`** | Sentinela WoL 24/7 com bateria (dispara e recebe WoL) |
| **`kavure`** | `enp1s0` (Ethernet) | `d0:94:66:ad:f3:c4` | **`192.168.3.41`** | Swarm Leader, Home Assistant, Pi-hole, WoL peer |
| **`psicopompo`** | `eno1` (Ethernet) | `d0:94:66:de:8b:58` | **`192.168.3.100`** | Workstation, NAS central NFS, GPU worker, WoL peer |
| **`kuaray`** | `enp7s0` (Ethernet) | `a4:1f:72:fb:9a:36` | **`192.168.3.200`** | Standby mirror, suíte multimídia *arr, P2P |

> [!IMPORTANT]
> **Sub-rede da LAN:** `192.168.3.0/24`  
> **IP do Roteador (Gateway):** `192.168.3.1`  
> **Máscara de Sub-rede:** `255.255.255.0`  
> **Pool Dinâmico DHCP:** `192.168.3.101` até `192.168.3.199` (deixa a faixa 2–99 e 200–254 para IPs estáticos de infraestrutura).

---

## 3. Fase 1: Chegada na Casa Nova (Roteador da Operadora)

Ao instalar a nova internet, o técnico deixará um modem/roteador Wi-Fi padrão da operadora (Vivo, Claro, Oi, etc.). Siga este checklist imediato:

### Passo 1 — Acessar o Roteador da Operadora
1. Conecte um notebook ou celular na Wi-Fi/porta LAN do roteador novo.
2. Acesse o IP padrão de fábrica (geralmente `192.168.1.1` ou `192.168.0.1`) com usuário/senha da etiqueta do aparelho.

### Passo 2 — Alterar o Endereçamento LAN
1. Vá em **Rede Local (LAN / DHCP Server)**.
2. Altere o **IP do Roteador / Gateway** para: `192.168.3.1`.
3. Altere a **Máscara**: `255.255.255.0`.
4. Configure a faixa do servidor DHCP: início em `192.168.3.101` e fim em `192.168.3.199`.
5. Salve as alterações. (O roteador irá reiniciar o DHCP; desconecte e reconecte seu dispositivo para pegar um IP `192.168.3.x`).

### Passo 3 — Cadastrar as 4 Reservas Estáticas
1. Acesse o novo painel em `http://192.168.3.1`.
2. Vá em **DHCP Static Lease / Reserva de Endereço IP**.
3. Adicione os 4 itens da **Tabela de MACs da Seção 2**.

### Passo 4 — Configuração da Rede Wi-Fi (Preservação de IoT)
1. Configure o **SSID (Nome da Rede)** exatamente com o **mesmo nome** usado na casa anterior.
2. Configure a **Senha** exatamente com a **mesma senha** WPA2/WPA3 anterior.
3. *Resultado:* Lâmpadas inteligentes (Tuya/SmartLife), sensores ESP32, tablets, consoles e celulares reconectarão automaticamente sem necessidade de resetar nada.

### Passo 5 — Blindagem de Segurança Obrigatória no Modem da Operadora
1. **Desativar UPnP (Universal Plug and Play):** Vá em *Avançado / Segurança / UPnP* e marque **Disabled (Desativado)**. Isso impede que aplicativos na rede peçam abertura de portas na WAN sem você saber.
2. **Desativar DMZ:** Certifique-se de que a opção **DMZ** está **Desativada** (campo em branco).
3. **Port Forwarding:** Certifique-se de que **não há nenhuma porta encaminhada**.

### Passo 6 — Conectar a Infraestrutura Física
1. Conecte um cabo de rede Cat6 saindo de uma porta LAN do roteador da operadora para a porta 1 do seu **Switch Gigabit**.
2. Conecte `psicopompo`, `kavure` e `kuaray` nas portas restantes do Switch.
3. Ligue as máquinas. Elas receberão exatamente os mesmos IPs locais e a malha Tailscale subirá automaticamente.

---

## 4. Fase 2: Evolução para Roteador Próprio Dedicado (Fase Definitiva)

Quando você for adquirir o roteador definitivo para assumir o controle total da borda:

### Arquitetura Alvo

```text
               [Fibra Óptica / WAN Externa]
                            │
                            ▼
               [Modem/ONT da Operadora]
                    (Modo Bridge)
                            │ Cabo Ethernet (Porta WAN)
                            ▼
              ┌───────────────────────────┐
              │  Roteador Dedicado Próprio│  ← OPNsense / UniFi / OpenWrt
              │     (Gateway 192.168.3.1) │
              └─────────────┬─────────────┘
                            │
             ┌──────────────┴──────────────┐
             ▼                             ▼
   [Switch Gigabit Homelab]      [Access Point Wi-Fi]
   - psicopompo (192.168.3.100)  - VLAN IoT (Lâmpadas, Tuya)
   - kavure     (192.168.3.41)   - VLAN Principal (Móveis)
   - kuaray     (192.168.3.200)  - VLAN Visitantes
   - kururu     (192.168.3.55)
```

### 1. Recomendações de Hardware para o Roteador
* **Opção A — Mini PC x86 com OPNsense / pfSense (Recomendado para Homelabbers):**
  * Mini PC Intel N100 ou N305 com 2 a 4 portas Ethernet 2.5 GbE (Intel i226-V), 8–16 GB RAM e NVMe.
  * *Vantagens:* Sistema operacional de nível corporativo, firewall stateful de ponta, IDS/IPS nativo (Suricata), WireGuard/Tailscale nativo, controle fino de DNS e zero limitações de software.
* **Opção B — Appliance Dedicado Gerenciado (UniFi Cloud Gateway Ultra / Express):**
  * *Vantagens:* Interface gráfica integrada, topologia visual de clientes, excelente suporte a VLANs e fácil gerenciamento pelo celular.
* **Opção C — Roteador Comercial com OpenWrt (Ex: GL.iNet Flint 2 / GL-MT6000 ou TP-Link com OpenWrt):**
  * *Vantagens:* Custo-benefício, Wi-Fi 6 integrado potente, kernel Linux aberto.

### 2. Configuração do Modem da Operadora
1. Solicite ou configure o modem da operadora em **Modo Bridge** (Ponte).
2. O modem desativa o roteamento e Wi-Fi interno, tornando-se apenas um conversor de mídia (ONT).
3. Conecte o cabo da porta LAN 1 do modem da operadora na porta **WAN** do seu roteador dedicado.
4. No roteador próprio, configure a conexão WAN (via **PPPoE** com login da operadora ou **DHCP Client**, dependendo do provedor).

### 3. Configuração do Roteador Próprio
1. Configure a interface LAN com IP **`192.168.3.1/24`**.
2. Transporte a tabela de reservas DHCP da Seção 2 para o novo roteador.
3. Configure o **DNS Local**: Aponte o DNS primário do DHCP para o **Pi-hole no Kavure (`100.124.146.77` ou `192.168.3.41`)** e secundário para o **AdGuard no Ybytu (`100.115.253.109`)**.
4. Ative **IPv6 nativo** via DHCPv6 Prefix Delegation (`/56` ou `/64`).

### 4. Segmentação em VLANs (Próximo Nível de Segurança)
Com o roteador próprio, você poderá segregar a rede física em zonas:

* **VLAN 10 (Homelab / Gestão):** `192.168.3.0/24` — Servidores cabeados (`psicopompo`, `kavure`, `kuaray`). Acesso total.
* **VLAN 20 (IoT / Smart Home):** `192.168.20.0/24` — Lâmpadas, tomadas Tuya, sensores.
  * *Regra de Firewall:* Os dispositivos IoT só podem falar com a internet e com a porta do Home Assistant no Kavure (`8123/tcp`), mas **não podem escanear nem acessar o Psicopompo ou os outros servidores**.
* **VLAN 30 (Família & Dispositivos Pessoais):** `192.168.30.0/24` — Computadores pessoais, celulares e consoles.
* **VLAN 40 (Visitantes):** `192.168.40.0/24` — Isolamento total de clientes (acesso apenas à internet).

---

## 5. Checklist de Verificação Pós-Mudança

Após ligar tudo na nova casa, execute esta bateria rápida de validação no terminal do Psicopompo:

```bash
# 1. Validar conectividade física com o novo roteador e nós locais
ping -c 3 192.168.3.1    # Gateway (Roteador)
ping -c 3 192.168.3.41   # Kavure
ping -c 3 192.168.3.200  # Kuaray
ping -c 3 192.168.3.55   # Kururu

# 2. Validar se a malha Tailscale reestabeleceu todos os túneis
tailscale status

# 3. Testar disparo de Wake-on-LAN na LAN local
curl http://127.0.0.1:9096/wake/kavure

# 4. Validar montagem do NAS central (NFS) nos nós clientes
ssh kavure "df -h | grep BACKUP"
ssh kuaray "df -h | grep nas"

# 5. Executar auditoria de superfície de ataque do Stenio Sentinel
stenio --ports
stenio --scope all
```

Se todos os 5 testes responderem com sucesso, a mudança foi 100% transparente e sem atrito.

---

## 6. Referências & Documentos Vinculados

* [`topology.md`](topology.md) — Topologia física e cabeamento gigabit
* [`ports.md`](ports.md) — Matriz canônica de portas e zonas de confiança
* [`../services/wol-relay.md`](../services/wol-relay.md) — Arquitetura de Wake-on-LAN e MACs
* [`../guides/ufw-lan-runbook.md`](../guides/ufw-lan-runbook.md) — Políticas de firewall UFW e sub-rede LAN
* [`../guides/security-baseline.md`](../guides/security-baseline.md) — Baseline de segurança Zero Trust