#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# monitor-demo.sh — Мониторинг демо-бота Kent
# Проверяет: healthz, процесс, диск, память.
# Отправляет алерты оператору через Telegram.
# Собирает бизнес-метрики из логов.
#
# Cron: */5 * * * * /home/kent/monitor-demo.sh
# ============================================================

OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
GATEWAY_URL="http://localhost:18789/healthz"
DISK_THRESHOLD_GB=5
MEM_THRESHOLD_PCT=90
LOG_DIR="${OPENCLAW_HOME}/logs"
LOG_FILE="${LOG_DIR}/demo.log"

VERBOSE=false
[[ "${1:-}" == "--verbose" ]] && VERBOSE=true

# --- Загружаем .env ---
ENV_FILE="${OPENCLAW_HOME}/.env"
if [[ -f "$ENV_FILE" ]]; then
    set +e; source "$ENV_FILE"; set -e
fi

OPERATOR_TELEGRAM_BOT_TOKEN="${OPERATOR_TELEGRAM_BOT_TOKEN:-}"
OPERATOR_TELEGRAM_CHAT_ID="${OPERATOR_TELEGRAM_CHAT_ID:-}"

HOSTNAME_LABEL=$(hostname 2>/dev/null || echo "kent-demo")
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
FAILURES=()

verbose() { $VERBOSE && echo "$1" || true; }
fail()    { FAILURES+=("$1"); verbose "СБОЙ: $1"; }
ok()      { verbose "OK: $1"; }

# === Проверка 1: Gateway health ===
if curl -sf --max-time 5 "$GATEWAY_URL" >/dev/null 2>&1; then
    ok "Gateway healthz доступен"
else
    fail "Gateway healthz не отвечает (${GATEWAY_URL})"
fi

# === Проверка 2: Процесс Gateway ===
if pgrep -f "openclaw.*gateway" >/dev/null 2>&1; then
    ok "Процесс Gateway запущен"
else
    fail "Процесс Gateway не найден"
fi

# === Проверка 3: Systemd сервис ===
if systemctl is-active kent-demo >/dev/null 2>&1; then
    ok "Сервис kent-demo active"
else
    fail "Сервис kent-demo не active"
fi

# === Проверка 4: Свободное место ===
if command -v df >/dev/null 2>&1; then
    FREE_KB=$(df -k "$HOME" | awk 'NR==2 {print $4}')
    FREE_GB=$(( FREE_KB / 1048576 ))
    if [[ "$FREE_GB" -lt "$DISK_THRESHOLD_GB" ]]; then
        fail "Мало места: ${FREE_GB} GB свободно (порог: ${DISK_THRESHOLD_GB} GB)"
    else
        ok "Диск: ${FREE_GB} GB свободно"
    fi
fi

# === Проверка 5: Память ===
if command -v free >/dev/null 2>&1; then
    MEM_USED_PCT=$(free | awk '/Mem:/ {printf "%.0f", $3/$2*100}')
    if [[ "$MEM_USED_PCT" -gt "$MEM_THRESHOLD_PCT" ]]; then
        fail "Высокое потребление RAM: ${MEM_USED_PCT}% (порог: ${MEM_THRESHOLD_PCT}%)"
    else
        ok "RAM: ${MEM_USED_PCT}% использовано"
    fi
fi

# === Бизнес-метрики (из логов) ===
TODAY=$(date '+%Y-%m-%d')
METRICS=""

if [[ -f "$LOG_FILE" ]]; then
    # Уникальные юзеры за сегодня (примерный подсчёт по peer ID в логах)
    TODAY_SESSIONS=$(find "${OPENCLAW_HOME}/sessions/" -maxdepth 1 -type d -newer "/tmp/.kent-demo-day-marker" 2>/dev/null | wc -l || echo "?")

    # Юзеры, достигшие лимита (ищем [15/15] в логах за сегодня)
    LIMIT_REACHED=$(grep -c "\[15/15\]" "$LOG_FILE" 2>/dev/null || echo "0")

    METRICS="📊 Метрики за сегодня: сессий ~${TODAY_SESSIONS}, достигли лимита: ${LIMIT_REACHED}"
    verbose "$METRICS"
fi

# Обновляем маркер дня
touch /tmp/.kent-demo-day-marker

# === Отправка алертов ===
send_telegram() {
    local message="$1"
    if [[ -n "$OPERATOR_TELEGRAM_BOT_TOKEN" ]] && [[ -n "$OPERATOR_TELEGRAM_CHAT_ID" ]]; then
        curl -s -X POST \
            "https://api.telegram.org/bot${OPERATOR_TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${OPERATOR_TELEGRAM_CHAT_ID}" \
            -d "text=${message}" \
            -d "parse_mode=HTML" \
            >/dev/null 2>&1 || true
    fi
}

# Если есть сбои — отправляем алерт
if [[ ${#FAILURES[@]} -gt 0 ]]; then
    ALERT_MSG="🚨 <b>Kent Demo — СБОЙ</b>
Хост: ${HOSTNAME_LABEL}
Время: ${TIMESTAMP}

Проблемы:
$(printf '• %s\n' "${FAILURES[@]}")"

    send_telegram "$ALERT_MSG"
    verbose "Алерт отправлен оператору"
fi

# Ежедневный отчёт (в полночь)
HOUR=$(date '+%H')
if [[ "$HOUR" == "00" ]] && [[ -n "$METRICS" ]]; then
    DAILY_MSG="📋 <b>Kent Demo — Ежедневный отчёт</b>
Хост: ${HOSTNAME_LABEL}
Дата: ${TODAY}

${METRICS}

Статус: $([ ${#FAILURES[@]} -eq 0 ] && echo '✅ Всё работает' || echo '⚠️ Есть проблемы')"

    send_telegram "$DAILY_MSG"
fi

# Конверсионный сигнал — юзер достиг лимита
if [[ "$LIMIT_REACHED" -gt 0 ]]; then
    # Проверяем, не отправляли ли уже за этот час
    MARKER="/tmp/.kent-demo-lead-${TODAY}-${HOUR}"
    if [[ ! -f "$MARKER" ]]; then
        send_telegram "🔥 <b>Горячий лид!</b> ${LIMIT_REACHED} юзер(ов) исчерпали лимит демо (15/15) сегодня."
        touch "$MARKER"
    fi
fi

# Выход
if [[ ${#FAILURES[@]} -gt 0 ]]; then
    exit 1
fi
exit 0
