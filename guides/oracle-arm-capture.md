---
tags: [homelab, oracle, oci, cloud, tutorial, todo]
---

# Captura da VM ARM Always Free (A1.Flex) — design do loop

> Objetivo: capturar a **melhor máquina do free tier** da Oracle — a **`VM.Standard.A1.Flex`**
> em **2 OCPU / 12 GB** (o teto da cota *Always Free* desta tenancy). Como a capacidade de host
> está esgotada, é preciso um **loop de tentativas**. Desenhado em **08/10/2026**.

## O alvo (o "melhor do free tier")

| Item | Valor |
|---|---|
| Shape | **`VM.Standard.A1.Flex`** (Ampere ARM) |
| OCPU / RAM | **2 OCPU / 12 GB** (`standard-a1-core-count: available 2` · `memory: available 12`) |
| Imagem | Ubuntu 24.04 **aarch64** — `…qqxqqfkhlzjcneto533jgu7ey6nzlzlpt5kuh6cqtbldhy2bu2hq` |
| AD | `WdCV:SA-SAOPAULO-1-AD-1` (**único** da região) |
| Boot volume | 50 GB (default; cabe folgado) |
| IP público | **não** — o limite de 2 efêmeros está usado (ybytu + ybyra) → acesso pela **tailnet** |
| Subnet | `ocid1.subnet.…dibma` (a mesma dos outros) |

> A cota ARM é `available: 2` (núcleos) e `available: 12` (GB) — ou seja, **a cota existe**, o que
> falta é **capacidade de host** (`Out of host capacity`).

## Estratégia

- **Alvo único: `2 OCPU / 12 GB`.** **Sem plano B** — não capturamos shape menor (decisão
  canonizada 08/10/2026). O loop espera o que sobrar da cota cheia aparecer.
- **Ciclo de 2 min — e isso é o *teto* na prática.** Testamos **1 min** e a OCI respondeu
  **`TooManyRequests: Too many requests for the user`** (throttling por usuário). Ou seja: **mais
  rápido não vence a corrida — só bate no limite.** O script trata o 429 como normal (retenta no
  próximo ciclo, sem alarme). A capacidade, quando fura, fica **minutos** disponível — não segundos.
- **Sem IP público** (limite atingido) — o acesso é pela tailnet, então o host já nasce pronto
  para `tailscale up`.
- **Parada automática** ao capturar (arquivo-sentinela) → o timer não fica tentando à toa.
- **Aviso no ntfy** ao capturar (e em erro inesperado, para não falhar em silêncio).

## O script (`provisioning/scripts/arm-hunt`)

```bash
#!/bin/bash
# arm-hunt — captura a VM ARM Always Free (A1.Flex). Roda via hl-arm-hunt.timer.
set -euo pipefail

TENANCY="${ARM_TENANCY:-ocid1.tenancy.oc1..aaaaaaaad7bkoaf4ze5dqpncywag5fsktwnnqzjgrd5ktgbcmf6r7x5clokq}"
AD="${ARM_AD:-WdCV:SA-SAOPAULO-1-AD-1}"
SUBNET="${ARM_SUBNET:-ocid1.subnet.oc1.sa-saopaulo-1.aaaaaaaaf32oeak5kdzfyqic5b4y77uxnffxdlyh5dlw2e4pyiipv53dibma}"
IMAGE="${ARM_IMAGE:-ocid1.image.oc1.sa-saopaulo-1.aaaaaaaaqqxqqfkhlzjcneto533jgu7ey6nzlzlpt5kuh6cqtbldhy2bu2hq}"
KEYS_FILE="${ARM_KEYS_FILE:-/etc/arm-hunt/ssh_authorized_keys}"
OCPUS="${ARM_OCPUS:-2}"; MEMGB="${ARM_MEMGB:-12}"
NTFY="${ARM_NTFY:-http://ybytu:8083/alerts}"
STATE=/var/lib/arm-hunt; LOG=/var/log/arm-hunt.log

mkdir -p "$STATE"
[ -f "$STATE/done" ] && exit 0
log(){ echo "$(date '+%F %T') $*" >> "$LOG"; }
notify(){ curl -s -H "Title: $1" -H "Priority: $2" -H "Tags: $3" -d "$4" "$NTFY" >/dev/null 2>&1 || true; }

KEYS=$(cat "$KEYS_FILE" 2>/dev/null || true)
META=$(printf '{"ssh_authorized_keys":"%s"}' "$KEYS")

out=$(oci compute instance launch \
  --compartment-id "$TENANCY" --availability-domain "$AD" \
  --shape "VM.Standard.A1.Flex" \
  --shape-config "{\"ocpus\":$OCPUS,\"memoryInGBs\":$MEMGB}" \
  --image-id "$IMAGE" --subnet-id "$SUBNET" \
  --assign-public-ip false --boot-volume-size-in-gbs 50 \
  --display-name arm-free --metadata "$META" 2>&1) && rc=0 || rc=$?

if printf '%s' "$out" | grep -qi 'Out of host capacity'; then
  log "sem capacidade (A1 $OCPUS/$MEMGB)"; exit 0
fi
if [ "$rc" -eq 0 ] || printf '%s' "$out" | grep -q '"id"'; then
  id=$(printf '%s' "$out" | python3 -c 'import sys,json;print(json.load(sys.stdin)["data"]["id"])' 2>/dev/null || echo '?')
  touch "$STATE/done"
  log "CAPTURADA id=$id ($OCPUS/$MEMGB)"
  notify "🎉 ARM capturada" "high" "tada" "A1.Flex $OCPUS OCPU/$MEMGB GB — $id"
else
  log "erro: $out"
  notify "⚠️ arm-hunt: erro inesperado" "default" "warning" "$(printf '%s' "$out" | head -c 300)"
fi
```

### Units (`provisioning/systemd/`)

`hl-arm-hunt.service`:
```ini
[Unit]
Description=Homelab: arm-hunt (captura a VM ARM Always Free)
Wants=network-online.target
After=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/bin/arm-hunt
```
`hl-arm-hunt.timer`:
```ini
[Unit]
Description=A cada 2 min: arm-hunt
[Timer]
OnBootSec=2min
OnUnitActiveSec=2min
AccuracySec=1s
Persistent=true
[Install]
WantedBy=timers.target
```

## Rate limit da OCI (medido 08/10/2026)

Testado com timer de **1 min** → a API retornou **`TooManyRequests: Too many requests for the user`**.
**Conclusão:** o intervalo seguro é **≥ 2 min**. Aumentar a frequência **não** melhora a chance (é
throttled) e a disponibilidade dura minutos, então **2 min é o ponto**. O script ignora o 429
(não alerta; tenta de novo no próximo ciclo).

## Como as pessoas pegam (contexto)

- A maioria usa **loops de 1–5 min** (ou o Console manual) + **ntfy/Telegram** para saber na hora.
- Não há "reserva" no free tier (capacity reservations não valem para Always Free), então **polling
  é o único caminho**.
- Os que conseguem costumam pegar em **horários de baixa** (madrugada) ou após algum tempo de loop.
- **Vence quem estiver tentando** quando um slot vagar — não quem tentar mais rápido.

## Quando capturar: é automático? **Sim (08/10/2026)**

- **A criação é 100% automática** — o `arm-hunt` cria a instância (nome **`ybytyra`**, 50 GB, sem IP público).
- **A configuração TAMBÉM é automática** — via **cloud-init** (`--user-data-file`,
  `provisioning/cloud-init/ybytyra.yaml`), a máquina **nasce pronta**:
  1. Docker + `daemon.json` (rotação de log)
  2. **Tailscale** (entra na tailnet com a auth key do cofre, `--ssh`)
  3. Serviços padrão (config-as-code em `~/homelab/{svc}/compose.yml`): **autoheal, watchtower,
     node-exporter, promtail, glances, dockerproxy** (com os binds na tailnet e healthchecks)
  4. `etckeeper` (base do backup)
  5. aviso no ntfy `/alerts` ao terminar
- **O `arm-hunt` renderiza a auth key** do cofre (`sops-decrypt.sh TS_AUTH_KEY`) no cloud-init no
  momento do launch (testado: render + YAML válido).
- **Passo único manual (1 linha):** adicionar o alvo no **Prometheus do kavure**
  (`<ip-tailnet>:9100 # ybytyra` + o label no relabel). O resto (promtail → Loki) é automático.
- **Garantia:** a **captura** não é garantida (depende de capacidade); **uma vez capturada, a máquina
  é sua** (o free tier não a retoma). Enquanto não capturar, 100 GB seguem livres.

> **Nome `ybytyra`** (Tupi: *montanha/serra*) — mantém a família `yby*` das VMs Oracle
> (`ybytu` = vento, `ybyra` = árvore). Criar `servers/ybytyra.md` quando capturada.

## Status (08/10/2026) — **ATIVO no psicopompo**

- Script em `/usr/local/bin/arm-hunt` + **`hl-arm-hunt.timer` ativo** (dispara a cada 2 min).
- `/etc/arm-hunt/ssh_authorized_keys` (0600, root) com a chave pública do usuário.
- O unit define `HOME=/home/edu` e `PATH=…/.local/bin` — o `oci` é um *uv tool* do usuário
  (o serviço roda como root e sem isso dá `oci: command not found`).
- 1º disparo confirmado: **`sem capacidade (A1 2/12)`** (a Oracle recusa por capacidade, esperado).

## Onde rodar

**Recomendado:** **psicopompo** (onde vive a API key OCI + o CLI). A latência à API da Oracle não
é gargalo — a capacidade fica livre por minutos. *(Alternativa: o próprio ybyra, in-region, tem
latência de poucos ms — vantagem se a disputa for por segundos; exige materializar o config OCI
lá via `oci-restore.sh`.)*

## Pré-requisitos

- [ ] `oci` no PATH + `~/.oci/config` válido (ver [`oracle-oci-cli.md`](oracle-oci-cli.md)).
- [ ] `/etc/arm-hunt/ssh_authorized_keys` (0600) com a(s) chave(s) pública(s) do usuário.
- [ ] Coletar o OCID da instância capturada → **documentar em [`servers/ybyra.md`](../servers/ybyra.md)
      / novo `servers/`** e configurar (tailscale, docker) no passo seguinte.

## Riscos e cuidados

- **Alvo único `2/12`:** **sem fallback** — não capturamos shape menor (decisão 08/10/2026).
- **Cota:** enquanto a ARM não existir, `100 GB` livres. Capturada a 50 GB → **50 GB** livres.
- **IP público:** sem IP (limite). Se precisar de IP público, liberar um efêmero (parar uma VM)
  ou usar a tailnet (padrão).
- **Parar o loop depois:** `systemctl disable --now hl-arm-hunt.timer` (o `done` já evita
  tentativas, mas o timer segue disparando à toa).

## Referências

- [`guides/oracle-oci-cli.md`](oracle-oci-cli.md) — OCI CLI/API e os limites da tenancy
- [`guides/oci-shrink-boot-volume.md`](oci-shrink-boot-volume.md) — como liberamos a cota
- Doc Oracle: [Always Free](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm) ·
  [Creating an Instance](https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/launchinginstance.htm)
