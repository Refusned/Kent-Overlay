#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# deploy.sh — Главный скрипт развёртывания Kent AI Assistant
# Превращает чистый VPS (Ubuntu 24) в рабочую установку Kent.
# Идемпотентен — безопасен для повторного запуска.
# ============================================================================

# --- Цвета и форматирование ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

TOTAL_STEPS=20
CURRENT_STEP=0

# --- Вспомогательные функции ---

step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo ""
    echo -e "${CYAN}${BOLD}[${CURRENT_STEP}/${TOTAL_STEPS}]${NC} ${BOLD}$1${NC}"
}

ok() {
    echo -e "  ${GREEN}✔${NC} $1"
}

info() {
    echo -e "  ${DIM}→${NC} $1"
}

warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

fail() {
    echo -e "  ${RED}✘${NC} $1" >&2
}

die() {
    fail "$1"
    echo ""
    echo -e "${RED}${BOLD}  Развёртывание прервано.${NC}" >&2
    exit 1
}

# Логирование в файл (создаётся позже, пишем в /tmp до этого)
LOG_FILE="/tmp/kent-deploy-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# ============================================================================
# [1/20] Баннер + определение OVERLAY_DIR
# ============================================================================
step "Инициализация — определение окружения"

OVERLAY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_HOME="${HOME}/.openclaw"

echo ""
echo -e "${BOLD}  ╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}  ║                                                        ║${NC}"
echo -e "${BOLD}  ║        Kent AI Assistant — Deployment Script            ║${NC}"
echo -e "${BOLD}  ║        Powered by OpenClaw                              ║${NC}"
echo -e "${BOLD}  ║                                                        ║${NC}"
echo -e "${BOLD}  ╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

ok "OVERLAY_DIR: ${OVERLAY_DIR}"
ok "OPENCLAW_HOME: ${OPENCLAW_HOME}"
ok "Дата: $(date '+%Y-%m-%d %H:%M:%S')"
ok "Пользователь: $(whoami)"
ok "Хост: $(hostname)"
ok "Лог: ${LOG_FILE}"

# ============================================================================
# [2/20] Запуск prerequisites.sh
# ============================================================================
step "Проверка зависимостей (prerequisites.sh)"

PREREQ_SCRIPT="${OVERLAY_DIR}/prerequisites.sh"

if [[ ! -f "$PREREQ_SCRIPT" ]]; then
    die "Файл prerequisites.sh не найден: ${PREREQ_SCRIPT}"
fi

chmod +x "$PREREQ_SCRIPT"

if ! bash "$PREREQ_SCRIPT"; then
    die "Проверка зависимостей провалена. Установите недостающие компоненты и запустите deploy.sh повторно."
fi

ok "Все зависимости проверены"

# ============================================================================
# [3/20] Загрузка .env
# ============================================================================
step "Загрузка переменных окружения (.env)"

ENV_FILE=""

if [[ -f "${OPENCLAW_HOME}/.env" ]]; then
    ENV_FILE="${OPENCLAW_HOME}/.env"
    info "Используется существующий .env: ${ENV_FILE}"
elif [[ -f "${OVERLAY_DIR}/.env" ]]; then
    ENV_FILE="${OVERLAY_DIR}/.env"
    info "Используется .env из overlay: ${ENV_FILE}"
else
    die "Файл .env не найден ни в ${OVERLAY_DIR}/.env, ни в ${OPENCLAW_HOME}/.env"
fi

# Безопасный source: загружаем только переменные, игнорируя комментарии
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

ok "Переменные окружения загружены из ${ENV_FILE}"

# Проверяем критически важные переменные
for var in OPENCLAW_GATEWAY_TOKEN TELEGRAM_BOT_TOKEN CLIENT_TELEGRAM_ID CLIENT_NAME; do
    if [[ -z "${!var:-}" ]]; then
        die "Обязательная переменная ${var} не задана в .env"
    fi
done

ok "Все обязательные переменные присутствуют"

# ============================================================================
# [4/20] Установка OpenClaw
# ============================================================================
step "Установка OpenClaw (pnpm global)"

OPENCLAW_TARGET_VERSION="${OPENCLAW_VERSION:-latest}"
info "Целевая версия: ${OPENCLAW_TARGET_VERSION}"

if command -v openclaw &>/dev/null; then
    CURRENT_VERSION="$(openclaw --version 2>/dev/null || echo 'неизвестно')"
    info "Текущая версия OpenClaw: ${CURRENT_VERSION}"
fi

if ! pnpm add -g "openclaw@${OPENCLAW_TARGET_VERSION}"; then
    die "Не удалось установить openclaw@${OPENCLAW_TARGET_VERSION}"
fi

INSTALLED_VERSION="$(openclaw --version 2>/dev/null || echo 'неизвестно')"
ok "OpenClaw установлен: ${INSTALLED_VERSION}"

# ============================================================================
# [5/20] Установка Python-зависимостей
# ============================================================================
step "Установка Python-зависимостей"

PYTHON_DEPS=(
    faster-whisper
    python-pptx
    Pillow
    PyPDF2
    python-docx
    openpyxl
    pandas
    yt-dlp
)

info "Пакеты: ${PYTHON_DEPS[*]}"

if pip3 install --break-system-packages "${PYTHON_DEPS[@]}"; then
    ok "Python-зависимости установлены"
else
    die "Не удалось установить Python-зависимости"
fi

# ============================================================================
# [6/20] Настройка файрвола
# ============================================================================
step "Настройка файрвола (ufw)"

if command -v ufw &>/dev/null; then
    # Проверяем, есть ли уже правило
    if ufw status 2>/dev/null | grep -q "18789/tcp.*DENY"; then
        ok "Правило ufw deny 18789/tcp уже существует"
    else
        if ufw deny 18789/tcp 2>/dev/null; then
            ok "Порт 18789/tcp заблокирован для внешнего доступа"
        else
            warn "Не удалось добавить правило ufw (возможно, нужны права root)"
        fi
    fi
else
    warn "ufw не найден — пропускаем настройку файрвола"
    warn "Убедитесь, что порт 18789 не доступен из внешней сети"
fi

# ============================================================================
# [7/20] Создание структуры директорий
# ============================================================================
step "Создание структуры директорий"

mkdir -p "${OPENCLAW_HOME}"/{workspace,credentials,logs,cron}
mkdir -p "${OPENCLAW_HOME}/workspace"/{memory/groups,smm/{posts,analytics,brands},content/drafts,scripts,self-improvement,leads,faq,crm/contacts,broadcasts,smarthome,feedback,tools}

ok "Структура директорий создана в ${OPENCLAW_HOME}"

# --- Копирование backup.sh в scripts/ ---
if [[ -f "${OVERLAY_DIR}/backup.sh" ]]; then
    cp "${OVERLAY_DIR}/backup.sh" "${OPENCLAW_HOME}/workspace/scripts/backup.sh"
    chmod +x "${OPENCLAW_HOME}/workspace/scripts/backup.sh"
    ok "backup.sh скопирован в ${OPENCLAW_HOME}/workspace/scripts/"
fi

# ============================================================================
# [8/20] Копирование .env
# ============================================================================
step "Копирование .env в ${OPENCLAW_HOME}"

TARGET_ENV="${OPENCLAW_HOME}/.env"

if [[ "$(realpath "${ENV_FILE}" 2>/dev/null || readlink -f "${ENV_FILE}" 2>/dev/null || echo "${ENV_FILE}")" == \
      "$(realpath "${TARGET_ENV}" 2>/dev/null || readlink -f "${TARGET_ENV}" 2>/dev/null || echo "${TARGET_ENV}")" ]]; then
    ok ".env уже находится в ${OPENCLAW_HOME} — копирование не требуется"
else
    cp "${ENV_FILE}" "${TARGET_ENV}"
    ok ".env скопирован в ${TARGET_ENV}"
fi

# ============================================================================
# [9/20] Копирование openclaw.json
# ============================================================================
step "Копирование openclaw.json"

SOURCE_CONFIG="${OVERLAY_DIR}/config/openclaw.json"
TARGET_CONFIG="${OPENCLAW_HOME}/openclaw.json"

if [[ ! -f "$SOURCE_CONFIG" ]]; then
    die "Файл конфигурации не найден: ${SOURCE_CONFIG}"
fi

cp "$SOURCE_CONFIG" "$TARGET_CONFIG"
ok "openclaw.json скопирован в ${TARGET_CONFIG}"

# ============================================================================
# [10/20] Копирование файлов workspace
# ============================================================================
step "Копирование файлов workspace"

WORKSPACE_SRC="${OVERLAY_DIR}/workspace"
WORKSPACE_DST="${OPENCLAW_HOME}/workspace"

# --- Markdown-файлы (перезаписываемые) ---
OVERWRITE_FILES=(
    SOUL.md
    AGENTS.md
    SECURITY.md
    IDENTITY.md
    TOOLS.md
    BOOT.md
    BOOTSTRAP.md
)

for f in "${OVERWRITE_FILES[@]}"; do
    if [[ -f "${WORKSPACE_SRC}/${f}" ]]; then
        cp "${WORKSPACE_SRC}/${f}" "${WORKSPACE_DST}/${f}"
        ok "${f} скопирован"
    else
        warn "${f} не найден в overlay — пропускаем"
    fi
done

# --- USER.md — особая обработка: не перезаписывать кастомизированный ---
USER_MD_DST="${WORKSPACE_DST}/USER.md"
USER_MD_TEMPLATE="${WORKSPACE_SRC}/USER.md.template"

if [[ -f "$USER_MD_DST" ]]; then
    # Проверяем, был ли файл изменён пользователем (сравниваем с шаблоном)
    if [[ -f "$USER_MD_TEMPLATE" ]]; then
        # Генерируем из шаблона для сравнения
        TEMPLATE_HASH="$(md5sum "$USER_MD_TEMPLATE" 2>/dev/null | awk '{print $1}' || md5 -q "$USER_MD_TEMPLATE" 2>/dev/null || echo "")"
        EXISTING_HASH="$(md5sum "$USER_MD_DST" 2>/dev/null | awk '{print $1}' || md5 -q "$USER_MD_DST" 2>/dev/null || echo "")"

        if [[ -n "$TEMPLATE_HASH" && "$TEMPLATE_HASH" == "$EXISTING_HASH" ]]; then
            cp "$USER_MD_TEMPLATE" "$USER_MD_DST"
            ok "USER.md обновлён (не был изменён пользователем)"
        else
            ok "USER.md сохранён без изменений (кастомизирован пользователем)"
        fi
    else
        ok "USER.md уже существует — пропускаем"
    fi
else
    # USER.md не существует — создаём из шаблона
    if [[ -f "$USER_MD_TEMPLATE" ]]; then
        cp "$USER_MD_TEMPLATE" "$USER_MD_DST"
        ok "USER.md создан из шаблона"
    elif [[ -f "${WORKSPACE_SRC}/USER.md" ]]; then
        cp "${WORKSPACE_SRC}/USER.md" "$USER_MD_DST"
        ok "USER.md скопирован"
    else
        warn "USER.md и USER.md.template не найдены — пропускаем"
    fi
fi

# --- MEMORY.md и LEARNED.md — не перезаписывать, если уже существуют ---
for user_file in MEMORY.md LEARNED.md; do
    FILE_DST="${WORKSPACE_DST}/${user_file}"
    FILE_SRC="${WORKSPACE_SRC}/${user_file}"
    if [[ -f "$FILE_DST" ]]; then
        ok "${user_file} уже существует — пропускаем (пользовательские данные)"
    elif [[ -f "$FILE_SRC" ]]; then
        cp "$FILE_SRC" "$FILE_DST"
        ok "${user_file} создан из шаблона"
    fi
done

# --- Seed-файлы для cron (контент-план и SMM-стратегия) ---
for seed_file in content/calendar.md smm/strategy.md; do
    SEED_DST="${WORKSPACE_DST}/${seed_file}"
    SEED_SRC="${WORKSPACE_SRC}/${seed_file}"
    if [[ ! -f "$SEED_DST" && -f "$SEED_SRC" ]]; then
        cp "$SEED_SRC" "$SEED_DST"
        ok "Seed-файл ${seed_file} создан"
    fi
done

# --- Skills (все 10 директорий) ---
SKILLS_SRC="${WORKSPACE_SRC}/skills"
SKILLS_DST="${WORKSPACE_DST}/skills"

if [[ -d "$SKILLS_SRC" ]]; then
    mkdir -p "$SKILLS_DST"
    # Копируем все поддиректории навыков
    SKILL_COUNT=0
    for skill_dir in "$SKILLS_SRC"/*/; do
        if [[ -d "$skill_dir" ]]; then
            skill_name="$(basename "$skill_dir")"
            cp -r "$skill_dir" "${SKILLS_DST}/${skill_name}"
            SKILL_COUNT=$((SKILL_COUNT + 1))
        fi
    done
    ok "Локальные навыки скопированы: ${SKILL_COUNT} шт."
else
    warn "Директория skills не найдена в overlay"
fi

# --- tools/pptx_tool.py ---
TOOLS_SRC="${WORKSPACE_SRC}/tools"
TOOLS_DST="${WORKSPACE_DST}/tools"

if [[ -f "${TOOLS_SRC}/pptx_tool.py" ]]; then
    mkdir -p "$TOOLS_DST"
    cp "${TOOLS_SRC}/pptx_tool.py" "${TOOLS_DST}/pptx_tool.py"
    ok "tools/pptx_tool.py скопирован"
else
    warn "tools/pptx_tool.py не найден в overlay"
fi

# ============================================================================
# [11/20] Установка навыков из ClawHub
# ============================================================================
step "Установка навыков из ClawHub"

CLAWHUB_SKILLS=(
    spotify-player
    pdf-tools
    capability-evolver
    self-improving-agent
    agent-browser
    tavily-search
    crm
    seo-blog-writer
    humanizer
    seo-content-engine
    elevenlabs-tts
    image-generation
)

SKILLS_INSTALLED=0
SKILLS_FAILED=0

for skill in "${CLAWHUB_SKILLS[@]}"; do
    if openclaw skills install "$skill" 2>/dev/null; then
        ok "Навык установлен: ${skill}"
        SKILLS_INSTALLED=$((SKILLS_INSTALLED + 1))
    else
        warn "Не удалось установить навык: ${skill} — продолжаем"
        SKILLS_FAILED=$((SKILLS_FAILED + 1))
    fi
done

ok "ClawHub: установлено ${SKILLS_INSTALLED}/${#CLAWHUB_SKILLS[@]} навыков"
if (( SKILLS_FAILED > 0 )); then
    warn "Не установлено навыков: ${SKILLS_FAILED} (можно установить позже вручную)"
fi

# ============================================================================
# [12/20] Установка прав доступа
# ============================================================================
step "Установка прав доступа"

chmod 700 "${OPENCLAW_HOME}"
ok "chmod 700 ${OPENCLAW_HOME}"

chmod 600 "${OPENCLAW_HOME}/.env"
ok "chmod 600 .env"

chmod 600 "${OPENCLAW_HOME}/openclaw.json"
ok "chmod 600 openclaw.json"

# ============================================================================
# [13/20] Онбординг и установка демона
# ============================================================================
step "Онбординг OpenClaw (install-daemon)"

if openclaw onboard --install-daemon; then
    ok "Онбординг завершён, демон установлен"
else
    die "openclaw onboard --install-daemon завершился с ошибкой"
fi

# ============================================================================
# [14/20] Копирование cron/jobs.json
# ============================================================================
step "Копирование расписания задач (cron/jobs.json)"

CRON_SRC="${OVERLAY_DIR}/cron/jobs.json"
CRON_DST="${OPENCLAW_HOME}/cron/jobs.json"

if [[ -f "$CRON_SRC" ]]; then
    cp "$CRON_SRC" "$CRON_DST"
    ok "jobs.json скопирован в ${CRON_DST}"
else
    warn "cron/jobs.json не найден в overlay — пропускаем"
fi

# ============================================================================
# [15/20] Прогрев QMD
# ============================================================================
step "Прогрев QMD (Quick Memory Database)"

if command -v qmd &>/dev/null; then
    info "QMD найден, запускаем обновление и индексацию..."
    if qmd update && qmd embed; then
        ok "QMD прогрет успешно"
    else
        warn "QMD прогрев завершился с ошибкой — не критично"
    fi
else
    info "QMD не установлен, пропускаем"
fi

# ============================================================================
# [16/20] Прогрев faster-whisper
# ============================================================================
step "Прогрев faster-whisper (загрузка модели base)"

if python3 -c "from faster_whisper import WhisperModel; WhisperModel('base')" 2>/dev/null; then
    ok "Модель Whisper base загружена и кэширована"
else
    warn "Прогрев Whisper не удался — модель будет загружена при первом использовании"
fi

# ============================================================================
# [17/20] Аудит безопасности
# ============================================================================
step "Аудит безопасности"

if openclaw security audit --fix --deep; then
    ok "Аудит безопасности пройден"
else
    die "Аудит безопасности провален — развёртывание остановлено. Исправьте проблемы и перезапустите deploy.sh"
fi

# ============================================================================
# [18/20] Финальные проверки
# ============================================================================
step "Финальные проверки"

# openclaw doctor
info "Запуск openclaw doctor..."
if openclaw doctor; then
    ok "openclaw doctor — OK"
else
    warn "openclaw doctor обнаружил проблемы (см. вывод выше)"
fi

# openclaw status
info "Запуск openclaw status..."
if openclaw status; then
    ok "openclaw status — OK"
else
    warn "openclaw status обнаружил проблемы"
fi

# openclaw channels status
info "Проверка каналов связи..."
if openclaw channels status --probe; then
    ok "Каналы связи — OK"
else
    warn "Некоторые каналы недоступны (см. вывод выше)"
fi

# Проверка порта 18789
info "Проверка прослушивания порта 18789..."
if command -v ss &>/dev/null; then
    if ss -tlnp 2>/dev/null | grep -q ":18789"; then
        ok "Порт 18789 прослушивается"
    else
        warn "Порт 18789 не прослушивается — шлюз может быть ещё не запущен"
    fi
elif command -v lsof &>/dev/null; then
    if lsof -i :18789 &>/dev/null; then
        ok "Порт 18789 прослушивается"
    else
        warn "Порт 18789 не прослушивается — шлюз может быть ещё не запущен"
    fi
else
    warn "Ни ss, ни lsof не найдены — проверка порта пропущена"
fi

# ============================================================================
# [19/20] Сохранение версии overlay
# ============================================================================
step "Сохранение версии Kent Overlay"

VERSION_FILE="${OVERLAY_DIR}/VERSION"
VERSION_DST="${OPENCLAW_HOME}/kent-overlay-version"

if [[ -f "$VERSION_FILE" ]]; then
    KENT_VERSION="$(cat "$VERSION_FILE" | tr -d '[:space:]')"
else
    KENT_VERSION="unknown-$(date +%Y%m%d)"
    warn "Файл VERSION не найден, используется: ${KENT_VERSION}"
fi

echo "$KENT_VERSION" > "$VERSION_DST"
ok "Версия ${KENT_VERSION} сохранена в ${VERSION_DST}"

# ============================================================================
# [20/20] Итоговая сводка
# ============================================================================
step "Итоговая сводка"

# Маскировка токена: первые 8 символов + ****
GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-}"
if [[ ${#GATEWAY_TOKEN} -ge 8 ]]; then
    MASKED_TOKEN="${GATEWAY_TOKEN:0:8}****"
else
    MASKED_TOKEN="(не задан)"
fi

# Перемещаем лог в постоянное место
FINAL_LOG="${OPENCLAW_HOME}/logs/deploy-$(date +%Y%m%d-%H%M%S).log"
if [[ -d "${OPENCLAW_HOME}/logs" ]]; then
    cp "$LOG_FILE" "$FINAL_LOG" 2>/dev/null || true
fi

CURRENT_USER="$(whoami)"
CURRENT_HOST="$(hostname)"

echo ""
echo -e "${BOLD}  ╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}  ║          Kent AI Assistant — Развёртывание завершено    ║${NC}"
echo -e "${BOLD}  ╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Версия overlay:${NC}     ${KENT_VERSION}"
echo -e "  ${BOLD}OpenClaw:${NC}           $(openclaw --version 2>/dev/null || echo 'н/д')"
echo -e "  ${BOLD}Gateway token:${NC}      ${MASKED_TOKEN}"
echo -e "  ${BOLD}Конфигурация:${NC}       ${OPENCLAW_HOME}/openclaw.json"
echo -e "  ${BOLD}Лог развёртывания:${NC}  ${FINAL_LOG}"
echo ""
echo -e "  ${BOLD}────────────────────────────────────────────────────────${NC}"
echo -e "  ${BOLD}SSH-туннель для доступа к шлюзу:${NC}"
echo -e "  ${CYAN}ssh -L 18789:localhost:18789 ${CURRENT_USER}@${CURRENT_HOST}${NC}"
echo ""
echo -e "  ${BOLD}Сопряжение с Telegram:${NC}"
echo -e "  1. Откройте SSH-туннель (команда выше)"
echo -e "  2. Выполните: ${CYAN}openclaw pair telegram${NC}"
echo -e "  3. Следуйте инструкциям на экране"
echo -e "  ${BOLD}────────────────────────────────────────────────────────${NC}"
echo ""
echo -e "  ${GREEN}${BOLD}Kent готов к работе! 👔${NC}"
echo ""
