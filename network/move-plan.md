---
tags: [homelab, network, storage, todo]
---

Montar a infraestrutura ideal na casa nova e prever o impacto dessa migração é um excelente exercício de planejamento. Como a sua rede hoje é madura, rodando serviços críticos como o **StênioBOT**, servidores de Minecraft otimizados em Docker, automação residencial com Home Assistant via MQTT e o ecossistema da Tailscale, o seu foco deve ser o **isolamento de camadas**.

Abaixo está o desenho de rede ideal para o seu perfil e o tamanho do esforço para essa mudança.

## O Cenário Ideal: O que eu faria na rede nova

O maior erro em Homelabs é deixar o modem da operadora gerenciar a rede local. Para ter controle total e estabilidade, eu adotaria o conceito de **Modem em Bridge + Roteador Próprio**.

```
[Mundo Externo (Fibra)] 
          │
          ▼
[Modem da Operadora] ──(Modo Bridge)──> [Seu Roteador Próprio]
                                                │
       ┌────────────────────────────────────────┴────────────────────────────────────────┐
       ▼                                        ▼                                        ▼
[Rede IoT / Automação]                  [Rede Cabeada Física]                    [Rede Wi-Fi Principal]
(Lâmpadas, MQTT, HA)                     (Psicopompo, Linux)                      (Celulares, S10 FE+, PS5)
```

### 1. Centralizar o controle em um Roteador Próprio

Eu compraria um roteador robusto compatível com sistemas open-source como **OpenWrt** (se quiser escovar bit) ou soluções prontas avançadas (como um roteador da ASUS da linha RT, ou um mini-PC rodando **pfSense/OPNsense** se quiser ir para o nível corporativo).

- **Ação:** Colocar o modem da operadora em **Modo Bridge** (onde ele vira apenas um "cano" de internet e desliga o Wi-Fi) e conectar o seu roteador próprio atrás dele.
    
- **Vantagem:** O seu roteador próprio será o cérebro da rede. Se você trocar de operadora de novo no futuro, basta plugar o modem novo em Bridge nele e **absolutamente nada** na sua casa precisa ser reconfigurado.
    

### 2. Segmentação por VLANs (Segurança para o Home Assistant)

Dispositivos de automação inteligente (lâmpadas Wi-Fi, sensores) costumam usar firmwares chineses vulneráveis.

- **Ação:** No seu roteador novo, eu criaria uma **VLAN** (uma rede virtual isolada) apenas para os dispositivos IoT e o broker Mosquitto/MQTT.
    
- **Vantagem:** Suas lâmpadas conseguem falar com o Home Assistant, mas se uma delas for invadida, o invasor não consegue enxergar o seu sleeper _Psicopompo_ ou os seus dados pessoais.
    

### 3. IPv6 Nativo com Failover para a Tailnet

Ao contratar a operadora nova (tente buscar as que entregam IPv6 nativo, como as grandes de fibra), você vai configurar o seu roteador próprio para receber esse bloco IPv6.

- **Ação:** No painel da Tailscale, você poderá reativar o IPv6 sem medo, pois agora a sua rede física saberá para onde escoar esse tráfego. O Windows (`Psicopompo`) nunca mais vai dar o bug do planetinha, o Google Drive vai sincronizar instantaneamente e você terá portas abertas reais para o mundo sem depender de proxies se não quiser.
    

## Estimativa de Trabalho: O tamanho do "Boleto" da Migração

A boa notícia é que o uso do **Docker** e da **Tailscale** na sua estrutura atual vai reduzir drasticamente o seu trabalho. Você não vai precisar reconfigurar servidores do zero. O trabalho se divide em três níveis de dificuldade:

### Nível Fácil: Seus Serviços e Containers (Esforço: 5%)

Graças ao Docker, a migração do seu servidor Linux é praticamente um "copia e cola".

- Seus servidores de Minecraft, o banco de dados do Home Assistant e o StênioBOT vão subir idênticos na casa nova assim que você ligar o servidor Linux na tomada.
    
- A Tailscale vai achar as máquinas na internet e restabelecer os túneis de forma 100% transparente, independente do novo IP que o provedor te der.
    

### Nível Médio: A Infraestrutura Física e Wi-Fi (Esforço: 40%)

Aqui está o trabalho manual de reconexão:

- Passar os cabos de rede para o _Psicopompo_ e para o servidor Linux no novo escritório.
    
- **O truque de ouro:** Se você configurar o Wi-Fi do seu roteador novo com **exatamente o mesmo SSID (nome da rede) e a mesma senha** do ambiente atual, todas as suas lâmpadas inteligentes, o Galaxy Tab S10 FE+ e o PS5 vão se conectar sozinhos na rede nova, sem você precisar resetar um por um.
    

### Nível Difícil: Ajustes de IPs Estáticos e DNS (Esforço: 55%)

Essa será a parte chata que vai exigir atenção para não quebrar o fluxo:

- O modem novo provavelmente virá com uma sub-rede diferente (ex: mudando de `192.168.3.x` para `192.168.1.x`).
    
- Você terá que redefinir os IPs estáticos do seu servidor Linux e do _Psicopompo_ para a nova faixa.
    
- Será necessário atualizar o mapeamento de DNS no modem novo para apontar para o IP local atualizado do seu Pi-hole, garantindo que o bloqueio de anúncios continue funcionando para quem está no Wi-Fi.
    

### Resumo do veredito:

Será um trabalho de **um fim de semana**. O primeiro dia voltado para passar cabos, fixar roteadores e subir o Wi-Fi; o segundo dia focado em alinhar os IPs estáticos, ajustar o Pi-hole na nova sub-rede e testar as automações do Home Assistant. No final, com o roteador próprio em mãos, você terá uma rede infinitamente mais robusta e à prova de futuro.