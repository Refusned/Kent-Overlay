#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Мониторинг здоровья OpenClaw Gateway (Kent)
# Проверяет: healthz, процесс, диск, память, размер логов.
# При сбое отправляет алерт оператору через Telegram.
#
# Добавить в системный cron:
# */5 * * * * /path/to/monitor.sh
# ============================================================

OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
GATEWAY_URL="http://localhost:18789/healthz"
DISK_THRESHOLD_GB=5          # предупреждение если свободно меньше (ГБ)
MEM_THRESHOLD_PCT=90         # предупреждение если занято больше (%)
LOG_SIZE_THRESHOLD_MB=500    # предупреждение если лог больше (МБ)
LOG_DIR="${OPENCLAW_HOME}/logs"

VERBOSE=false
if [[ "${1:-}" == "--verbose" ]]; then
    VERBOSE=true
fi

# --- Загружаем .env ---
ENV_FILE="${OPENCLAW_HOME}/.env"
if [[ -f "$ENV_FILE" ]]; then
    set +e
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set -e
fi

# --- Переменные Telegram ---
OPERATOR_TELEGRAM_BOT_TOKEN="${OPERATOR_TELEGRAM_BOT_TOKEN:-}"
OPERATOR_TELEGRAM_CHAT_ID="${OPERATOR_TELEGRAM_CHAT_ID:-}"

# --- Утилиты ---
HOSTNAME_LABEL=$(hostname 2>/dev/null || echo "unknown")
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
FAILURES=()

verbose() {
    if $VERBOSE; then
        echo "$1"
    fi
}

fail() {
    FAILURES+=("$1")
    verbose "СБОЙ: $1"
}

ok() {
    verbose "OK: $1"
}

# === Проверка 1: Gateway health endpoint ===
if curl -sf --max-time 5 "$GATEWAY_URL" >/dev/null 2>&1; then
    ok "Gateway healthz доступен"
else
    fail "Gateway healthz не отвечает (${GATEWAY_URL})"
fi

# === Проверка 2: Процесс Gateway запущен ===
GATEWAY_RUNNING=false
# Сначала проверяем PID-файл
PID_FILE="${OPENCLAW_HOME}/gateway.pid"
if [[ -f "$PID_FILE" ]]; then
    PID=$(cat "$PID_FILE" 2>/dev/null || true)
    if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
        GATEWAY_RUNNING=true
    fi
fi
# Если PID-файл не помог, ищем процесс через pgrep
if ! $GATEWAY_RUNNING; then
    if pgrep -f "openclaw.*gateway" >/dev/null 2>&1; then
        GATEWAY_RUNNING=true
    fi
fi

if $GATEWAY_RUNNING; then
    ok "Процесс Gateway запущен"
else
    fail "Процесс Gateway не найден"
fi

# === Проверка 3: Свободное место на диске ===
# Берём свободное место на корневом разделе (или том, где $HOME)
if command -v df >/dev/null 2>&1; then
    # df -BG выдаёт в гигабайтах (Linux); на macOS используем другой формат
    if df --version 2>/dev/null | grep -q GNU; then
        # GNU/Linux
        FREE_KB=$(df -k "$HOME" | awk 'NR==2 {print $4}')
    else
        # macOS / BSD
        FREE_KB=$(df -k "$HOME" | awk 'NR==2 {print $4}')
    fi
    FREE_GB=$(( FREE_KB / 1048576 ))
    if [[ "$FREE_GB" -lt "$DISK_THRESHOLD_GB" ]]; then
        fail "Мало места на диске: ${FREE_GB} ГБ свободно (порог: ${DISK_THRESHOLD_GB} ГБ)"
    else
        ok "Диск: ${FREE_GB} ГБ свободно"
    fi
else
    verbose "ПРЕДУПРЕЖДЕНИЕ: команда df недоступна, пропускаю проверку диска"
fi

# === Проверка 4: Использование памяти ===
MEM_USED_PCT=0
if [[ "$(uname)" == "Darwin" ]]; then
    # macOS: получаем через vm_stat
    PAGE_SIZE=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
    PAGES_FREE=$(vm_stat 2>/dev/null | awk '/Pages free/ {gsub(/\./, "", $3); print $3}')
    PAGES_INACTIVE=$(vm_stat 2>/dev/null | awk '/Pages inactive/ {gsub(/\./, "", $3); print $3}')
    PAGES_TOTAL=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
    if [[ "$PAGES_TOTAL" -gt 0 && -n "$PAGES_FREE" ]]; then
        FREE_BYTES=$(( (PAGES_FREE + PAGES_INACTIVE) * PAGE_SIZE ))
        MEM_USED_PCT=$(( 100 - (FREE_BYTES * 100 / PAGES_TOTAL) ))
    fi
else
    # Linux: /proc/meminfo
    if [[ -f /proc/meminfo ]]; then
        TOTAL=$(awk '/^MemTotal/ {print $2}' /proc/meminfo)
        AVAIL=$(awk '/^MemAvailable/ {print $2}' /proc/meminfo)
        if [[ -n "$TOTAL" && "$TOTAL" -gt 0 && -n "$AVAIL" ]]; then
            MEM_USED_PCT=$(( 100 - (AVAIL * 100 / TOTAL) ))
        fi
    fi
fi

if [[ "$MEM_USED_PCT" -gt "$MEM_THRESHOLD_PCT" ]]; then
    fail "Высокое потребление памяти: ${MEM_USED_PCT}% (порог: ${MEM_THRESHOLD_PCT}%)"
else
    ok "Память: ${MEM_USED_PCT}% использовано"
fi

# === Проверка 5: Размер лог-файлов ===
if [[ -d "$LOG_DIR" ]]; then
    while IFS= read -r logfile; do
        if [[ -f "$logfile" ]]; then
            SIZE_BYTES=$(stat -f%z "$logfile" 2>/dev/null || stat -c%s "$logfile" 2>/dev/null || echo 0)
            SIZE_MB=$(( SIZE_BYTES / 1048576 ))
            if [[ "$SIZE_MB" -gt "$LOG_SIZE_THRESHOLD_MB" ]]; then
                fail "Лог-файл слишком большой: $(basename "$logfile") = ${SIZE_MB} МБ (порог: ${LOG_SIZE_THRESHOLD_MB} МБ)"
            else
                ok "Лог $(basename "$logfile"): ${SIZE_MB} МБ"
            fi
        fi
    done < <(find "$LOG_DIR" -maxdepth 1 -name '*.log' -type f 2>/dev/null)
else
    verbose "Каталог логов ${LOG_DIR} не найден, пропускаю проверку"
fi

# === Отправка алерта при сбоях ===
if [[ ${#FAILURES[@]} -gt 0 ]]; then
    # Формируем текст алерта
    ALERT_TEXT="⚠️ Kent Monitor Alert
Хост: ${HOSTNAME_LABEL}
Время: ${TIMESTAMP}
Сбои (${#FAILURES[@]}):"

    for f in "${FAILURES[@]}"; do
        ALERT_TEXT="${ALERT_TEXT}
• ${f}"
    done

    verbose "$ALERT_TEXT"

    # Отправляем в Telegram оператору (НЕ через Kent!)
    if [[ -n "$OPERATOR_TELEGRAM_BOT_TOKEN" && -n "$OPERATOR_TELEGRAM_CHAT_ID" ]]; then
        curl -s --max-time 10 \
            "https://api.telegram.org/bot${OPERATOR_TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${OPERATOR_TELEGRAM_CHAT_ID}" \
            -d "text=${ALERT_TEXT}" \
            -d "parse_mode=HTML" \
            >/dev/null 2>&1 || verbose "ПРЕДУПРЕЖДЕНИЕ: не удалось отправить алерт в Telegram"
        verbose "Алерт отправлен в Telegram"
    else
        verbose "ПРЕДУПРЕЖДЕНИЕ: OPERATOR_TELEGRAM_BOT_TOKEN или OPERATOR_TELEGRAM_CHAT_ID не заданы в .env, алерт не отправлен"
    fi

    exit 1
fi

verbose "Все проверки пройдены успешно"
exit 0
