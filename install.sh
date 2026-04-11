#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# install.sh — Единая установка Kent AI Assistant (OpenClaw + Overlay)
#
# Использование:
#   bash <(curl -fsSL https://raw.githubusercontent.com/Refusned/Kent-Overlay/main/install.sh)
#
# Флаги:
#   --allow-root       Разрешить запуск от root
#   --skip-configure   Пропустить интерактивную настройку (для CI/автоматизации)
#   --branch <name>    Клонировать указанную ветку (по умолчанию: main)
#   --dir <path>       Установить в указанную директорию (по умолчанию: ~/kent-overlay)
# ============================================================================

# --- Перенаправление stdin для curl|bash ---
# /dev/tty может быть недоступен при неинтерактивном SSH
if [ ! -t 0 ]; then
    exec < /dev/tty 2>/dev/null || true
fi

# --- Константы ---
KENT_REPO="https://github.com/Refusned/Kent-Overlay.git"
KENT_BRANCH="main"
KENT_INSTALL_DIR="${HOME}/kent-overlay"
KENT_MIN_NODE="22.16"

TOTAL_STEPS=7
CURRENT_STEP=0
INSTALL_PHASE="init"

# --- Цвета ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# --- Логирование ---
LOG_FILE="/tmp/kent-install-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# --- Вспомогательные функции ---
step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo ""
    echo -e "${CYAN}${BOLD}[${CURRENT_STEP}/${TOTAL_STEPS}]${NC} ${BOLD}$1${NC}"
}

ok()   { echo -e "  ${GREEN}✔${NC} $1"; }
info() { echo -e "  ${DIM}→${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "  ${RED}✘${NC} $1" >&2; }

die() {
    fail "$1"
    echo ""
    echo -e "${RED}${BOLD}  Установка прервана.${NC}" >&2
    exit 1
}

# --- EXIT-trap: rollback-инструкции при ошибке ---
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo ""
        echo -e "${RED}${BOLD}═══ Установка завершилась с ошибкой (код ${exit_code}) ═══${NC}"
        echo ""
        case "$INSTALL_PHASE" in
            deps)
                echo -e "  Фаза: установка зависимостей"
                echo -e "  Решение: исправьте ошибку и перезапустите install.sh"
                ;;
            clone)
                echo -e "  Фаза: клонирование репозитория"
                echo -e "  Решение: ${BOLD}rm -rf ${KENT_INSTALL_DIR}${NC} и перезапустите install.sh"
                ;;
            configure)
                echo -e "  Фаза: настройка"
                echo -e "  Решение: ${BOLD}cd ${KENT_INSTALL_DIR} && ./configure.sh${NC}"
                ;;
            deploy)
                echo -e "  Фаза: развёртывание"
                echo -e "  Решение: ${BOLD}cd ${KENT_INSTALL_DIR} && ./deploy.sh${NC}"
                ;;
        esac
        echo ""
        echo -e "  Лог: ${LOG_FILE}"
        echo ""
    fi
}
trap cleanup EXIT

# --- Сравнение версий: $1 >= $2 ---
version_gte() {
    local IFS='.'
    local i
    local ver1=($1)
    local ver2=($2)
    for ((i = 0; i < ${#ver2[@]}; i++)); do
        local v1="${ver1[$i]:-0}"
        local v2="${ver2[$i]:-0}"
        if ((v1 > v2)); then return 0; fi
        if ((v1 < v2)); then return 1; fi
    done
    return 0
}

# ============================================================================
# Парсинг аргументов
# ============================================================================
ALLOW_ROOT=false
SKIP_CONFIGURE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --allow-root)      ALLOW_ROOT=true; shift ;;
        --skip-configure)  SKIP_CONFIGURE=true; shift ;;
        --branch)          KENT_BRANCH="${2:-main}"; shift 2 ;;
        --dir)             KENT_INSTALL_DIR="${2:-$KENT_INSTALL_DIR}"; shift 2 ;;
        *)                 warn "Неизвестный аргумент: $1"; shift ;;
    esac
done

# ============================================================================
# [0] Баннер + проверки окружения
# ============================================================================
echo ""
echo -e "${BOLD}  ╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}  ║                                                        ║${NC}"
echo -e "${BOLD}  ║     Kent AI Assistant — One-Command Installer          ║${NC}"
echo -e "${BOLD}  ║     Powered by OpenClaw                                ║${NC}"
echo -e "${BOLD}  ║                                                        ║${NC}"
echo -e "${BOLD}  ╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

info "Дата: $(date '+%Y-%m-%d %H:%M:%S')"
info "Пользователь: $(whoami)"
info "Хост: $(hostname)"
info "Лог: ${LOG_FILE}"

# --- Проверка root ---
if [[ "$EUID" -eq 0 ]] && ! $ALLOW_ROOT; then
    echo ""
    warn "Запуск от root не рекомендуется."
    echo -e "  Создайте пользователя и запустите от его имени:"
    echo -e "    ${CYAN}adduser kent && usermod -aG sudo kent${NC}"
    echo -e "    ${CYAN}su - kent${NC}"
    echo ""
    echo -e "  Или запустите с флагом ${CYAN}--allow-root${NC} для обхода."
    exit 1
fi

# --- Проверка ОС ---
if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "${ID:-}" == "ubuntu" ]]; then
        ok "ОС: ${PRETTY_NAME:-Ubuntu}"
    elif [[ "${ID_LIKE:-}" == *"debian"* || "${ID:-}" == "debian" ]]; then
        warn "ОС: ${PRETTY_NAME:-Debian-based} — поддерживается, но рекомендуется Ubuntu 24.04"
    else
        warn "ОС: ${PRETTY_NAME:-неизвестно} — не тестировалась, могут быть проблемы"
    fi
else
    warn "Не удалось определить ОС (/etc/os-release не найден)"
fi

# --- Проверка sudo ---
if [[ "$EUID" -ne 0 ]]; then
    if ! sudo -n true 2>/dev/null; then
        info "Для установки потребуется пароль sudo"
        if ! sudo true; then
            die "Не удалось получить доступ sudo. Добавьте пользователя в sudoers."
        fi
    fi
    ok "Доступ sudo подтверждён"
fi

# --- Проверка существующей установки ---
if [[ -d "${KENT_INSTALL_DIR}/.git" ]]; then
    echo ""
    warn "Обнаружена существующая установка: ${KENT_INSTALL_DIR}"

    EXISTING_OC_VERSION="$(openclaw --version 2>/dev/null || echo 'н/д')"
    EXISTING_KENT_VERSION="$(cat "${HOME}/.openclaw/kent-overlay-version" 2>/dev/null || echo 'н/д')"

    info "OpenClaw: ${EXISTING_OC_VERSION}"
    info "Kent Overlay: ${EXISTING_KENT_VERSION}"
    echo ""
    echo -e "  ${BOLD}Что сделать?${NC}"
    echo -e "  ${CYAN}1${NC} — Обновить (git pull + deploy)"
    echo -e "  ${CYAN}2${NC} — Переустановить (удалить и начать заново)"
    echo -e "  ${CYAN}3${NC} — Отмена"
    echo ""
    if [ -t 0 ]; then
        read -r -p "  Ваш выбор [1/2/3]: " choice
    else
        # Неинтерактивный режим — по умолчанию обновляем
        choice="1"
        info "Неинтерактивный режим — выбрано: обновление"
    fi

    case "$choice" in
        1)
            ok "Режим обновления"
            cd "${KENT_INSTALL_DIR}"
            info "Обновление репозитория..."
            if git pull --ff-only 2>/dev/null; then
                ok "Репозиторий обновлён"
            else
                warn "git pull --ff-only не удался, пробуем git pull..."
                git pull || warn "Не удалось обновить репозиторий, продолжаем с текущей версией"
            fi
            # Перейти сразу к configure + deploy
            INSTALL_PHASE="configure"
            if ! $SKIP_CONFIGURE; then
                CURRENT_STEP=4
                step "Настройка Kent (configure.sh)"
                chmod +x "${KENT_INSTALL_DIR}/configure.sh"
                bash "${KENT_INSTALL_DIR}/configure.sh"
                ok "Настройка завершена"
            fi

            INSTALL_PHASE="deploy"
            CURRENT_STEP=5
            step "Развёртывание Kent (deploy.sh)"
            chmod +x "${KENT_INSTALL_DIR}/deploy.sh"
            bash "${KENT_INSTALL_DIR}/deploy.sh"
            ok "Развёртывание завершено"

            # Итоги
            CURRENT_STEP=6
            step "Обновление завершено"
            echo ""
            echo -e "  ${GREEN}${BOLD}Kent обновлён и готов к работе! 👔${NC}"
            echo ""
            exit 0
            ;;
        2)
            warn "Удаление ${KENT_INSTALL_DIR}..."
            rm -rf "${KENT_INSTALL_DIR}"
            ok "Старая установка удалена"
            ;;
        *)
            echo ""
            echo -e "  Установка отменена."
            exit 0
            ;;
    esac
fi

# ============================================================================
# [1/7] Установка системных пакетов
# ============================================================================
INSTALL_PHASE="deps"
step "Установка системных пакетов"

info "apt-get update..."
sudo apt-get update -qq

SYSTEM_PACKAGES=(
    curl
    git
    jq
    openssl
    rsync
    python3
    python3-pip
    python3-venv
    ca-certificates
    gnupg
)

info "Пакеты: ${SYSTEM_PACKAGES[*]}"
sudo apt-get install -y "${SYSTEM_PACKAGES[@]}"
ok "Системные пакеты установлены"

# ============================================================================
# [2/7] Установка Node.js 24
# ============================================================================
step "Установка Node.js"

NEED_NODE_INSTALL=true

if command -v node &>/dev/null; then
    NODE_RAW="$(node --version 2>/dev/null)"
    NODE_VER="${NODE_RAW#v}"
    if version_gte "$NODE_VER" "$KENT_MIN_NODE"; then
        ok "Node.js ${NODE_RAW} уже установлен (>= ${KENT_MIN_NODE})"
        NEED_NODE_INSTALL=false
    else
        info "Node.js ${NODE_RAW} — устаревшая версия, обновляем..."
    fi
fi

if $NEED_NODE_INSTALL; then
    info "Установка Node.js 24 через NodeSource..."
    curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
    sudo apt-get install -y nodejs
    ok "Node.js $(node --version 2>/dev/null) установлен"
fi

# --- pnpm ---
if command -v pnpm &>/dev/null; then
    ok "pnpm $(pnpm --version 2>/dev/null) уже установлен"
else
    info "Установка pnpm..."
    npm install -g pnpm
    ok "pnpm $(pnpm --version 2>/dev/null) установлен"
fi

# --- Настройка глобальной директории pnpm ---
if ! pnpm config get global-bin-dir &>/dev/null || [[ "$(pnpm config get global-bin-dir 2>/dev/null)" == "undefined" ]]; then
    info "Настройка pnpm global bin directory..."
    pnpm setup 2>/dev/null || true
    export PNPM_HOME="${HOME}/.local/share/pnpm"
    export PATH="${PNPM_HOME}:${PATH}"
    ok "PNPM_HOME настроен: ${PNPM_HOME}"
fi

# ============================================================================
# [3/7] Проверка зависимостей
# ============================================================================
step "Финальная проверка зависимостей"

# Краткая проверка критических компонентов
DEPS_OK=true

for cmd in node pnpm python3 pip3 curl git jq openssl rsync; do
    if command -v "$cmd" &>/dev/null; then
        ok "${cmd} — $(${cmd} --version 2>/dev/null | head -1 || echo 'ok')"
    else
        fail "${cmd} не найден"
        DEPS_OK=false
    fi
done

if ! $DEPS_OK; then
    die "Не все зависимости установлены. Проверьте вывод выше."
fi

# --- Системные ресурсы ---
MIN_RAM_GB=4
if [[ -f /proc/meminfo ]]; then
    TOTAL_RAM_KB="$(grep -i '^MemTotal:' /proc/meminfo 2>/dev/null | awk '{print $2}')"
    TOTAL_RAM_GB=$(( ${TOTAL_RAM_KB:-0} / 1048576 ))
    if (( TOTAL_RAM_GB >= MIN_RAM_GB )); then
        ok "RAM: ${TOTAL_RAM_GB} ГБ (минимум ${MIN_RAM_GB} ГБ)"
    else
        warn "RAM: ${TOTAL_RAM_GB} ГБ — рекомендуется минимум ${MIN_RAM_GB} ГБ"
    fi
fi

# ============================================================================
# [4/7] Клонирование репозитория
# ============================================================================
INSTALL_PHASE="clone"
step "Клонирование Kent Overlay"

info "Репозиторий: ${KENT_REPO}"
info "Ветка: ${KENT_BRANCH}"
info "Директория: ${KENT_INSTALL_DIR}"

git clone --branch "${KENT_BRANCH}" "${KENT_REPO}" "${KENT_INSTALL_DIR}"
ok "Репозиторий склонирован"

cd "${KENT_INSTALL_DIR}"

# Сделать скрипты исполняемыми
chmod +x install.sh configure.sh deploy.sh prerequisites.sh update.sh backup.sh monitor.sh 2>/dev/null || true
ok "Скрипты помечены как исполняемые"

# ============================================================================
# [5/7] Настройка Kent (интерактивная)
# ============================================================================
INSTALL_PHASE="configure"
step "Настройка Kent (configure.sh)"

if $SKIP_CONFIGURE; then
    warn "Настройка пропущена (--skip-configure)"
    warn "Убедитесь, что .env файл создан вручную перед запуском deploy.sh"
    if [[ ! -f "${KENT_INSTALL_DIR}/.env" ]]; then
        info "Шаблон .env: ${KENT_INSTALL_DIR}/.env.example"
    fi
else
    echo ""
    echo -e "  ${DIM}Сейчас запустится интерактивный мастер настройки.${NC}"
    echo -e "  ${DIM}Он создаст .env файл с токенами и настройками клиента.${NC}"
    echo ""
    bash "${KENT_INSTALL_DIR}/configure.sh"
    ok "Настройка завершена"
fi

# ============================================================================
# [6/7] Развёртывание Kent (deploy.sh)
# ============================================================================
INSTALL_PHASE="deploy"
step "Развёртывание Kent (deploy.sh)"

# Проверка: .env должен существовать перед deploy.sh
if [[ ! -f "${KENT_INSTALL_DIR}/.env" && ! -f "${HOME}/.openclaw/.env" ]]; then
    die "Файл .env не найден. Запустите configure.sh или создайте .env вручную из .env.example"
fi

echo ""
echo -e "  ${DIM}Запуск полного развёртывания (20 шагов)...${NC}"
echo ""

bash "${KENT_INSTALL_DIR}/deploy.sh"
ok "Развёртывание завершено"

# ============================================================================
# [7/7] Итоговая сводка
# ============================================================================
INSTALL_PHASE="done"
step "Установка завершена"

CURRENT_USER="$(whoami)"
CURRENT_HOST="$(hostname)"
KENT_VERSION="$(cat "${KENT_INSTALL_DIR}/VERSION" 2>/dev/null || echo 'н/д')"
OC_VERSION="$(openclaw --version 2>/dev/null || echo 'н/д')"

echo ""
echo -e "${BOLD}  ╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}  ║        Kent AI Assistant — Установка завершена          ║${NC}"
echo -e "${BOLD}  ╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Kent Overlay:${NC}  ${KENT_VERSION}"
echo -e "  ${BOLD}OpenClaw:${NC}      ${OC_VERSION}"
echo -e "  ${BOLD}Директория:${NC}    ${KENT_INSTALL_DIR}"
echo -e "  ${BOLD}Конфиг:${NC}        ${HOME}/.openclaw/openclaw.json"
echo -e "  ${BOLD}Лог:${NC}           ${LOG_FILE}"
echo ""
echo -e "  ${BOLD}────────────────────────────────────────────────────────${NC}"
echo -e "  ${BOLD}Следующие шаги:${NC}"
echo ""
echo -e "  ${CYAN}1.${NC} Откройте SSH-туннель для доступа к Control UI:"
echo -e "     ${CYAN}ssh -L 18789:localhost:18789 ${CURRENT_USER}@${CURRENT_HOST}${NC}"
echo ""
echo -e "  ${CYAN}2.${NC} Авторизуйте модели (если не сделали при настройке):"
echo -e "     ${CYAN}openclaw codex auth${NC}"
echo -e "     ${CYAN}openclaw auth login openai${NC}"
echo ""
echo -e "  ${CYAN}3.${NC} Сопрягите Telegram-бота:"
echo -e "     ${CYAN}openclaw pair telegram${NC}"
echo ""
echo -e "  ${CYAN}4.${NC} Отправьте боту ${CYAN}/start${NC} в Telegram"
echo -e "  ${BOLD}────────────────────────────────────────────────────────${NC}"
echo ""
echo -e "  ${DIM}Обновление:     cd ${KENT_INSTALL_DIR} && ./update.sh${NC}"
echo -e "  ${DIM}Реконфигурация: cd ${KENT_INSTALL_DIR} && ./configure.sh${NC}"
echo -e "  ${DIM}Мониторинг:     openclaw status${NC}"
echo ""
echo -e "  ${GREEN}${BOLD}Kent готов к работе! 👔${NC}"
echo ""
