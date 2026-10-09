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

## Runbook de reconstrução (o caminho real desta conta)

> Como **não há imagem custom**, a redução é feita **reconstruindo** o host. O alvo é deixar a
> nova instância **idêntica do lado de fora**: mesmo **nome**, mesmo **IP privado** e — o que mais
> importa — mesmo **IP/nome na tailnet** (preservando o estado do Tailscale). O que muda é só o
> **IP público** (efêmero), que nada funcional usa.

### Fase 1 — Preservar (zero downtime)
1. **Identidade Tailscale:** copiar `/var/lib/tailscale/` (o `tailscaled.state`) para o NAS.
2. **Configs:** rodar `config-backup` (já OK) + confirmar `/etc` no bare repo (etckeeper).
3. **Inventário** (capturado em 08/10): shape `VM.Standard.E2.1.Micro` · AD `WdCV:SA-SAOPAULO-1-AD-1`
   · FD `FAULT-DOMAIN-2` · subnet `ocid1.subnet…dibma` · privado `10.0.0.40` · nome `ybyra` ·
   imagem `Canonical Ubuntu 24.04`.
4. **Chave SSH da instância** (metadata `ssh_authorized_keys`) — reaplicar no launch.

### Fase 2 — Janela
5. (Opcional) **Failover** da borda para o kavure → borda no ar durante o resto.
6. **Terminar** o ybyra → libera 150 GB:
   `oci compute instance terminate --instance-id <Y> --preserve-boot-volume false --force`
7. **Criar** a nova instância (50 GB), **mesmo IP privado** e **mesmo nome**:
   ```bash
   oci compute instance launch -c "$T" \
     --availability-domain "WdCV:SA-SAOPAULO-1-AD-1" \
     --shape "VM.Standard.E2.1.Micro" --image-id <ubuntu-24.04-image-ocid> \
     --subnet-id ocid1.subnet.oc1.sa-saopaulo-1.aaaaaaaaf32oeak5kdzfyqic5b4y77uxnffxdlyh5dlw2e4pyiipv53dibma \
     --private-ip 10.0.0.40 --assign-public-ip true --boot-volume-size-in-gbs 50 \
     --display-name ybyra \
     --metadata '{"ssh_authorized_keys":"<chave capturada>"}' --wait-for-state RUNNING
   ```

### Fase 3 — Restaurar
8. **Tailscale:** instalar, parar o serviço, **restaurar `/var/lib/tailscale/`**, subir →
   **mesmo IP `100.66.224.34`** e mesmo nome na tailnet.
9. **Docker:** instalar o engine + reentrar no Swarm:
   `docker swarm join --token <worker-token> <kavure>:2377` (token via `docker swarm join-token worker` no manager).
10. **Configs:** restaurar `/home/ubuntu/homelab/*` do NAS + o `.env` do cofre
    (`sops-decrypt.sh` → `sumaenima.env`) e `docker compose up -d` nos standalone.
11. **Rótulo do nó:** `docker node update --label-add role=primary ybyra` → o Swarm reagenda
    `proxy`/`tunnel`/`umami` de volta ao ybyra.

### Fase 4 — Validar
12. `tailscale status` · `docker node ls` · Funnel (`curl -sI https://sumaenima.chimaera-heptatonic.ts.net`)
    · healthchecks. Então **fail back** (se houve failover) e liberar a ARM.

## O método (não se aplica a esta conta — custom-image-count = 0)

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

> **Testado em 08/10/2026 (após rotacionar a key):** o failover **funciona** — `proxy-standby`,
> `umami-standby` e `tunnel-standby` sobem no kavure, e o Funnel do standby responde **HTTP 200**
> (`https://sumaenima-1.chimaera-heptatonic.ts.net`), com o primário intacto (200 o tempo todo).
> ⚠️ **Mas o URL muda:** o standby registra o nó **`sumaenima-1`** (o nome `sumaenima` é do
> primário), então o Funnel **canônico não é preservado** no failover — durante a janela os
> clientes precisam usar o URL `-1`.
> ⚠️ O nó **`sumaenima-1` fica registrado** mesmo com o serviço em 0 → **deletar no console**, ou
> usar auth key **efêmera** (`--ephemeral`) para ele sumir sozinho.
> O teste é **100% reversível** (o primário nunca foi tocado).

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
