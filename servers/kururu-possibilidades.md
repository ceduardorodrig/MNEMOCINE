---
tags: [homelab, server, kururu, roadmap]
---

# Kururu — Catálogo de 20 Possibilidades & Roadmap Estratégico

Este documento cataloga **20 casos de uso reais e estratégicos** para o nó **Kururu** (Samsung Galaxy Tab 3 Lite 7.0 / SM-T110), aproveitando sua arquitetura soberana bare-metal Linux (Alpine v3.20 + kernel Samsung 3.4.5), seus **>770 MB de RAM livre** e seu conjunto único de sensores e atuadores físicos.

---

## 🧰 O Perfil de "Superpoderes" do Kururu

Diferente de um servidor comum x86 ou de uma placa SBC tradicional (como Raspberry Pi ou Orange Pi), o Kururu traz vantagens físicas integradas de fábrica:

1. **No-Break / UPS de Hardware Integrado (Bateria Li-ion ~3600 mAh):** Não desliga durante picos, oscilações ou apagões na rede elétrica. Opera por horas de forma contínua mesmo sem energia na tomada.
2. **Display Colorido de 7 Polegadas (1024x600, 32bpp):** Acesso direto via framebuffer de vídeo (`/dev/graphics/fb0`), sem a sobrecarga pesada de X11, Wayland ou Android TouchWiz.
3. **Botões de Hardware Dedicados (`/dev/input/`):**
   - Tecla **Power** (`/dev/input/event2` — PMIC 88PM822) → Atualmente controla o despertar/hibernação da tela.
   - Teclas de **Volume Up / Volume Down** (`/dev/input/event0` ou `event1`) → Disponíveis para navegação entre telas, abas e seleção de menus.
4. **Consumo Elétrico Quase Nulo (< 0.8W):** Custo operacional irrisório (< R$ 0,50 por mês ligado 24/7).
5. **Saída de Áudio P2 (3.5mm) & Alto-Falante Integrado:** Capaz de gerar tons de alerta, voz sintetizada e áudio.
6. **Porta Micro-USB com suporte a Host/OTG:** Permite acoplar adaptadores USB-Serial, rádios LoRa ou teclados.
7. **Slot MicroSD:** Expansão de armazenamento de até 32/64 GB para armazenamento local isolado.

---

## 🧭 Catálogo das 20 Possibilidades

### Categoria A: Alta Disponibilidade, Quorum & Resiliência Elétrica

#### 1. Sentinela de Apagão ("Dead Man's Snitch" / Queda de Energia Geral)
- **Conceito:** O Kururu é o **único nó do homelab com bateria própria**.
- **Como funciona:** Um daemon leve em Rust monitora via ICMP/ping os 5 nós centrais (`psicopompo`, `kavure`, `kuaray`, `ybytu`, `ybyra`) e o gateway local (`192.168.3.1`). Se todos os servidores AC pararem de responder juntos, o Kururu detecta imediatamente que houve **queda geral de energia** e emite um alerta de emergência via webhook/Telegram/Ntfy antes que as baterias das torres da operadora se esgotem.

#### 2. Quorum Witness (Testemunha de Desempate de Cluster)
- **Conceito:** Ambientes com tolerância a falhas (etcd, Raft, Corosync) exigem um número ímpar de participantes para evitar *split-brain*.
- **Como funciona:** O Kururu atua como o voter imparcial de baixo consumo, garantindo quorum sem a necessidade de manter uma máquina pesada ligada.

#### 3. Servidor DNS Secundário Resiliente (Blocky / AdGuard Home / Unbound)
- **Conceito:** Resolução local de nomes ininterrupta com bloqueio de telemetria e anúncios.
- **Como funciona:** Servindo como DNS secundário na rede local (`192.168.3.55`), garante que, caso o servidor DNS principal (ex.: no Kavure) reinicie para atualizações, a navegação de todos os dispositivos e celulares da casa continue sem interrupção.

#### 4. Espelho de Chaves & Segredos de Emergência (Offline Secret Vault)
- **Conceito:** Backup estático criptografado somente-leitura dos segredos do SOPS/Age, credenciais da Tailnet e chaves SSH críticas.
- **Como funciona:** Em caso de corrupção ou falha catastrófica dos storages principais, o Kururu guarda uma cópia segura acessível diretamente pelo console local.

---

### Categoria B: Telemetria Visual, Dashboards & Interação Física (Tela & Botões)

#### 5. NOC Desk Dashboard Interativo (Navegação via Teclas de Volume)
- **Conceito:** Evolução natural do [`kururu-display`](../../homelab/kururu-tab3lite-linux/crates/kururu-display/src/main.rs).
- **Como funciona:** Aproveitando os eventos das teclas físicas de Volume (`KEY_VOLUMEUP` e `KEY_VOLUMEDOWN`), permite alternar dinamicamente entre páginas na tela de 7":
  - **Aba 1 (Cluster Mnemocine):** Saúde, IPs e status dos 5 nós principais (`Psicopompo`, `Kuaray`, `Kavure`, `Ybytu`, `Ybyra`).
  - **Aba 2 (Containers & Serviços):** Status dos serviços Docker (Directus, WordPress, Valheim, Zomboid, Glances).
  - **Aba 3 (Hardware Remoto):** Temperatura da GPU do `psicopompo`, uso de disco do NAS `kavure` e uso de CPU do `kuaray`.
  - **Aba 4 (Relógio Retrô & Clima):** Relógio minimalista estilo CRT verde fosforescente com previsão meteorológica local.

#### 6. Kiosk de Monitoramento de Impressão 3D (Klipper / Moonraker / OctoPrint)
- **Conceito:** Tela dedicada de cabeceira/bancada para impressora 3D.
- **Como funciona:** Conecta-se à API da impressora via Wi-Fi e exibe porcentagem da camada, tempo estimado de término, temperaturas do bico e da mesa em tempo real.

#### 7. Monitor Contínuo de Latência WAN & Perda de Pacotes (Ping Matrix)
- **Conceito:** Raio-X visual da qualidade do link de fibra da operadora.
- **Como funciona:** Registra e desenha no framebuffer um gráfico histórico das últimas 2 horas de latência para múltiplos destinos (Cloudflare 1.1.1.1, Google 8.8.8.8, IX.br SP), revelando instabilidades e microquedas do modem.

#### 8. Pomodoro & Rastreador de Foco E-Ink Style
- **Conceito:** Cronômetro de trabalho focado sem as distrações do celular.
- **Como funciona:** Exibe contagem regressiva limpa de blocos de 25 minutos, acionada com um clique no botão físico, mantendo o ambiente de trabalho organizado e focado.

---

### Categoria C: Notificações, Áudio & Interação Física (Alto-Falante & P2)

#### 9. Sirene de Incidentes do Homelab (Alert Beep & Soundbox)
- **Conceito:** Feedback sonoro imediato para alertas de infraestrutura.
- **Como funciona:** Usando o driver ALSA e o amplificador interno do tablet (ou caixa de som no P2), reproduz bips distintos ou mensagens de voz sintetizada (`espeak-ng`):
  - *Tom curto:* Backup noturno finalizado com sucesso.
  - *Tom duplo:* Novo dispositivo autenticado na Tailnet.
  - *Alarme:* Nó do cluster inatingível ou superaquecimento de GPU.

#### 10. Servidor Próprio de Notificações Push (Ntfy / Gotify)
- **Conceito:** Infraestrutura 100% soberana de notificações, sem depender de Apple APNs ou Google FCM.
- **Como funciona:** Roda uma instância leve do [ntfy](https://ntfy.sh) em ARMv7. Scripts de cron, deploys e alertas enviam requisições `curl` locais para o Kururu, que distribui para os navegadores e celulares.

#### 11. Receptor de Áudio Sem Fio (AirPlay / Snapcast / Shairport-Sync)
- **Conceito:** Transformação do tablet em streamer de música para caixas analógicas.
- **Como funciona:** Conectado a um receiver ou caixa de som via cabo P2, recebe transmissões de áudio de alta fidelidade sem compressão com latência zero.

#### 12. Gerador Autônomo de Ruído Branco & Som de Foco (Sound Generator)
- **Conceito:** Gerador sonoro contínuo offline para concentração ou sono.
- **Como funciona:** Daemon que sintetiza sons procedurais (ruído marrom, chuva leve, ventilador) consumindo menos de 1% de CPU, podendo ser ativado pelo botão físico.

---

### Categoria D: Rede, Conectividade & Automação Residencial

#### 13. Emissor de Wake-on-LAN Resiliente (WOL Relay da LAN) ⚡
- **Conceito:** Servidor de acionamento remoto para ligar o `psicopompo` ou o `kavure` de qualquer lugar do mundo.
- **O Desafio Atual (atualizado 02/10/2026):**
  - ~~O Kavure atrás de repetidor Wi-Fi (bloqueava broadcast L2 `192.168.3.255:9`).~~
    **Obsoleto:** desde 02/10 o kavure é **cabeado** no switch gigabit `IT-BLUE LE-4203`
    → o broadcast chega normalmente a ele.
  - **✅ Resolvido em 02/10/2026:** o teste das 14:07 falhou por **BIOS**
    (`Deep Sleep Control = Enabled in S4 and S5`, default do OptiPlex 3060) — corrigido e
    **validado à noite**: kavure acorda em **29s** e psicopompo em **54s**, nos dois
    sentidos, com persistência `wol@.service`. Ver
    [`services/wol-relay.md`](../services/wol-relay.md) §Validação de ponta a ponta.
  - **O argumento original virou design:** um host em soft-off só volta se **outro nó
    vivo** emitir o pacote — por isso as **3 camadas** (kururu 24/7+bateria acorda os
    dois; psicopompo ⇄ kavure se acordam mutuamente). Quórum: basta 1 nó vivo.
- **A Solução Kururu:**
  - O Kururu está permanentemente ligado na tomada (com bateria de backup), na mesma sub-rede `192.168.3.0/24`.
  - Pode escutar uma rota simples autenticada (via SSH ou pequeno micro-serviço em Rust na porta 9096):
    ```bash
    # Exemplo de acionamento via Tailscale de qualquer lugar:
    ssh root@kururu wake psicopompo
    ```
  - Dispara o Magic Packet com repetição de 16x do endereço MAC alvo direto na interface `mlan0`.
  - **Investigação de Riscos de MAC:** Documentar de forma controlada os MACs reais de hardware (`d0:94:66:de:8b:58` para psicopompo e `d0:94:66:ad:f3:c4` para kavure) com proteções anti-spoofing e controle de acesso estrito na Tailnet.

#### 14. Broker MQTT Central para IoT (Mosquitto / Rumqttd)
- **Conceito:** Central de mensageria leve para domótica.
- **Como funciona:** Gerencia mensagens de lâmpadas, tomadas inteligentes, sensores térmicos e ESP32s da casa consumindo menos de 4 MB de RAM.

#### 15. Gateway / Subnet Router de Emergência na Tailnet
- **Conceito:** Ponto de entrada de contingência na rede local.
- **Como funciona:** Atua como subnet router anunciando a rota `192.168.3.0/24`, permitindo acessar impressoras, roteadores ou outros dispositivos cabeados da casa mesmo se o roteador principal reiniciar.

#### 16. Servidor de Webhooks para Automações (Webhook-rs)
- **Conceito:** Receptor de gatilhos HTTP leves para automações.
- **Como funciona:** Recebe webhooks do GitHub, Home Assistant ou cron jobs externos e executa ações seguras pré-definidas na rede interna.

---

### Categoria E: Manutenção, Bancada & Ferramental Avançado

#### 17. Terminal Serial de Bancada para Switches & Roteadores (USB Serial TTY)
- **Conceito:** Terminal de diagnóstico portátil com tela.
- **Como funciona:** Com um cabo OTG e adaptador USB-Serial (FTDI / CH340), o Kururu vira um console serial portátil para conectar na porta console de switches gerenciáveis, roteadores MikroTik ou Raspberry Pis sem precisar levar um laptop para a bancada.

#### 18. Servidor PXE / iPXE de Resgate Local (Netboot Server)
- **Conceito:** Recuperador de máquinas na rede.
- **Como funciona:** Disponibiliza imagens leves de diagnóstico (MemTest86+, Clonezilla, kernel de socorro) via TFTP/HTTP para que qualquer computador conectado ao switch possa inicializar sem pendrive.

#### 19. Gateway de Comunicação Off-Grid LoRa / Reticulum
- **Conceito:** Comunicação de emergência resiliente a colapsos de rede.
- **Como funciona:** Conectado a um módulo LoRa serial/USB (Heltec ou T-Beam), opera como nó repetidor ou terminal de mensageria descentralizado off-grid com a tela de 7" servindo de visor.

#### 20. Auditor Contínuo de Governança Remoto (StênioWorker)
- **Conceito:** Extensão satélite do StênioSentinel.
- **Como funciona:** Executa periodicamente checagens de saúde em background nos nós do cluster (`stenio --health`), validando certificados SSL, integridade dos backups diários do NAS e consistência da malha WireGuard, reportando qualquer anomalia diretamente no display.

---

## 🗺️ Matriz de Priorização Recomendada

| Funcionalidade | Esforço | Impacto | Próximos Passos |
|---|---|---|---|
| **WOL Relay Resiliente (#13)** | Baixo | **Muito Alto** | Adicionar comando `wake` nativo no Kururu com MACs salvos no store protegido. |
| **Abas Interativas com Botões de Volume (#5)** | Médio | **Alto** | Ler `/dev/input/event0` para alternar entre aba de nós, containers e clima. |
| **Sentinela de Queda de Energia (#1)** | Baixo | **Alto** | Script de monitoramento por heartbeat que alerta se a rede AC desligar. |
| **Alertas Sonoros via ALSA (#9)** | Baixo | **Médio** | Habilitar módulo de áudio no kernel para bips de confirmação de backup. |
| **DNS Secundário com Blocky (#3)** | Médio | **Alto** | Deploy de binário estático ARMv7 de DNS com upstream para 1.1.1.1. |

---

## 🔗 Referências e Documentos Relacionados

- [`mnemocine/servers/kururu.md`](kururu.md) — Documentação principal do servidor Kururu
- [`mnemocine/services/wol-relay.md`](../services/wol-relay.md) — Documentação do serviço legado de Wake-on-LAN
- [`mnemocine/network/tailscale.md`](../network/tailscale.md) — Topologia e mapa de endereçamento da Tailnet
- [Repositório GitHub: `KURURU-TAB3LITE-LINUX`](https://github.com/ceduardorodrig/KURURU-TAB3LITE-LINUX) — Código-fonte dos daemons e hooks de boot
