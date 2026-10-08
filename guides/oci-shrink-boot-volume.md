---
tags: [homelab, oracle, oci, cloud, tutorial, recovery]
---

# Reduzir um boot volume OCI (método + runbook do ybyra)

> **Por que existe:** a OCI **não reduz** boot/block volume — só **aumenta**. Quando a cota
> *Always Free* (200 GB) enche, a única saída é **recriar** o boot volume menor. Este guia
> documenta o método e o runbook aplicado ao **ybyra** (150 → 50 GB), pré-requisito para a
> captura da VM ARM. Canonizado 08/10/2026.

## Contexto

| Fato | Fonte |
|---|---|
| OCI **não encolhe** volume (só expande) | doc oficial + FAQ |
| Criar **imagem custom de instância em execução desliga a instância por vários minutos** | doc oficial |
| Boot volume mínimo = **50 GB** (ou o tamanho da imagem, o que for maior) | FAQ |
| Cota *Always Free*: **200 GB** totais (ybytu 50 + ybyra 150 = cheio) | medido via API |

**Objetivo:** liberar ≥ 50 GB para a ARM caber. Reduzindo o ybyra para 50 GB →
ybytu 50 + ybyra 50 = **100 GB** → **100 GB livres**.

## ⚠️ Realidade desta tenancy (medido 08/10/2026)

> **O método por imagem custom NÃO funciona aqui.** O limite `custom-image-count` da tenancy é
> **`0`** (escopo região) — o free tier **não permite criar imagens custom**:
> `oci compute image create` → `QuotaExceeded: maximum quota allowed for custom-image-count`.
> Não há imagens custom existentes (0). Logo, os passos 1–2 abaixo **não se aplicam**.

**O que sobra:** reconstruir o host do zero (imagem **Ubuntu de plataforma** + 50 GB, reinstalar
docker/tailscale, reentrar no Swarm, restaurar configs do NAS/cofre). Mais trabalhoso e com
**borda fora** durante a reconstrução — a menos que se faça o **failover** para o kavure antes.

> **Nota de estratégia:** a OCI **não encolhe** volume, **não** permite imagem custom nesta conta
> e **não** restaura backup em volume menor. Ou seja, **não existe** caminho "in-place" — só
> reconstrução. Reavaliar se vale reconstruir o ybyra, se convém **consolidar** (a ARM vira a
> borda) ou se a ARM é realmente necessária.

## O método

1. **Imagem custom** da instância (preserva SO + estado, mas **desliga** o host durante o processo).
2. **Verificar o tamanho da imagem** pela API (`oci compute image get` → `size-in-mbs`) **antes**
   de qualquer passo destrutivo. Se ≤ 50 GB, o launch de 50 GB é possível.
3. **Terminar** a instância antiga e **lançar** a nova a partir da imagem, com boot volume de 50 GB.

> Se a imagem **não** permitir 50 GB, o plano B é **reconstruir** o host do zero (imagem Ubuntu +
> reinstalar docker/tailscale + reentrar no Swarm + restaurar configs do NAS/cofre).

## Pré-requisitos (checar ANTES)

- [ ] **Backup do host OK** — `config-backup` verde e espelho no NAS atualizado
      (ver [`backups/config-backup.md`](../backups/config-backup.md)); `/etc` no bare repo (etckeeper).
- [ ] **Segredos no cofre** (`.env` não vão ao espelho — restaurar via sops).
- [ ] **Failover da borda** disponível (para zerar o downtime — ver abaixo).
- [ ] Janela combinada (a imagem custom **derruba** o host por vários minutos).

## Runbook do ybyra

### 0. Failover da borda para o kavure (opcional, ~zero downtime)

O stack `sae-edge` tem `proxy-standby`/`tunnel-standby`/`umami-standby` (replicas=0, nó com
`edge_backup=true` = **kavure**). No **manager (kavure)**:

```bash
# sobe os standby PRIMEIRO e valida o site
docker service scale sae-edge_proxy-standby=1 sae-edge_tunnel-standby=1 sae-edge_umami-standby=1
curl -sI https://sumaenima.chimaera-heptatonic.ts.net   # deve responder
# desliga os primários (ybyra)
docker service scale sae-edge_proxy=0 sae-edge_tunnel=0 sae-edge_umami=0
```

> ⚠️ **Validar antes:** esse failover é o procedimento previsto no `edge.yml`, mas
> **não havia registro de teste**. Se não validar, a borda fica fora durante a janela.

### 1. Imagem custom + checagem de tamanho

```bash
export T="$(/mnt/NVME_PCI/secrets/sops-decrypt.sh OCI_TENANCY_ID)"
INST=$(oci compute instance list -c "$T" --display-name ybyra --query 'data[0].id' --raw-output)

# ⚠️ desliga o ybyra por vários minutos
IMG=$(oci compute image create -c "$T" --instance-id "$INST" \
        --display-name "ybyra-shrink-$(date +%Y%m%d)" --wait-for-state AVAILABLE \
        --query 'data.id' --raw-output)

# verificação decisiva (antes de terminar qualquer coisa)
oci compute image get --image-id "$IMG" --query 'data."size-in-mbs"' --raw-output
```

### 2a. Se a imagem permitir 50 GB

```bash
BV=$(oci compute boot-volume list -c "$T" --query 'data[?contains("display-name",`ybyra`)].id' --raw-output)
oci compute instance terminate --instance-id "$INST" --preserve-boot-volume false --force
# lançar nova instância da imagem com 50 GB (shape/AD/network iguais)
```

### 2b. Se a imagem for 150 GB → plano B

Reconstruir do zero (imagem Ubuntu 24.04, 50 GB) + restaurar configs do NAS/cofre + reentrar no Swarm.

### 3. Fail back (voltar a borda para o ybyra)

```bash
docker service scale sae-edge_proxy=1 sae-edge_tunnel=1 sae-edge_umami=1
docker service scale sae-edge_proxy-standby=0 sae-edge_tunnel-standby=0 sae-edge_umami-standby=0
```

## Rollback / segurança

- Nada é apagado até a **imagem** existir e o **tamanho** ser verificado.
- Com o failover no kavure, o pior caso é a borda rodando no kavure até o ybyra voltar.
- Imagens custom **contam** para a cota de imagem (apagar depois de validado).

## Referências

- [`guides/oracle-oci-cli.md`](oracle-oci-cli.md) — OCI CLI/API no terminal
- [`servers/ybyra.md`](../servers/ybyra.md) · [`servers/ybytu.md`](../servers/ybytu.md)
- Doc: [Working with Boot Volumes](https://docs.oracle.com/iaas/Content/Block/Concepts/bootvolumes.htm) ·
  [Managing Custom Images](https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/managingcustomimages.htm)
