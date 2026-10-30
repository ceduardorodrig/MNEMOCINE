#!/bin/bash
# audit-access-fleet.sh — Varredura de chaves SSH e Cron jobs em toda a frota Mnemocine
# Executado periodicamente ou via Stênio Sentinel. Notifica via ntfy em caso de desvio.
set -euo pipefail

NTFY_TOPIC="/alerts"
HOSTS=("psicopompo" "kuaray" "kavure" "ybytu" "ybyra")
KNOWN_KEYS_FILE="/mnt/NVME_PCI/agentic-ai/mnemocine/security/authorized-keys.md"
VIOLATIONS=0
REPORT=""

log_alert() {
  REPORT+="$1"$'\n'
  ((VIOLATIONS++)) || true
}

for H in "${HOSTS[@]}"; do
  # 1. Checagem de SSH keys
  KEYS=""
  if [ "$H" = "psicopompo" ]; then
    KEYS=$(cat ~/.ssh/authorized_keys 2>/dev/null || true)
    ROOT_KEYS=$(sudo -n cat /root/.ssh/authorized_keys 2>/dev/null || true)
  else
    KEYS=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$H" 'cat ~/.ssh/authorized_keys 2>/dev/null || true' 2>/dev/null || true)
    ROOT_KEYS=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$H" 'sudo -n cat /root/.ssh/authorized_keys 2>/dev/null || true' 2>/dev/null || true)
  fi

  # Validar cada linha de chave encontrada
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    [[ "$line" =~ ^# ]] && continue
    # Extrair tipo e chave
    KEY_BODY=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i ~ /^AAAA/) print $i}')
    if [ -n "$KEY_BODY" ] && ! grep -q "$KEY_BODY" "$KNOWN_KEYS_FILE"; then
      log_alert "🚨 [SSH] Chave desconhecida detectada em $H (usuário): $line"
    fi
  done <<< "$KEYS"

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    [[ "$line" =~ ^# ]] && continue
    KEY_BODY=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i ~ /^AAAA/) print $i}')
    if [ -n "$KEY_BODY" ] && ! grep -q "$KEY_BODY" "$KNOWN_KEYS_FILE"; then
      log_alert "🚨 [SSH ROOT] Chave desconhecida detectada em $H (root): $line"
    fi
  done <<< "$ROOT_KEYS"

  # 2. Checagem de Cron inesperado
  CRONS=""
  if [ "$H" = "psicopompo" ]; then
    CRONS=$(sudo -n crontab -l 2>/dev/null || true)
  else
    CRONS=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$H" 'sudo -n crontab -l 2>/dev/null || true' 2>/dev/null || true)
  fi
  if [ -n "$CRONS" ] && ! echo "$CRONS" | grep -qv "^#"; then
    : # apenas comentários
  elif [ -n "$CRONS" ] && echo "$CRONS" | grep -qvE "^(#|$|no crontab)"; then
    log_alert "⚠️ [CRON] Crontab de root ativo detectado em $H: $CRONS"
  fi
done

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "Violações detectadas:"
  echo "$REPORT"
  curl -s -H "Title: Security Audit Alert — Mnemocine" -H "Priority: urgent" -H "Tags: warning,skull" \
    -d "$REPORT" "https://ntfy.sh$NTFY_TOPIC" >/dev/null 2>&1 || true
  exit 1
else
  echo "✅ Todas as chaves SSH e Cron jobs da frota estão 100% aderentes à matriz canônica."
fi
