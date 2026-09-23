---
tags: [homelab, meta]
---

# Open-Source Acknowledgments — Homelab Mnemocine

A infraestrutura do Homelab Mnemocine é operada com base em projetos e tecnologias de código aberto mantidos pela comunidade global. Agradecemos e reconhecemos os seguintes componentes fundamentais que sustentam nossos servidores e serviços:

## Sistemas Operacionais, Armazenamento & Kernel

- **[CachyOS](https://cachyos.org/)** / **[Arch Linux](https://archlinux.org/)** (GPL) — Sistema operacional com kernel BORE/EEVDF otimizado com compilações x86-64-v3/v4 para o nó primário `psicopompo`
- **[Ubuntu Server](https://ubuntu.com/)** (GPL) — Distribuição base para os nós de borda e serviços (`kavure`, `ybytu`, `ybyra`)
- **[Linux Mint](https://linuxmint.com/)** (GPL) — Distribuição desktop/servidor utilizada no nó standby `kuaray` (versão 22.3 Zena)
- **[Btrfs](https://btrfs.readthedocs.io/)** (GPL) — Sistema de arquivos com snapshots copy-on-write e compressão zstd
- **[Snapper](http://snapper.io/)** (GPL-2.0) — Gerenciamento automatizado de snapshots btrfs pré/pós transações
- **[Restic](https://restic.net/)** (BSD-2-Clause) — Backup criptografado e deduplicado para o storage NAS
- **[NFSv4](https://datatracker.ietf.org/doc/html/rfc7530)** (IETF Standard) — Protocolo de compartilhamento de arquivos em rede com montagens soft resilientes

## Rede, Segurança & Criptografia

- **[Tailscale](https://tailscale.com/)** (BSD-3-Clause) — Malha WireGuard segura conectando todos os nós, exit nodes e funnels
- **[AdGuard Home](https://adguard.com/adguard-home.html)** (GPLv3) & **[Pi-hole](https://pi-hole.net/)** (EUPL) — Servidores DNS recursivos locais com bloqueio de anúncios e rastreamento
- **[SOPS](https://github.com/getsops/sops)** (MPL-2.0) & **[Age](https://github.com/FiloSottile/age)** (BSD-3-Clause) — Criptografia de segredos centralizados e variáveis de ambiente
- **[Nginx](https://nginx.org/)** (2-Clause BSD) — Proxy reverso e terminação TLS
- **[Syncthing](https://syncthing.net/)** (MPL-2.0) — Sincronização descentralizada de dados entre psicopompo, kuaray e dispositivos móveis

## Containerização & Serviços Ativos

- **[Docker & Docker Compose](https://www.docker.com/)** (Apache 2.0) — Execução e orquestração de microserviços em containers
- **[Home Assistant](https://www.home-assistant.io/)** (Apache 2.0) — Plataforma de automação residencial
- **[Navidrome](https://www.navidrome.org/)** (GPLv3) — Servidor e streamer de música pessoal
- **[Calibre-Web](https://github.com/janeczku/calibre-web)** (GPLv3) — Leitor e gerenciador de acervo bibliográfico
- **[Prowlarr](https://prowlarr.com/)**, **[Lidarr](https://lidarr.audio/)**, **[Transmission](https://transmissionbt.com/)** (GPL) — Gerenciamento e indexação multimídia
- **[Homepage](https://gethomepage.dev/)** (GPLv3) — Painel e dashboard visual do homelab
- **[SearXNG](https://github.com/searxng/searxng)** (AGPLv3) — Mecanismo de metabusca focado em privacidade
- **[ChangeDetection.io](https://changedetection.io/)** (Apache 2.0) — Monitoramento automatizado de mudanças na web
- **[Watchtower](https://containrrr.dev/watchtower/)** (Apache 2.0) — Atualização controlada de containers

## Ferramentas de Terminal & Linters Rust

O homelab adota a política obrigatória de ferramentas Rust de alta performance no terminal:
- **`eza`** (GPL-3.0) — Alternativa moderna ao `ls`
- **`bat`** (Apache-2.0 / MIT) — Leitura de arquivos com syntax highlight
- **`ripgrep` (`rg`)** (Unlicense / MIT) — Busca textual recursiva ultrarrápida
- **`fd`** (Apache-2.0 / MIT) — Busca de arquivos e diretórios
- **`sd`** (MIT) — Substituição de texto intuitiva
- **`delta`** (MIT) — Visualizador de diffs e commits
- **`dust`** (Apache-2.0) & **`duf`** (MIT) — Análise de espaço e uso de disco
- **`xh`** (MIT) — Cliente HTTP amigável
- **`bottom` (`btm`)** (MIT) & **`procs`** (MIT) — Monitor de processos e recursos
- **[StenioSentinel](https://github.com/ceduardorodrig/STENIO-SENTINEL)** (Proprietary / MIT) — Motor universal de governança estática e infraestrutura

## Serviços e Tecnologias Aposentadas

Documentamos para fins de rastreabilidade os serviços descontinuados do homelab:
- *Kavita* (aposentado da stack de leitura)
- *Duplicati* (substituído pela cadeia Restic + Snapper + Btrfs)
- *Scripts Python legados de steniocheck no ybyra* (substituídos pelo StenioSentinel nativo em Rust)
