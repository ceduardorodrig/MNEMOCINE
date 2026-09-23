---
tags: [homelab, tutorial, hardware, usb, fat, storage]
---

# Hollyland FAT Fix — Dirty Bit / Read-Only em Dispositivos FAT32

## O Problema

Gravadores de áudio/vídeo como **Hollyland Lark Max, Lark M2 e similares** usam cartão SD ou memória interna formatada em **FAT32**. Quando o aparelho é desligado, ele simplesmente corta a energia — **não desmonta o sistema de arquivos**. Isso deixa o chamado **dirty bit** (bit de desmontagem suja) ativo no FAT32.

O Linux **respeita esse bit** e monta o dispositivo como **read-only (`ro`)** para evitar corrupção de dados. O resultado: você consegue ler os arquivos, mas **não consegue deletar, criar ou editar nada**.

Windows e Mac **ignoram** esse bit e montam como leitura-escrita normalmente — por isso o problema só aparece no Linux.

## A Solução — Automação Completa com UDEV + Systemd

Três componentes trabalham juntos para resolver isso **automaticamente** toda vez que você conectar um Hollyland:

| Componente | Função |
|---|---|
| **Regra udev** (`99-hollyland.rules`) | Detecta o dispositivo pelo vendor ID `3547` (Hollyland) + filesystem vfat |
| **Systemd service** (`hollyland-fix@.service`) | Executa o script de forma assíncrona (não trava a inicialização) |
| **Script** (`hollyland-fix.sh`) | Desmonta, roda `fsck.vfat -a` (auto, não-interativo) e limpa o dirty bit |

### Fluxo

1. Você conecta o Hollyland no USB
2. Udev detecta: `idVendor=3547` + `vfat` → dispara o systemd service
3. O service executa o script, que:
   - Aguarda 2 segundos (pra montagem inicial terminar)
   - Desmonta o dispositivo (lazy unmount)
   - Roda `fsck.vfat -a` → limpa dirty bit
4. O sistema (udisks2) **remonta automaticamente** como `rw`

### Por que não usar `RUN` no udev?

O `RUN` do udev executa em um namespace isolado — mounts feitos lá não são visíveis pro resto do sistema. A abordagem correta é `TAG+="systemd"` + `ENV{SYSTEMD_WANTS}`, que dispara um systemd service no namespace global.

---

## Arquivos do Sistema

### `/usr/local/bin/hollyland-fix.sh`

```bash
#!/bin/bash
# hollyland-fix.sh — Limpa dirty bit FAT32 em dispositivos Hollyland
# Acionado por udev → systemd service quando um dispositivo Hollyland
# com filesystem vfat é conectado.

set -euo pipefail

DEVICE="/dev/$1"
LOGTAG="hollyland-fix"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | logger -t "$LOGTAG"
}

log "=== Iniciando fix para $DEVICE ==="

FSTYPE=$(blkid -o value -s TYPE "$DEVICE" 2>/dev/null || true)
if [ "$FSTYPE" != "vfat" ]; then
    log "  Ignorado: tipo=$FSTYPE (não é vfat)"
    exit 0
fi

sleep 2

MOUNTPOINT=$(findmnt -n -o TARGET "$DEVICE" 2>/dev/null || true)
if [ -n "$MOUNTPOINT" ]; then
    log "  Desmontando $DEVICE de $MOUNTPOINT"
    umount -l "$DEVICE" 2>/dev/null || true
    sleep 1
fi

log "  Rodando fsck.vfat -a $DEVICE"
OUTPUT=$(fsck.vfat -a "$DEVICE" 2>&1) || true
echo "$OUTPUT" | logger -t "$LOGTAG"

if echo "$OUTPUT" | grep -qi "dirty bit"; then
    log "  dirty bit removido com sucesso"
fi
if echo "$OUTPUT" | grep -qi "changes"; then
    log "  alterações foram escritas no filesystem"
fi

log "  Finalizado. A remontagem automática deve ocorrer em rw."
```

### `/etc/udev/rules.d/99-hollyland.rules`

```
# 99-hollyland.rules — Hollyland Lark Max / Lark / Wireless Mic
#
# Match por vendor 3547 cobre TODOS os produtos Hollyland
# (Lark Max, Lark M2, Lark M1, Lark 150, etc).
#
# Filtros adicionais:
#   - SUBSYSTEM=="block" → só dispositivos de bloco
#   - ENV{ID_FS_TYPE}=="vfat" → só FAT32
#   - ATTRS{idVendor}=="3547" → só Hollyland

ACTION=="add", SUBSYSTEM=="block", KERNEL=="sd*", \
  ENV{ID_FS_TYPE}=="vfat", \
  ATTRS{idVendor}=="3547", \
  TAG+="systemd", ENV{SYSTEMD_WANTS}+="hollyland-fix@$kernel.service"
```

### `/etc/systemd/system/hollyland-fix@.service`

```ini
[Unit]
Description=Clear FAT32 dirty bit on Hollyland device (%I)
Documentation=https://github.com/usbids/usbids/blob/master/usb.ids
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/hollyland-fix.sh %I
TimeoutStartSec=30
StandardOutput=journal
StandardError=journal
```

---

## Boas Práticas Gerais para FAT32 no Linux

### 1. Limitar Write Cache de USBs (`99-usb-fat-tuning.rules`)

Por padrão, o Linux usa até **20% da RAM** como cache de escrita (dirty pages). Isso significa que quando você copia um arquivo pra um pendrive, o "copiado" aparece **antes dos dados irem pro dispositivo** — eles estão no cache da RAM. Se você remover o dispositivo nesse momento, os dados são perdidos.

Esta regra udev limita o cache para **5% por dispositivo USB removível** e ativa `strict_limit`:

```
# /etc/udev/rules.d/99-usb-fat-tuning.rules
ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="sd*", \
  ATTR{removable}=="1", ENV{ID_FS_TYPE}=="vfat", \
  ATTR{bdi/max_ratio}="5", ATTR{bdi/strict_limit}="1"
```

**Efeito:** o cache máximo para cada USB cai de 20% pra 5% da RAM. Dados chegam no dispositivo mais rápido. A cópia ainda é em `async` (performance não é drasticamente afetada como com `sync`).

### 2. Ejetar / Sincronizar

Sempre que possível, ejete o dispositivo antes de remover:

```bash
# Via comando
udisksctl unmount -b /dev/sdd1
udisksctl power-off -b /dev/sdd

# Ou via Nautilus / qualquer file manager → "Eject" / "Unmount"
```

Se precisar garantir que os dados foram pro disco:

```bash
sync
# ou para um dispositivo específico
sync /dev/sdd
```

### 3. Opção `flush` no Mount

`flush` é uma opção de montagem do vfat que faz com que os dados sejam liberados pro disco mais cedo que o normal (sem ser tão agressivo quanto `sync`). Por padrão, udisks2 já monta vfat com `flush` — você pode verificar com:

```bash
mount | grep vfat
```

Se por algum motivo não estiver usando `flush`, adicione:

```bash
sudo mount -o remount,flush /run/media/edu/SEU_DISPOSITIVO
```

> ⚠️ **Não use `sync`** para vfat — deixa a gravação extremamente lenta e reduz a vida útil de mídias flash.

### 4. Quando Nada disso Funciona

Se mesmo com o dirty bit limpo o dispositivo continuar `ro`:

1. Verifique se há **chave física de write-protect** no cartão SD / adaptador
2. Verifique **erros de hardware**:
   ```bash
   sudo dmesg | grep -i "i/o error\|buffer I/O\|device error"
   ```
3. O cartão pode estar **no fim da vida útil** — controladores NAND forçam modo `ro` quando a mídia não é mais confiável. Substitua o cartão.

---

## Instalação / Reinstalação

Se você ~~formatar o PC~~ ~~mudar de distro~~ ~~explodir tudo~~ precisar reaplicar:

```bash
# 1. Copiar script
sudo cp /tmp/hollyland-fix.sh /usr/local/bin/hollyland-fix.sh
sudo chmod +x /usr/local/bin/hollyland-fix.sh

# 2. Copiar regras udev
sudo cp /tmp/99-hollyland.rules /etc/udev/rules.d/
sudo cp /tmp/99-usb-fat-tuning.rules /etc/udev/rules.d/

# 3. Copiar service
sudo cp /tmp/hollyland-fix@.service /etc/systemd/system/

# 4. Recarregar tudo
sudo udevadm control --reload-rules
sudo systemctl daemon-reload

# 5. Testar (opcional — com dispositivo conectado)
sudo journalctl -f -u hollyland-fix@*
```

### Recuperação Manual (sem automação)

Se o sistema não estiver configurado e você precisar fazer na mão:

```bash
# 1. Identificar o dispositivo
lsblk

# 2. Desmontar
sudo umount /dev/sdd

# 3. Rodar fsck
sudo fsck.vfat -a /dev/sdd

# 4. Remover e reconectar o dispositivo
```

---

## Referências

- [Linux Kernel — vfat documentation](https://www.kernel.org/doc/html/latest/filesystems/vfat.html)
- [USB ID Repository — Hollyland](https://github.com/usbids/usbids)
- [Arch Wiki — udev](https://wiki.archlinux.org/title/Udev)
- [Arch Wiki — FAT](https://wiki.gentoo.org/wiki/FAT)
- [Udisks2 mount options](https://storaged.org/doc/udisks2-api/latest/mount_options.html)
