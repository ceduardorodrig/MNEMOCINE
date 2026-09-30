---
tags: [homelab, guide, tutorial, desktop]
created: 2026-09-25
---

# Guia de Operação do Yazi — Terminal File Manager (psicopompo)

Este guia documenta o uso, arquitetura e atalhos do **Yazi** no CachyOS/Hyprland com Noctalia, substituindo o Dolphin como gerenciador de arquivos padrão do sistema.

## Por que o Yazi?

- **Escrito em Rust:** assíncrono, não-bloqueante e com consumo mínimo de recursos (<30 MB RAM em uso, 0% CPU ocioso).
- **Sem daemons em segundo plano:** não depende de `kiod6`, `baloo` ou frameworks pesados de desktop.
- **Integração Hyprland:** invocado em janela flutuante elegante e veloz via atalho de sistema (`Super + E`).
- **Pré-visualizações nativas:** suporta arquivos de código (`bat`), imagens e vídeos (`ffmpegthumbnailer` + `chafa`), documentos (`pdftoppm`) e arquivos comprimidos (`7z`).

---

## Como Abrir e Controlar a Janela

| Ação | Atalho / Comando | O que faz |
|---|---|---|
| **Abrir o Yazi** | `Super + E` | Abre o Yazi em janela flutuante centralizada |
| **Fechar** | `q` | Fecha o Yazi imediatamente |
| **Sair e abrir terminal no CWD** | `_` (underscore) | Abre um sub-shell na pasta onde você está |
| **Fechar forçado** | `Super + Q` | Fecha a janela pelo atalho padrão do Hyprland |

---

## Navegação Rápida (Jump / Bookmarks)

Para pular rapidamente para qualquer disco ou serviço do sistema, pressione **`g`** seguido da tecla correspondente:

### Discos Locais e Vault
- **`g` `n`** $\rightarrow$ `/mnt/NVME_PCI` (Armazenamento NVMe de trabalho)
- **`g` `a`** $\rightarrow$ `/mnt/NVME_PCI/agentic-ai` (Vault Obsidian / Projetos)
- **`g` `l`** $\rightarrow$ `/mnt/NVME_PCI/homelab` (Repositórios e projetos Homelab)
- **`g` `s`** $\rightarrow$ `/mnt/SSD_SATA` (SSD SATA secundário)
- **`g` `H`** (Shift+H) $\rightarrow$ `/mnt/HDD_SATA` (HDD SATA local)
- **`g` `b`** $\rightarrow$ `/mnt/BACKUP` (Disco de backup do NAS)
- **`g` `G`** (Shift+G) $\rightarrow$ `~/Google_Drive` (Nuvem Google Drive montada via rclone)

### Servidores Remotos (Tailnet)
- **`g` `k`** $\rightarrow$ `~/Remote/kuaray` (Acesso/montagem ao Kuaray)
- **`g` `v`** $\rightarrow$ `~/Remote/kavure` (Acesso/montagem ao Kavure)

### Pastas de Sistema Padrão
- **`g` `h`** $\rightarrow$ `~` (Sua pasta Home)
- **`g` `d`** $\rightarrow$ `~/Downloads` (Downloads)
- **`g` `c`** $\rightarrow$ `~/.config` (Arquivos de configuração do sistema)
- **`g` `t`** $\rightarrow$ Lixeira do sistema (Trash bin)

---

## Movimentação Básica (Estilo Vim & Setas)

- **`k`** ou **`↑`**: Subir um item na lista.
- **`j`** ou **`↓`**: Descer um item na lista.
- **`h`** ou **`←`**: Voltar para o diretório pai.
- **`l`** ou **`→`** ou **`Enter`**: Entrar na pasta selecionada ou abrir arquivo.
- **`g` `g`**: Pular para o topo da lista.
- **`G`**: Pular para o final da lista.

---

## Seleção Múltipla de Arquivos

Você tem 3 formas de selecionar itens:

1. **Item por item (`Space`):**
   - Aperte a barra de espaço (`Space`) sobre o arquivo/pasta. Ele fica marcado com um indicador visual e o cursor avança para o próximo.
   - Pressionar `Space` novamente em um item marcado desfaz a seleção.
2. **Modo Visual em Bloco (`v`):**
   - Aperte **`v`** para ativar o modo visual.
   - Mova o cursor com `j`/`k` ou setas: todos os arquivos no caminho serão selecionados em bloco (como o `Shift + Clique`).
   - Pressione `v` novamente ou `Esc` para sair do modo visual.
3. **Selecionar Tudo (`Ctrl + A`):**
   - Seleciona todos os arquivos da pasta atual de uma vez.
   - Pressione `Esc` para desselecionar tudo.

---

## Como Mover Arquivos para Fora (Browser, Discord, etc.)

Como o Yazi roda dentro de um emulador de terminal Wayland (Kitty), você tem duas formas excelentes de enviar arquivos para navegadores ou outros aplicativos:

### Método 1: Clipboard Nativo (Ctrl+C / Ctrl+V — Mais Rápido)
A maioria dos navegadores modernos (Firefox, Chrome, Brave) e apps de chat (Discord, Telegram, Slack, WhatsApp Web) aceita colar o arquivo diretamente:
1. No Yazi, selecione os arquivos desejados com `Space` (ou posicione o cursor sobre ele).
2. Pressione **`Ctrl + c`** (ou `y` para colocar na área de transferência).
3. Vá na janela do navegador (no campo de mensagem ou de upload) e dê **`Ctrl + v`**. O navegador carrega o arquivo imediatamente.

### Método 2: Arrastar com Mouse (Drag and Drop 100% Nativo)
O Yazi possui suporte nativo a eventos de mouse ativados (`mouse_events = [ "click", "scroll", "drag" ]`):
- Você pode simplesmente clicar em um arquivo ou pasta no Yazi com o botão esquerdo do mouse e **arrastá-lo diretamente para a janela do seu navegador** (área de upload de arquivos, chat, etc.), soltando-o lá. Funciona de forma 100% nativa no Wayland sem necessidade de qualquer ferramenta adicional!

---

## Operações com Arquivos

- **Copiar:** `y` no(s) item(ns) selecionado(s).
- **Cortar / Mover:** `x` no(s) item(ns) selecionado(s).
- **Colar:** `p` no diretório de destino.
- **Deletar (Mover para Lixeira):** `d` (pressionar `d` confirma o envio à lixeira).
- **Deletar Permanentemente:** `D` (Shift+D).
- **Criar novo arquivo:** `a` (digite o nome e finalize com Enter; termine com `/` para criar diretório).
- **Renomear:** `r` (abre o prompt interativo para editar o nome).

---

## Busca e Filtragem Ultrarrápida

- **Filtrar na pasta atual:** Digite **`/`** e comece a digitar o nome. A lista é filtrada instantaneamente em tempo real. Pressione `Esc` para limpar o filtro.
- **Busca profunda via fzf (`Z`):** Digite **`Z`** (Shift+Z) para abrir o diálogo de busca rápida com o `fzf` e encontrar arquivos em qualquer subpasta recursivamente.
- **Localizar no arquivo (grep):** Digite **`s`** para buscar pelo conteúdo textual dos arquivos com `ripgrep`.

---

## Abas e Multitarefa

O Yazi suporta múltiplas abas sem poluir o desktop:
- **`t` `t`**: Cria uma nova aba na pasta atual.
- **`1`**, **`2`**, **`3`**, etc.: Alterna diretamente entre as abas abertas.
- **`w`**: Fecha a aba ativa.

---

## Estrutura de Configuração

- **Keymaps:** [`~/.config/yazi/keymap.toml`](file:///home/edu/.config/yazi/keymap.toml)
- **Configurações gerais:** `~/.config/yazi/yazi.toml`
- **Atalho do Hyprland:** [`~/.config/hypr/config/variables.lua`](file:///home/edu/.config/hypr/config/variables.lua) (`FILE_MANAGER = "kitty --class yazi -e yazi"`)
- **Regra de janela flutuante:** [`~/.config/hypr/config/windowrules.lua`](file:///home/edu/.config/hypr/config/windowrules.lua) (classe `yazi` abre centralizada com 45% largura e 55% altura — ajustado de 75%/80% para 60%/70% em 28/09/2026, reduzido para 45%/55% no mesmo dia a pedido do usuário).
