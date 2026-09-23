---
tags: [homelab, kde, plasma, tutorial, config, psicopompo]
---

# KDE Plasma — Applets de Rede e Volume quebrados após update (bug Kirigami)

## O Problema

Após uma atualização do CachyOS (KDE Plasma) que trouxe **kirigami 6.29.0** e **qt6 6.11.2**, os applets de **Rede** (`org.kde.plasma.networkmanagement`) e **Volume** (`org.kde.plasma.volume`) da bandeja param de carregar: clicar no ícone não abre o popup ("Sorry! There was an error loading Networks.").

Erros QML no journal (`journalctl --user`):

```
main.qml:60:25: Type PopupDialog unavailable
PopupDialog.qml:110:22: Type ConnectionListPage unavailable
ConnectionListPage.qml:26:5: Type Kirigami.InlineMessage unavailable
InlineMessage.qml:14:1: Type KT.InlineMessage unavailable
templates/InlineMessage.qml:187:51: Cannot assign object of type
  "Primitives.IconPropertiesGroup" to property of type
  "IconPropertiesGroup_QMLTYPE_*" as the former is neither the same as
  the latter nor a sub-class of it.
```

Afeta **qualquer** componente que use `Kirigami.InlineMessage` (rede, volume, FolderView do desktop), não só o applet de rede.

## Causa raiz (upstream)

- Bug **KDE #508377** (prioridade **HIGH**, aberto desde 08/2025, **sem fix**).
- Duplicatas: **#524515** (applet de rede, aberto 21/08/2026 com as MESMAS versões deste homelab), #521692, #521572.
- Gatilho: combinação `kirigami 6.29` + `qt6 6.11.2`. O ID do tipo muda entre sessões (`IconPropertiesGroup_QMLTYPE_326` → `_355`) — assinatura de **duplicação de tipo QML** (módulo carregado via qrc vs disco).
- Não é bug de configuração do usuário, nem de tema. A rede em si funciona (`nmcli`/`nmtui`).

## O que NÃO resolve (testado em 21-25/08/2026 no psicopompo)

| Tentativa | Resultado |
|---|---|
| Limpar caches QML (`~/.cache/plasmashell/qmlcache`, `kwin`, `systemsettings`, `qtshadercache-*`) + reiniciar plasmashell | Não resolve |
| Downgrade kirigami 6.29 → 6.28.0 | Não resolve (estrutura do QML idêntica) |
| Downgrade qt6-base + qt6-declarative 6.11.2 → 6.11.1 | **Espiral de ABI** (`libQt6Svg.so.6` exige `QtPrivate_6_11_2`) — revertido |
| Trocar para tema Breeze puro + limpar caches | Não resolve |

## O Fix (workaround confirmado no fórum CachyOS + validado aqui)

O `appletsrc` (config do layout do desktop/painéis) fica "envenenado" e faz o plasmashell re-injetar a duplicação de tipo QML. **Resetar o layout resolve.**

```bash
# 1. Backup (reversível — NUNCA usar rm direto)
mv ~/.config/plasma-org.kde.plasma.desktop-appletsrc \
   ~/.config/plasma-org.kde.plasma.desktop-appletsrc.bak-$(date +%Y%m%d)

# 2. Reiniciar o shell (gera layout padrão novo)
kquitapp6 plasmashell; sleep 3; kstart plasmashell

# 3. Verificar (deve dar 0)
journalctl --user _PID=$(pgrep -x plasmashell) --no-pager | grep -c "error when loading applet"
```

- **Desfazer:** `mv` do `.bak` de volta + reiniciar plasmashell.
- ⚠️ **Remove TODAS as customizações de painéis/widgets** (a fonte do fórum): você perde o layout e precisa reconstruir os widgets à mão. O backup permite reconstruir com paridade (mapa de widgets/sensores).
- ✅ **Preservado:** tema/cores/fontes/widget style (`kdeglobals`), kwin (`kwinrc`), atalhos (`kglobalshortcutsrc`) — o `appletsrc` só guarda layout de painéis/widgets.
- O autor do fix no fórum observou que a **correção definitiva virá num update de pacote** (aguardar kirigami/plasma/qt6 corrigirem o #508377).

## Aplicação neste homelab

- **Host:** psicopompo (CachyOS KDE — tema Catppuccin + Klassy).
- **Data:** 25/08/2026. Fix aplicado com sucesso; backup deletado após confirmação; layout sendo reconstruído manualmente.
- **Acompanhamento:** https://bugs.kde.org/show_bug.cgi?id=508377 — quando resolver, uma atualização normal restaura tudo (sem precisar do reset).
- **Fórum de origem:** discuss.cachyos.org — *Broken network and audio tray icons after update* (thread 34619).
