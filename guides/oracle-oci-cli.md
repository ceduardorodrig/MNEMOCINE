---
tags: [homelab, oracle, oci, cloud, tutorial, sops]
---

# Oracle Cloud Infrastructure (OCI) — gestão via CLI/API

> **Escopo canonizado em 08/10/2026:** as VMs Oracle do homelab (**ybytu**, **ybyra**) passam a
> ser **gerenciáveis por API, direto do terminal**, a partir do **psicopompo**, com o **OCI CLI**.
> Cobre: inventário/estado das instâncias, boot/block volumes, rede (subnets/VNICs), imagens e a
> **captura da VM ARM Always Free**. Antes disso, a operação das VMs Oracle dependia do console web.

## Arquitetura

```
psicopompo (terminal)   ──API key RSA (assinatura)──►   OCI · sa-saopaulo-1
  ~/.oci/config + chave privada                          tenancy ceduardorodrig
  (materializados do cofre sops)                         ├── ybytu  (VM.Standard.E2.1.Micro)
                                                         └── ybyra  (VM.Standard.E2.1.Micro)
```

- **Autenticação:** **API key RSA** (assinatura das requisições) — **não** *instance principal*.
  A chave foi gerada e permanece no psicopompo; só a **pública** foi enviada à OCI.
- **Credenciais:** no **cofre sops** (`OCI_*` em `secrets.enc.env`), nunca em claro.
- **Região:** `sa-saopaulo-1` (home region da tenancy — a *Always Free* é **home-region-only**).

## Credenciais (cofre sops)

| Variável | Conteúdo |
|---|---|
| `OCI_USER_ID` | OCID do usuário `ceduardorodrig@gmail.com` |
| `OCI_TENANCY_ID` | OCID da tenancy |
| `OCI_FINGERPRINT` | identificador da API key (`46:b4:f0:…`) |
| `OCI_REGION` | `sa-saopaulo-1` |
| `OCI_PRIVATE_KEY_B64` | chave privada (PEM, com o rótulo de segurança da Oracle), em base64 |

**Restaurar** (reconstrói `~/.oci/config` + a chave privada):

```bash
/mnt/NVME_PCI/secrets/oci-restore.sh
```

> Roda no **psicopompo** (onde está a chave age privada). Não exibe valores.
> Detalhe do cofre: [`guides/secrets-centralizados.md`](secrets-centralizados.md).

## Instalação do CLI

O `oci` é uma ferramenta **Python** da Oracle (não há CLI oficial em Rust). Instalado
**isolado** via `uv`, fixado em **Python 3.11** — a partir do 3.12 o interpretador promove a
`SyntaxWarning` um *escape* inválido no módulo `compute` do `oci-cli` (bug *upstream*, marcado
`# noqa: W605`); o 3.11 mantém a saída limpa:

```bash
uv tool install oci-cli --python 3.11
# binário: ~/.local/bin/oci  (versão 3.94.2 em 08/10/2026)
```

## Comandos úteis

```bash
# tenancy (evita repetir o OCID)
export T="$(/mnt/NVME_PCI/secrets/sops-decrypt.sh OCI_TENANCY_ID)"

# inventário das VMs
oci compute instance list --compartment-id "$T" --output table \
  --query 'data[].{nome:"display-name", estado:"lifecycle-state", shape:shape, ad:"availability-domain"}'

# detalhe de uma instância
oci compute instance get --instance-id <ocid>

# boot volumes / block volumes
oci bv boot-volume list --compartment-id "$T" --output table

# imagens disponíveis
oci compute image list --compartment-id "$T" --output table

# disponibilidade de cota (ex.: núcleos ARM A1) — neste limite o AD é obrigatório
oci limits resource-availability get --service-name compute \
  --limit-name standard-a1-core-count --compartment-id "$T" \
  --availability-domain 'WdCV:SA-SAOPAULO-1-AD-1'
```

## Limites da tenancy (free tier, medido 08/10/2026)

| Limite | Valor | Consequência |
|---|---|---|
| Armazenamento de bloco | **200 GB** | ybytu 50 + ybyra 150 = **cheio**; sem espaço para a ARM |
| `custom-image-count` | **0** | **impossível** criar imagem custom (sem clone/shrink) |
| Cota ARM A1 | 2 OCPU / 12 GB (`available: 2`) | a cota existe; falta **capacidade de host** |
| ADs na região | 1 (`WdCV:SA-SAOPAULO-1-AD-1`) | sem alternância de AD |

> Consequência prática: como não há imagem custom e a OCI não encolhe volume, **reduzir o ybyra
> exige reconstrução** — ver [`oci-shrink-boot-volume.md`](oci-shrink-boot-volume.md).

## Por que isto importa — captura da ARM

A cota **Always Free ARM** (`VM.Standard.A1.Flex`) em 2026 é de **2 OCPU / 12 GB** na home
region. Medido via API (08/10/2026): `standard-a1-core-count` → **`available: 2, used: 0`**
(a cota existe), e a região tem **um único AD** (`WdCV:SA-SAOPAULO-1-AD-1`). O que falta é
**capacidade de host** — a criação retorna *"Out of host capacity"* e só sai com **retry em
loop**. Com a API key, isso vira um **loop no terminal** (rodando no `ybyra`), alternando os
shapes 1/6 e 2/12, **sem fault domain** e **sem IP público**, com aviso no **ntfy** ao
conseguir. Contexto e plano: [`servers/ybyra.md`](../servers/ybyra.md).

## Decisões e histórico

- **08/10/2026 — canonizado:** API key RSA gerada no **psicopompo** (a privada nunca saiu daqui);
  a pública foi enviada via **Cloud Shell** (`oci iam user api-key upload`) — atalho que evita
  depender da UI do console (a tela "Resources → API keys" não aparece em todas as contas).
  Fingerprint `46:b4:f0:…`; a chave ficou **ACTIVE** no usuário.
- **Por que API key e não *instance principal*:** o instance principal exigiria Dynamic Group +
  Policy **e** só valeria de dentro do `ybyra`. A API key gerencia a conta **de qualquer host**
  (o psicopompo), que é o objetivo. O Dynamic Group/Policy ficou **dispensado**.

## Segurança

- A chave privada existe **apenas** no psicopompo (modo `600`) e no **cofre cifrado** — nunca
  numa nota do vault, nunca em host Oracle.
- O **rótulo de segurança** no fim do PEM habilita o *secret scanning* da Oracle (aviso caso a
  chave apareça num repositório público).
- **Revogar:** apagar a API key no console (*User settings → Tokens and keys → API keys*).
  Nada mais depende dela.

## Referências

- [`guides/secrets-centralizados.md`](secrets-centralizados.md) — cofre sops/age (onde vive a chave)
- [`servers/ybyra.md`](../servers/ybyra.md) · [`servers/ybytu.md`](../servers/ybytu.md) — as duas VMs
- Doc oficial: [Required Keys and OCIDs](https://docs.oracle.com/iaas/Content/API/Concepts/apisigningkey.htm)
