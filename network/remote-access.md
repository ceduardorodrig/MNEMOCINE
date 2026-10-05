---
tags: [homelab, network, storage]
---

# Acesso Remoto aos Servidores via File Managers (SFTP)

Metodologia canônica e unificada para acessar os sistemas de arquivos remotos dos servidores do homelab (`kuaray`, `kavure`) a partir do **Psicopompo**, compatível simultaneamente com o **Dolphin** (KDE) e o **Cosmic Files** (COSMIC Desktop).

## Princípios

1. **Protocolo Padrão SFTP:** Não usar `sshfs` montado manualmente nem abstrações proprietárias (`remote:/`). O protocolo `sftp://` é nativo, assíncrono, suporta reconexão automática e respeita as credenciais de `~/.ssh/config`.
2. **Autenticação Transparente via Chaves SSH:**
   - O `~/.ssh/config` define os aliases `Host kuaray` e `Host kavure` com chave Ed25519 (`~/.ssh/id_ed25519`).
   - O `ssh-agent` fornece a chave sem necessidade de digitar senha a cada acesso.
3. **Padrão Multi-Desktop:**
   - **Cosmic Files (GIO/GVFS):** Lê bookmarks de `~/.config/gtk-3.0/bookmarks` e monta em `/run/user/1000/gvfs/sftp:host={host}` via `gio mount sftp://{host}/`.
   - **Dolphin (KIO):** Lê bookmarks de `~/.local/share/user-places.xbel` com a tag `<bookmark href="sftp://{host}/">`.

## Configuração nos File Managers

### 1. Cosmic Files (`~/.config/gtk-3.0/bookmarks`)

```text
sftp://kuaray/ Kuaray (Root)
sftp://kavure/ Kavure (Root)
```

Montagem sob demanda em linha de comando (se necessário para scripts):
```bash
gio mount sftp://kuaray/
gio mount sftp://kavure/
```

### 2. Dolphin (`~/.local/share/user-places.xbel`)

As entradas são cadastradas com esquema `sftp://`:
```xml
<bookmark href="sftp://kuaray/">
  <title>Kuaray (Root)</title>
  <info>
    <metadata owner="http://freedesktop.org">
      <bookmark:icon name="folder-remote"/>
    </metadata>
  </info>
</bookmark>
<bookmark href="sftp://kavure/">
  <title>Kavure (Root)</title>
  <info>
    <metadata owner="http://freedesktop.org">
      <bookmark:icon name="folder-remote"/>
    </metadata>
  </info>
</bookmark>
```

## Sanitização Realizada (04/10/2026)

- Removida a entrada legada `remote:/kuaray-root` no Dolphin.
- Removidos registros órfãos de montagem `fuse.sshfs` em `/home/edu/kuaray` no `user-places.xbel`.
- Cadastradas as URIs canônicas `sftp://kuaray/` e `sftp://kavure/` em ambos os navegadores.
