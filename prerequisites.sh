#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# prerequisites.sh — Проверка зависимостей для Kent AI Assistant
# По умолчанию только проверяет наличие и версии.
# Флаги:
#   --install    Автоматически устанавливать недостающие зависимости
#   --skip-env   Пропустить проверку .env файла
# ============================================================================

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # Сброс цвета

# Счётчики результатов
PASSED=0
FAILED=0
WARNINGS=0

# Режимы работы
INSTALL_MODE=false
SKIP_ENV=false

for arg in "$@"; do
    case "$arg" in
        --install)   INSTALL_MODE=true ;;
        --skip-env)  SKIP_ENV=true ;;
    esac
done

# Директория скрипта (для поиска .env)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Функция авто-установки (только в режиме --install) ---
try_install_apt() {
    local pkg="$1"
    local label="${2:-$pkg}"
    if $INSTALL_MODE; then
        echo -e "  ${YELLOW}→${NC} Устанавливаем ${label}..."
        if sudo apt-get install -y "$pkg" &>/dev/null; then
            pass "${label} установлен"
            return 0
        else
            fail "Не удалось установить ${label}"
            return 1
        fi
    fi
    return 1
}

# --- Вспомогательные функции ---

# Успешная проверка
pass() {
    echo -e "  ${GREEN}✔${NC} $1"
    PASSED=$((PASSED + 1))
}

# Провалена обязательная проверка
fail() {
    echo -e "  ${RED}✘${NC} $1"
    FAILED=$((FAILED + 1))
}

# Предупреждение (необязательная зависимость)
warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    WARNINGS=$((WARNINGS + 1))
}

# Сравнение версий: возвращает 0, если $1 >= $2
version_gte() {
    # Разбираем версии на компоненты и сравниваем поэлементно
    local IFS='.'
    local i
    local ver1=($1)
    local ver2=($2)
    for ((i = 0; i < ${#ver2[@]}; i++)); do
        local v1="${ver1[$i]:-0}"
        local v2="${ver2[$i]:-0}"
        if ((v1 > v2)); then
            return 0
        elif ((v1 < v2)); then
            return 1
        fi
    done
    return 0
}

# ============================================================================
echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Проверка зависимостей — Kent AI Assistant${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
echo ""

# --- 1. Node.js >= 22.16 (рекомендуется 24) ---
echo -e "${BOLD}▸ Среда выполнения${NC}"

if command -v node &>/dev/null; then
    NODE_RAW="$(node --version 2>/dev/null)"
    # Убираем префикс "v" (например, v22.16.0 -> 22.16.0)
    NODE_VER="${NODE_RAW#v}"
    if version_gte "$NODE_VER" "22.16"; then
        if version_gte "$NODE_VER" "24.0"; then
            pass "Node.js ${NODE_RAW} (рекомендуемая версия)"
        else
            pass "Node.js ${NODE_RAW} (минимум выполнен; рекомендуется >= 24)"
        fi
    else
        fail "Node.js ${NODE_RAW} — требуется >= 22.16 (рекомендуется 24)"
        if $INSTALL_MODE; then
            echo -e "  ${YELLOW}→${NC} Устанавливаем Node.js 24 через NodeSource..."
            if curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash - &>/dev/null && sudo apt-get install -y nodejs &>/dev/null; then
                pass "Node.js $(node --version 2>/dev/null) установлен"
            else
                fail "Не удалось установить Node.js 24"
            fi
        fi
    fi
else
    fail "Node.js не найден — требуется >= 22.16 (рекомендуется 24)"
    if $INSTALL_MODE; then
        echo -e "  ${YELLOW}→${NC} Устанавливаем Node.js 24 через NodeSource..."
        if curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash - &>/dev/null && sudo apt-get install -y nodejs &>/dev/null; then
            pass "Node.js $(node --version 2>/dev/null) установлен"
        else
            fail "Не удалось установить Node.js 24"
        fi
    fi
fi

# --- 2. pnpm ---
if command -v pnpm &>/dev/null; then
    PNPM_VER="$(pnpm --version 2>/dev/null)"
    pass "pnpm ${PNPM_VER}"
else
    fail "pnpm не найден — установите: npm install -g pnpm"
    if $INSTALL_MODE && command -v npm &>/dev/null; then
        echo -e "  ${YELLOW}→${NC} Устанавливаем pnpm..."
        if npm install -g pnpm &>/dev/null; then
            pass "pnpm $(pnpm --version 2>/dev/null) установлен"
        else
            fail "Не удалось установить pnpm"
        fi
    fi
fi

# --- 3. Python 3 + pip3 ---
if command -v python3 &>/dev/null; then
    PY_VER="$(python3 --version 2>/dev/null)"
    pass "${PY_VER}"
else
    fail "Python 3 не найден"
    try_install_apt python3 "Python 3"
fi

if command -v pip3 &>/dev/null; then
    PIP_VER="$(pip3 --version 2>/dev/null | head -1 || true)"
    pass "pip3 — ${PIP_VER}"
else
    fail "pip3 не найден"
    try_install_apt python3-pip "pip3"
fi

echo ""
echo -e "${BOLD}▸ Утилиты${NC}"

# --- 4. curl ---
if command -v curl &>/dev/null; then
    CURL_VER="$(curl --version 2>/dev/null | head -1 || true)"
    pass "curl — ${CURL_VER}"
else
    fail "curl не найден"
    try_install_apt curl "curl"
fi

# --- 5. jq ---
if command -v jq &>/dev/null; then
    JQ_VER="$(jq --version 2>/dev/null)"
    pass "jq ${JQ_VER}"
else
    fail "jq не найден — установите: brew install jq / apt install jq"
    try_install_apt jq "jq"
fi

# --- 6. openssl ---
if command -v openssl &>/dev/null; then
    OPENSSL_VER="$(openssl version 2>/dev/null)"
    pass "${OPENSSL_VER}"
else
    fail "openssl не найден"
    try_install_apt openssl "openssl"
fi

# --- 7. rsync ---
if command -v rsync &>/dev/null; then
    RSYNC_VER="$(rsync --version 2>/dev/null | head -1 || true)"
    pass "rsync — ${RSYNC_VER}"
else
    fail "rsync не найден — установите: apt install rsync"
    try_install_apt rsync "rsync"
fi

# --- 8. Docker (необязательно) ---
if command -v docker &>/dev/null; then
    DOCKER_VER="$(docker --version 2>/dev/null)"
    pass "Docker — ${DOCKER_VER}"
else
    warn "Docker не найден — необязателен, но нужен для контейнерного деплоя"
fi

# --- 8. Файл .env и обязательные переменные ---
if ! $SKIP_ENV; then
    echo ""
    echo -e "${BOLD}▸ Конфигурация (.env)${NC}"

    ENV_FILE="${SCRIPT_DIR}/.env"
    REQUIRED_VARS=(
        "OPENCLAW_GATEWAY_TOKEN"
        "TELEGRAM_BOT_TOKEN"
        "CLIENT_TELEGRAM_ID"
        "CLIENT_NAME"
    )

    if [[ -f "$ENV_FILE" ]]; then
        pass "Файл .env найден: ${ENV_FILE}"

        # Проверяем каждую обязательную переменную
        for var in "${REQUIRED_VARS[@]}"; do
            # Ищем строку вида VAR=значение (не пустое)
            if grep -qE "^${var}=.+" "$ENV_FILE" 2>/dev/null; then
                pass "Переменная ${var} задана"
            else
                fail "Переменная ${var} отсутствует или пуста в .env"
            fi
        done
    else
        fail "Файл .env не найден (ожидается: ${ENV_FILE})"
        for var in "${REQUIRED_VARS[@]}"; do
            fail "Переменная ${var} — .env отсутствует"
        done
    fi
else
    echo ""
    echo -e "${BOLD}▸ Конфигурация (.env)${NC}"
    echo -e "  ${YELLOW}⚠${NC} Проверка .env пропущена (--skip-env)"
fi

# --- 9. Системные ресурсы ---
echo ""
echo -e "${BOLD}▸ Системные ресурсы${NC}"

# Минимум 4 ГБ оперативной памяти
MIN_RAM_GB=4
if [[ "$(uname)" == "Darwin" ]]; then
    # macOS: sysctl возвращает байты
    TOTAL_RAM_BYTES="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
    TOTAL_RAM_GB=$(( TOTAL_RAM_BYTES / 1073741824 ))
elif [[ -f /proc/meminfo ]]; then
    # Linux: /proc/meminfo возвращает килобайты
    TOTAL_RAM_KB="$(grep -i '^MemTotal:' /proc/meminfo 2>/dev/null | awk '{print $2}')"
    TOTAL_RAM_GB=$(( ${TOTAL_RAM_KB:-0} / 1048576 ))
else
    TOTAL_RAM_GB=0
fi

if (( TOTAL_RAM_GB >= MIN_RAM_GB )); then
    pass "Оперативная память: ${TOTAL_RAM_GB} ГБ (минимум ${MIN_RAM_GB} ГБ)"
else
    if (( TOTAL_RAM_GB == 0 )); then
        warn "Не удалось определить объём оперативной памяти (рекомендуется ${MIN_RAM_GB} ГБ)"
    else
        warn "Оперативная память: ${TOTAL_RAM_GB} ГБ — рекомендуется минимум ${MIN_RAM_GB} ГБ"
    fi
fi

# Минимум 10 ГБ свободного места на диске
MIN_DISK_GB=10
if [[ "$(uname)" == "Darwin" ]]; then
    # macOS: df выводит блоки по 512 байт, берём available
    FREE_BLOCKS="$(df -k "$SCRIPT_DIR" 2>/dev/null | tail -1 | awk '{print $4}')"
    FREE_DISK_GB=$(( ${FREE_BLOCKS:-0} / 1048576 ))
else
    # Linux: df -BG
    FREE_DISK_RAW="$(df -BG "$SCRIPT_DIR" 2>/dev/null | tail -1 | awk '{print $4}')"
    FREE_DISK_GB="${FREE_DISK_RAW%G}"
    FREE_DISK_GB="${FREE_DISK_GB:-0}"
fi

if (( FREE_DISK_GB >= MIN_DISK_GB )); then
    pass "Свободное место на диске: ${FREE_DISK_GB} ГБ (минимум ${MIN_DISK_GB} ГБ)"
else
    if (( FREE_DISK_GB == 0 )); then
        fail "Не удалось определить свободное место на диске (минимум ${MIN_DISK_GB} ГБ)"
    else
        fail "Свободное место на диске: ${FREE_DISK_GB} ГБ — требуется минимум ${MIN_DISK_GB} ГБ"
    fi
fi

# ============================================================================
# Итоги
# ============================================================================
echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Итоги проверки${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${GREEN}✔${NC} Пройдено: ${PASSED}"
[[ $WARNINGS -gt 0 ]] && echo -e "  ${YELLOW}⚠${NC} Предупреждений: ${WARNINGS}"
[[ $FAILED -gt 0 ]]   && echo -e "  ${RED}✘${NC} Провалено: ${FAILED}"
echo ""

if (( FAILED == 0 )); then
    echo -e "  ${GREEN}${BOLD}Все обязательные проверки пройдены.${NC}"
    echo ""
    exit 0
else
    echo -e "  ${RED}${BOLD}${FAILED} проверок провалено — продолжение невозможно.${NC}"
    echo -e "  Установите недостающие зависимости и запустите скрипт повторно."
    echo ""
    exit 1
fi
