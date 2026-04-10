#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# configure.sh — Интерактивная настройка Kent AI Assistant
# Создаёт .env файл и USER.md на основе пользовательского ввода.
# ============================================================================

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # Сброс цвета

# Директория скрипта
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
USER_MD_TEMPLATE="${SCRIPT_DIR}/workspace/USER.md.template"
USER_MD="${SCRIPT_DIR}/workspace/USER.md"

# --- Обработка Ctrl+C ---
cleanup() {
    echo ""
    echo -e "${YELLOW}⚠ Настройка прервана пользователем.${NC}"
    echo -e "${DIM}  Частично введённые данные не сохранены.${NC}"
    exit 130
}
trap cleanup INT

# --- Вспомогательные функции ---

# Заголовок секции
section() {
    echo ""
    echo -e "${BOLD}${CYAN}▸ $1${NC}"
    echo ""
}

# Информационная подсказка
hint() {
    echo -e "  ${DIM}$1${NC}"
}

# Успешное сообщение
ok() {
    echo -e "  ${GREEN}✔${NC} $1"
}

# Предупреждение
warning() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

# Ошибка
error() {
    echo -e "  ${RED}✘${NC} $1"
}

# Запрос обязательного значения. Аргументы: описание, имя переменной, подсказка (необяз.)
ask_required() {
    local prompt="$1"
    local varname="$2"
    local hint_text="${3:-}"
    local value=""

    [[ -n "$hint_text" ]] && hint "$hint_text"

    while [[ -z "$value" ]]; do
        read -r -p "  ${prompt}: " value
        if [[ -z "$value" ]]; then
            error "Это поле обязательно для заполнения."
        fi
    done

    # Записываем значение в переменную по имени
    eval "$varname=\"\$value\""
}

# Запрос значения с умолчанием. Аргументы: описание, имя переменной, значение по умолчанию
ask_default() {
    local prompt="$1"
    local varname="$2"
    local default="$3"
    local value=""

    read -r -p "  ${prompt} [${default}]: " value
    value="${value:-$default}"
    eval "$varname=\"\$value\""
}

# Запрос да/нет. Возвращает 0 = да, 1 = нет
ask_yesno() {
    local prompt="$1"
    local answer=""

    read -r -p "  ${prompt} (y/n) [n]: " answer
    case "$answer" in
        [yY]|[yY][eE][sS]|[дД]|[дД][аА]) return 0 ;;
        *) return 1 ;;
    esac
}

# Запрос необязательного значения. Возвращает пустую строку, если пропущено.
ask_optional() {
    local prompt="$1"
    local varname="$2"
    local hint_text="${3:-}"
    local value=""

    [[ -n "$hint_text" ]] && hint "$hint_text"
    read -r -p "  ${prompt} (Enter — пропустить): " value
    eval "$varname=\"\$value\""
}

# ============================================================================
# Начало настройки
# ============================================================================

echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Настройка Kent AI Assistant${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Этот скрипт поможет создать конфигурационный файл ${CYAN}.env${NC}"
echo -e "  для вашего персонального ИИ-ассистента Kent."
echo ""

# --- Проверка существующего .env ---
OVERWRITE_MODE="create" # create | overwrite | update

if [[ -f "$ENV_FILE" ]]; then
    warning "Файл .env уже существует: ${ENV_FILE}"
    echo ""
    echo -e "  ${BOLD}Что сделать?${NC}"
    echo -e "  ${CYAN}1${NC} — Перезаписать (создать заново)"
    echo -e "  ${CYAN}2${NC} — Обновить (изменить только выбранные значения)"
    echo -e "  ${CYAN}3${NC} — Отмена"
    echo ""
    read -r -p "  Ваш выбор [1/2/3]: " choice
    case "$choice" in
        1) OVERWRITE_MODE="overwrite"
           ok "Файл .env будет перезаписан."
           ;;
        2) OVERWRITE_MODE="update"
           ok "Режим обновления: текущие значения будут предложены как умолчания."
           # Загружаем текущие значения
           # shellcheck disable=SC1090
           source "$ENV_FILE" 2>/dev/null || true
           ;;
        *) echo ""
           echo -e "  Настройка отменена."
           exit 0
           ;;
    esac
fi

# --- Массив для сбора переменных ---
declare -A CONFIG

# ============================================================================
# Шаг 1: Данные клиента
# ============================================================================
section "Данные клиента"

if [[ "$OVERWRITE_MODE" == "update" && -n "${CLIENT_NAME:-}" ]]; then
    ask_default "Имя клиента" CONFIG_CLIENT_NAME "${CLIENT_NAME}"
else
    ask_required "Имя клиента" CONFIG_CLIENT_NAME
fi
CONFIG[CLIENT_NAME]="$CONFIG_CLIENT_NAME"

if [[ "$OVERWRITE_MODE" == "update" && -n "${CLIENT_ROLE:-}" ]]; then
    ask_default "Должность или род деятельности" CONFIG_CLIENT_ROLE "${CLIENT_ROLE}"
else
    ask_required "Должность или род деятельности" CONFIG_CLIENT_ROLE
fi
CONFIG[CLIENT_ROLE]="$CONFIG_CLIENT_ROLE"

if [[ "$OVERWRITE_MODE" == "update" && -n "${CLIENT_TZ:-}" ]]; then
    ask_default "Часовой пояс" CONFIG_CLIENT_TZ "${CLIENT_TZ}"
else
    ask_default "Часовой пояс" CONFIG_CLIENT_TZ "Europe/Moscow"
fi
CONFIG[CLIENT_TZ]="$CONFIG_CLIENT_TZ"

if [[ "$OVERWRITE_MODE" == "update" && -n "${CLIENT_LANG:-}" ]]; then
    ask_default "Язык общения" CONFIG_CLIENT_LANG "${CLIENT_LANG}"
else
    ask_default "Язык общения" CONFIG_CLIENT_LANG "ru"
fi
CONFIG[CLIENT_LANG]="$CONFIG_CLIENT_LANG"

# ============================================================================
# Шаг 2: Telegram
# ============================================================================
section "Telegram"

if [[ "$OVERWRITE_MODE" == "update" && -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
    ask_default "Токен Telegram-бота" CONFIG_TELEGRAM_BOT_TOKEN "${TELEGRAM_BOT_TOKEN}"
else
    ask_required "Токен Telegram-бота" CONFIG_TELEGRAM_BOT_TOKEN \
        "Создайте бота через @BotFather в Telegram и скопируйте токен."
fi
CONFIG[TELEGRAM_BOT_TOKEN]="$CONFIG_TELEGRAM_BOT_TOKEN"

if [[ "$OVERWRITE_MODE" == "update" && -n "${CLIENT_TELEGRAM_ID:-}" ]]; then
    ask_default "Ваш Telegram ID" CONFIG_CLIENT_TELEGRAM_ID "${CLIENT_TELEGRAM_ID}"
else
    ask_required "Ваш Telegram ID (число)" CONFIG_CLIENT_TELEGRAM_ID \
        "Отправьте /start боту @userinfobot — он покажет ваш ID."
fi
CONFIG[CLIENT_TELEGRAM_ID]="$CONFIG_CLIENT_TELEGRAM_ID"

# ============================================================================
# Шаг 3: Токен шлюза OpenClaw
# ============================================================================
section "OpenClaw Gateway"

echo -e "  Генерация токена шлюза..."
CONFIG_OPENCLAW_GATEWAY_TOKEN="$(openssl rand -hex 32)"
ok "OPENCLAW_GATEWAY_TOKEN сгенерирован."
CONFIG[OPENCLAW_GATEWAY_TOKEN]="$CONFIG_OPENCLAW_GATEWAY_TOKEN"

# ============================================================================
# Шаг 4: Авторизация OpenClaw Codex (OAuth для моделей)
# ============================================================================
section "Авторизация в OpenClaw Codex"

echo -e "  Сейчас откроется OAuth-авторизация для доступа к моделям."
hint "Для headless-серверов: скопируйте URL и откройте в браузере на другом устройстве."
echo ""

if command -v openclaw &>/dev/null; then
    if ask_yesno "Запустить openclaw codex auth сейчас?"; then
        echo ""
        openclaw codex auth || {
            warning "openclaw codex auth завершился с ошибкой. Можно повторить позже."
        }
    else
        warning "Пропущено. Выполните вручную: openclaw codex auth"
    fi
else
    warning "Команда openclaw не найдена. Установите OpenClaw и выполните: openclaw codex auth"
fi

# ============================================================================
# Шаг 5: Авторизация OpenAI (OAuth для генерации изображений)
# ============================================================================
section "Авторизация OpenAI (генерация изображений)"

echo -e "  OAuth-авторизация для ChatGPT / DALL-E."
hint "Для headless-серверов: скопируйте URL и откройте в браузере на другом устройстве."
echo ""

if command -v openclaw &>/dev/null; then
    if ask_yesno "Запустить openclaw auth login openai сейчас?"; then
        echo ""
        openclaw auth login openai || {
            warning "openclaw auth login openai завершился с ошибкой. Можно повторить позже."
        }
    else
        warning "Пропущено. Выполните вручную: openclaw auth login openai"
    fi
else
    warning "Команда openclaw не найдена. Установите OpenClaw и выполните: openclaw auth login openai"
fi

# ============================================================================
# Шаг 6: Опциональные интеграции
# ============================================================================
section "Опциональные интеграции"

echo -e "  Настройте интеграции с внешними сервисами."
echo -e "  Можно пропустить и добавить позже в .env вручную."
echo ""

# --- Google ---
if ask_yesno "Подключить Google (Calendar, Gmail и т.д.)?"; then
    echo ""
    ask_required "  GOOGLE_CLIENT_ID" CONFIG_GOOGLE_CLIENT_ID
    CONFIG[GOOGLE_CLIENT_ID]="$CONFIG_GOOGLE_CLIENT_ID"
    ask_required "  GOOGLE_CLIENT_SECRET" CONFIG_GOOGLE_CLIENT_SECRET
    CONFIG[GOOGLE_CLIENT_SECRET]="$CONFIG_GOOGLE_CLIENT_SECRET"
    ask_required "  GOOGLE_REFRESH_TOKEN" CONFIG_GOOGLE_REFRESH_TOKEN
    CONFIG[GOOGLE_REFRESH_TOKEN]="$CONFIG_GOOGLE_REFRESH_TOKEN"
    ok "Google интеграция настроена."
fi
echo ""

# --- Twitter / X ---
if ask_yesno "Подключить Twitter / X?"; then
    echo ""
    ask_required "  TWITTER_API_KEY" CONFIG_TWITTER_API_KEY
    CONFIG[TWITTER_API_KEY]="$CONFIG_TWITTER_API_KEY"
    ask_required "  TWITTER_API_SECRET" CONFIG_TWITTER_API_SECRET
    CONFIG[TWITTER_API_SECRET]="$CONFIG_TWITTER_API_SECRET"
    ask_required "  TWITTER_ACCESS_TOKEN" CONFIG_TWITTER_ACCESS_TOKEN
    CONFIG[TWITTER_ACCESS_TOKEN]="$CONFIG_TWITTER_ACCESS_TOKEN"
    ok "Twitter / X интеграция настроена."
fi
echo ""

# --- Яндекс Алиса ---
if ask_yesno "Подключить Яндекс Алису?"; then
    echo ""
    hint "Получите OAuth-токен на https://oauth.yandex.ru/"
    hint "Создайте приложение с доступом к Алисе и скопируйте токен."
    ask_required "  YANDEX_OAUTH_TOKEN" CONFIG_YANDEX_OAUTH_TOKEN
    CONFIG[YANDEX_OAUTH_TOKEN]="$CONFIG_YANDEX_OAUTH_TOKEN"
    ok "Яндекс Алиса интеграция настроена."
fi
echo ""

# --- ElevenLabs ---
if ask_yesno "Подключить ElevenLabs (синтез речи)?"; then
    echo ""
    ask_required "  ELEVENLABS_API_KEY" CONFIG_ELEVENLABS_API_KEY
    CONFIG[ELEVENLABS_API_KEY]="$CONFIG_ELEVENLABS_API_KEY"
    ok "ElevenLabs интеграция настроена."
fi
echo ""

# --- Tavily Search ---
if ask_yesno "Подключить Tavily Search (поиск в интернете)?"; then
    echo ""
    ask_required "  TAVILY_API_KEY" CONFIG_TAVILY_API_KEY
    CONFIG[TAVILY_API_KEY]="$CONFIG_TAVILY_API_KEY"
    ok "Tavily Search интеграция настроена."
fi

# ============================================================================
# Шаг 7: Оператор (мониторинг и уведомления)
# ============================================================================
section "Оператор (уведомления и мониторинг)"

hint "Бот-оператор отправляет уведомления о работе системы."
echo ""

if [[ "$OVERWRITE_MODE" == "update" && -n "${OPERATOR_TELEGRAM_BOT_TOKEN:-}" ]]; then
    ask_default "Токен бота-оператора" CONFIG_OPERATOR_TELEGRAM_BOT_TOKEN "${OPERATOR_TELEGRAM_BOT_TOKEN}"
else
    ask_required "Токен бота-оператора (OPERATOR_TELEGRAM_BOT_TOKEN)" CONFIG_OPERATOR_TELEGRAM_BOT_TOKEN
fi
CONFIG[OPERATOR_TELEGRAM_BOT_TOKEN]="$CONFIG_OPERATOR_TELEGRAM_BOT_TOKEN"

if [[ "$OVERWRITE_MODE" == "update" && -n "${OPERATOR_TELEGRAM_CHAT_ID:-}" ]]; then
    ask_default "Chat ID оператора" CONFIG_OPERATOR_TELEGRAM_CHAT_ID "${OPERATOR_TELEGRAM_CHAT_ID}"
else
    ask_required "Chat ID оператора (OPERATOR_TELEGRAM_CHAT_ID)" CONFIG_OPERATOR_TELEGRAM_CHAT_ID
fi
CONFIG[OPERATOR_TELEGRAM_CHAT_ID]="$CONFIG_OPERATOR_TELEGRAM_CHAT_ID"

# ============================================================================
# Шаг 8: Групповые чаты (необязательно)
# ============================================================================
section "Групповые чаты (необязательно)"

hint "Если Kent должен работать в групповых чатах, укажите их ID."
echo ""

ask_optional "GROUP_1_ID" CONFIG_GROUP_1_ID
[[ -n "${CONFIG_GROUP_1_ID:-}" ]] && CONFIG[GROUP_1_ID]="$CONFIG_GROUP_1_ID"

ask_optional "GROUP_2_ID" CONFIG_GROUP_2_ID
[[ -n "${CONFIG_GROUP_2_ID:-}" ]] && CONFIG[GROUP_2_ID]="$CONFIG_GROUP_2_ID"

# ============================================================================
# Шаг 9: Запись .env файла
# ============================================================================
section "Сохранение конфигурации"

echo -e "  Запись файла: ${CYAN}${ENV_FILE}${NC}"
echo ""

{
    echo "# ============================================================================"
    echo "# Kent AI Assistant — Конфигурация"
    echo "# Сгенерировано: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "# ============================================================================"
    echo ""
    echo "# --- Данные клиента ---"
    echo "CLIENT_NAME=\"${CONFIG[CLIENT_NAME]}\""
    echo "CLIENT_ROLE=\"${CONFIG[CLIENT_ROLE]}\""
    echo "CLIENT_TZ=\"${CONFIG[CLIENT_TZ]}\""
    echo "CLIENT_LANG=\"${CONFIG[CLIENT_LANG]}\""
    echo ""
    echo "# --- Telegram ---"
    echo "TELEGRAM_BOT_TOKEN=\"${CONFIG[TELEGRAM_BOT_TOKEN]}\""
    echo "CLIENT_TELEGRAM_ID=\"${CONFIG[CLIENT_TELEGRAM_ID]}\""
    echo ""
    echo "# --- OpenClaw ---"
    echo "OPENCLAW_GATEWAY_TOKEN=\"${CONFIG[OPENCLAW_GATEWAY_TOKEN]}\""
    echo ""
    echo "# --- Оператор ---"
    echo "OPERATOR_TELEGRAM_BOT_TOKEN=\"${CONFIG[OPERATOR_TELEGRAM_BOT_TOKEN]}\""
    echo "OPERATOR_TELEGRAM_CHAT_ID=\"${CONFIG[OPERATOR_TELEGRAM_CHAT_ID]}\""

    # Опциональные интеграции
    if [[ -n "${CONFIG[GOOGLE_CLIENT_ID]:-}" ]]; then
        echo ""
        echo "# --- Google ---"
        echo "GOOGLE_CLIENT_ID=\"${CONFIG[GOOGLE_CLIENT_ID]}\""
        echo "GOOGLE_CLIENT_SECRET=\"${CONFIG[GOOGLE_CLIENT_SECRET]}\""
        echo "GOOGLE_REFRESH_TOKEN=\"${CONFIG[GOOGLE_REFRESH_TOKEN]}\""
    fi

    if [[ -n "${CONFIG[TWITTER_API_KEY]:-}" ]]; then
        echo ""
        echo "# --- Twitter / X ---"
        echo "TWITTER_API_KEY=\"${CONFIG[TWITTER_API_KEY]}\""
        echo "TWITTER_API_SECRET=\"${CONFIG[TWITTER_API_SECRET]}\""
        echo "TWITTER_ACCESS_TOKEN=\"${CONFIG[TWITTER_ACCESS_TOKEN]}\""
    fi

    if [[ -n "${CONFIG[YANDEX_OAUTH_TOKEN]:-}" ]]; then
        echo ""
        echo "# --- Яндекс Алиса ---"
        echo "YANDEX_OAUTH_TOKEN=\"${CONFIG[YANDEX_OAUTH_TOKEN]}\""
    fi

    if [[ -n "${CONFIG[ELEVENLABS_API_KEY]:-}" ]]; then
        echo ""
        echo "# --- ElevenLabs ---"
        echo "ELEVENLABS_API_KEY=\"${CONFIG[ELEVENLABS_API_KEY]}\""
    fi

    if [[ -n "${CONFIG[TAVILY_API_KEY]:-}" ]]; then
        echo ""
        echo "# --- Tavily Search ---"
        echo "TAVILY_API_KEY=\"${CONFIG[TAVILY_API_KEY]}\""
    fi

    if [[ -n "${CONFIG[GROUP_1_ID]:-}" || -n "${CONFIG[GROUP_2_ID]:-}" ]]; then
        echo ""
        echo "# --- Групповые чаты ---"
        [[ -n "${CONFIG[GROUP_1_ID]:-}" ]] && echo "GROUP_1_ID=\"${CONFIG[GROUP_1_ID]}\""
        [[ -n "${CONFIG[GROUP_2_ID]:-}" ]] && echo "GROUP_2_ID=\"${CONFIG[GROUP_2_ID]}\""
    fi

    echo ""
} > "$ENV_FILE"

ok "Файл .env сохранён."

# ============================================================================
# Шаг 10: Генерация USER.md из шаблона
# ============================================================================
section "Генерация USER.md"

if [[ -f "$USER_MD_TEMPLATE" ]]; then
    echo -e "  Шаблон: ${CYAN}${USER_MD_TEMPLATE}${NC}"

    # Экспортируем переменные для envsubst / sed
    export CLIENT_NAME="${CONFIG[CLIENT_NAME]}"
    export CLIENT_ROLE="${CONFIG[CLIENT_ROLE]}"
    export CLIENT_TZ="${CONFIG[CLIENT_TZ]}"
    export CLIENT_LANG="${CONFIG[CLIENT_LANG]}"
    export CLIENT_TELEGRAM_ID="${CONFIG[CLIENT_TELEGRAM_ID]}"

    if command -v envsubst &>/dev/null; then
        envsubst < "$USER_MD_TEMPLATE" > "$USER_MD"
    else
        # Фолбэк на sed, если envsubst недоступен
        sed \
            -e "s|\\\${CLIENT_NAME}|${CONFIG[CLIENT_NAME]}|g" \
            -e "s|\\\$CLIENT_NAME|${CONFIG[CLIENT_NAME]}|g" \
            -e "s|\\\${CLIENT_ROLE}|${CONFIG[CLIENT_ROLE]}|g" \
            -e "s|\\\$CLIENT_ROLE|${CONFIG[CLIENT_ROLE]}|g" \
            -e "s|\\\${CLIENT_TZ}|${CONFIG[CLIENT_TZ]}|g" \
            -e "s|\\\$CLIENT_TZ|${CONFIG[CLIENT_TZ]}|g" \
            -e "s|\\\${CLIENT_LANG}|${CONFIG[CLIENT_LANG]}|g" \
            -e "s|\\\$CLIENT_LANG|${CONFIG[CLIENT_LANG]}|g" \
            -e "s|\\\${CLIENT_TELEGRAM_ID}|${CONFIG[CLIENT_TELEGRAM_ID]}|g" \
            -e "s|\\\$CLIENT_TELEGRAM_ID|${CONFIG[CLIENT_TELEGRAM_ID]}|g" \
            "$USER_MD_TEMPLATE" > "$USER_MD"
    fi

    ok "USER.md сгенерирован: ${USER_MD}"
else
    warning "Шаблон USER.md.template не найден: ${USER_MD_TEMPLATE}"
    warning "USER.md не был создан. Создайте шаблон или напишите USER.md вручную."
fi

# ============================================================================
# Итоги
# ============================================================================
echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Настройка завершена${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${GREEN}✔${NC} Клиент: ${BOLD}${CONFIG[CLIENT_NAME]}${NC} (${CONFIG[CLIENT_ROLE]})"
echo -e "  ${GREEN}✔${NC} Часовой пояс: ${CONFIG[CLIENT_TZ]}"
echo -e "  ${GREEN}✔${NC} Язык: ${CONFIG[CLIENT_LANG]}"
echo -e "  ${GREEN}✔${NC} Telegram ID: ${CONFIG[CLIENT_TELEGRAM_ID]}"
echo -e "  ${GREEN}✔${NC} Файл .env: ${ENV_FILE}"

[[ -f "$USER_MD" ]] && echo -e "  ${GREEN}✔${NC} USER.md: ${USER_MD}"

# Показываем, какие интеграции подключены
INTEGRATIONS=()
[[ -n "${CONFIG[GOOGLE_CLIENT_ID]:-}" ]]    && INTEGRATIONS+=("Google")
[[ -n "${CONFIG[TWITTER_API_KEY]:-}" ]]     && INTEGRATIONS+=("Twitter/X")
[[ -n "${CONFIG[YANDEX_OAUTH_TOKEN]:-}" ]]  && INTEGRATIONS+=("Яндекс Алиса")
[[ -n "${CONFIG[ELEVENLABS_API_KEY]:-}" ]]  && INTEGRATIONS+=("ElevenLabs")
[[ -n "${CONFIG[TAVILY_API_KEY]:-}" ]]      && INTEGRATIONS+=("Tavily Search")

if [[ ${#INTEGRATIONS[@]} -gt 0 ]]; then
    echo -e "  ${GREEN}✔${NC} Интеграции: ${INTEGRATIONS[*]}"
else
    echo -e "  ${DIM}  Внешние интеграции не настроены${NC}"
fi

echo ""
echo -e "  Следующий шаг: запустите ${CYAN}./prerequisites.sh${NC} для проверки зависимостей."
echo ""
