---
tags: [meta, agents, governance, homelab]
---

# AGENTS.md — Mnemocine Homelab Governance Rules

Este repositório contém a documentação pública, manifestos arquiteturais e topologias de rede do **Homelab Mnemocine**.

Ao modificar qualquer arquivo deste repositório, siga estas regras obrigatórias de governança:

## 🔒 Regras de Segurança & Proteção de Segredos

1. **PROIBIÇÃO TOTAL DE SEGREDO EM CLARO (`SEC-SECRETS`)** — Nenhum arquivo contendo chaves privadas, senhas, tokens de API ou credenciais de produção deve ser commitado. Todos os exemplos devem usar valores fictícios ou referências a variáveis de ambiente (`.env.template`).

2. **PROIBIÇÃO DE ARQUIVOS ENCRIPTADOS REAIS NO PÚBLICO** — O arquivo `secrets.enc.env` do cofre SOPS/Age é estritamente proibido neste repositório público. Apenas `.env.template` deve estar presente.

3. **VERIFICAÇÃO OBRIGATÓRIA DO STÊNIOSENTINEL (REGRA 0)** — Antes de qualquer commit, é obrigatório executar `stenio --scope homelab --path .`. O Quality Gate deve aprovar com zero erros bloqueantes.

4. **INTEGRIDADE DE LINKS E NOMENCLATURA** — Todos os links markdown relativos devem apontar para documentos existentes. Arquivos de serviço devem residir em `services/`, servidores em `servers/`, e guias em `guides/`.

5. **DISCLAIMER PADRONIZADO NO README** — O `README.md` raiz deve manter o disclaimer padronizado de governança humana-IA:
   ```markdown
   <div align="center">

   > **Yes... This is a Vibe Coded project**
   >
   > Governed by 🤖 **StenioSentinel** (our Rust-based AI Governance Sentinel) with **Carlos Eduardo Rodrigues** ([@ceduardorodrig](https://github.com/ceduardorodrig)).

   </div>
   ```
