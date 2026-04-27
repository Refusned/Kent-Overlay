#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# deploy-demo.sh — Развёртывание демо-бота Kent
# Превращает подготовленный VPS в демо-инстанс Kent.
# Идемпотентен — безопасен для повторного запуска.
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

TOTAL_STEPS=14
CURRENT_STEP=0

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
    echo -e "${RED}${BOLD}  Развёртывание прервано.${NC}" >&2
    # Rollback если бэкап существует
    if [[ -d "${OPENCLAW_HOME}.bak" ]]; then
        warn "Восстанавливаю из бэкапа..."
        rm -rf "$OPENCLAW_HOME"
        mv "${OPENCLAW_HOME}.bak" "$OPENCLAW_HOME"
        ok "Бэкап восстановлен"
    fi
    exit 1
}

LOG_FILE="/tmp/kent-demo-deploy-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# ============================================================================
# [1] Инициализация
# ============================================================================
step "Инициализация"

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY_DIR="$(dirname "$DEMO_DIR")"
OPENCLAW_HOME="${HOME}/.openclaw"

echo ""
echo -e "${BOLD}  ╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}  ║                                              ║${NC}"
echo -e "${BOLD}  ║    Kent Demo Bot — Deployment Script          ║${NC}"
echo -e "${BOLD}  ║    Powered by OpenClaw                        ║${NC}"
echo -e "${BOLD}  ║                                              ║${NC}"
echo -e "${BOLD}  ╚══════════════════════════════════════════════╝${NC}"
echo ""

ok "DEMO_DIR: ${DEMO_DIR}"
ok "OVERLAY_DIR: ${OVERLAY_DIR}"
ok "OPENCLAW_HOME: ${OPENCLAW_HOME}"
ok "Дата: $(date '+%Y-%m-%d %H:%M:%S')"
ok "Пользователь: $(whoami)"
ok "Лог: ${LOG_FILE}"

# ============================================================================
# [2] Проверка зависимостей
# ============================================================================
step "Проверка зависимостей"

check_cmd() {
    if command -v "$1" &>/dev/null; then
        ok "$1 — $(command -v "$1")"
    else
        die "$1 не найден. Установите перед запуском."
    fi
}

check_cmd node
check_cmd pnpm
check_cmd python3
check_cmd docker
check_cmd openssl
check_cmd curl

NODE_VERSION=$(node --version | sed 's/v//' | cut -d. -f1)
if [[ "$NODE_VERSION" -lt 22 ]]; then
    die "Node.js >= 22 обязателен, текущая версия: $(node --version)"
fi
ok "Node.js $(node --version)"

# Проверяем OpenClaw
if command -v openclaw &>/dev/null; then
    ok "OpenClaw: $(openclaw --version 2>/dev/null || echo 'установлен')"
else
    warn "OpenClaw не установлен, будет установлен на следующем шаге"
fi

# ============================================================================
# [3] Установка OpenClaw и Codex CLI
# ============================================================================
step "Установка OpenClaw и Codex CLI"

OPENCLAW_TARGET_VERSION="${OPENCLAW_VERSION:-2026.4.10}"

if ! command -v openclaw &>/dev/null; then
    info "Устанавливаю openclaw@${OPENCLAW_TARGET_VERSION}..."
    pnpm add -g "openclaw@${OPENCLAW_TARGET_VERSION}"
    ok "OpenClaw установлен"
else
    ok "OpenClaw уже установлен"
fi

if ! command -v codex &>/dev/null; then
    info "Устанавливаю @openai/codex..."
    pnpm add -g @openai/codex
    ok "Codex CLI установлен"
else
    ok "Codex CLI уже установлен"
fi

# ============================================================================
# [4] Бэкап текущего состояния
# ============================================================================
step "Бэкап текущего состояния"

if [[ -d "$OPENCLAW_HOME" ]]; then
    BACKUP_DIR="${OPENCLAW_HOME}.bak"
    if [[ -d "$BACKUP_DIR" ]]; then
        rm -rf "$BACKUP_DIR"
    fi
    cp -a "$OPENCLAW_HOME" "$BACKUP_DIR"
    ok "Бэкап создан: ${BACKUP_DIR}"
else
    info "Первый деплой — бэкап не нужен"
fi

# ============================================================================
# [5] Создание структуры директорий
# ============================================================================
step "Создание структуры директорий"

mkdir -p "${OPENCLAW_HOME}"/{workspace/skills,workspace/memory,workspace/faq,credentials,logs,sessions}
ok "Директории созданы"

# ============================================================================
# [6] Копирование демо-конфигурации
# ============================================================================
step "Копирование демо-конфигурации"

# Конфиг OpenClaw
cp "${DEMO_DIR}/openclaw-demo.json" "${OPENCLAW_HOME}/openclaw.json"
ok "openclaw.json ← openclaw-demo.json"

# Workspace файлы (демо-версии → без суффикса -DEMO)
cp "${DEMO_DIR}/AGENTS-DEMO.md" "${OPENCLAW_HOME}/workspace/AGENTS.md"
ok "AGENTS.md ← AGENTS-DEMO.md"

cp "${DEMO_DIR}/SOUL-DEMO.md" "${OPENCLAW_HOME}/workspace/SOUL.md"
ok "SOUL.md ← SOUL-DEMO.md"

cp "${DEMO_DIR}/SECURITY-DEMO.md" "${OPENCLAW_HOME}/workspace/SECURITY.md"
ok "SECURITY.md ← SECURITY-DEMO.md"

# ============================================================================
# [7] Копирование скиллов (только 5 демо-скиллов)
# ============================================================================
step "Копирование скиллов (5 из 17)"

DEMO_SKILLS="humanize social-drafts faq-responder weather-fallback coder"

for skill in $DEMO_SKILLS; do
    SKILL_SRC="${OVERLAY_DIR}/workspace/skills/${skill}"
    SKILL_DST="${OPENCLAW_HOME}/workspace/skills/${skill}"
    if [[ -d "$SKILL_SRC" ]]; then
        cp -r "$SKILL_SRC" "$SKILL_DST"
        ok "${skill}"
    else
        warn "${skill} — не найден в ${SKILL_SRC}, пропускаю"
    fi
done

# ============================================================================
# [8] Генерация токенов и создание .env
# ============================================================================
step "Настройка .env"

ENV_FILE="${OPENCLAW_HOME}/.env"

# Генерируем токены если нет
if [[ ! -f "$ENV_FILE" ]] || ! grep -q "OPENCLAW_GATEWAY_TOKEN=" "$ENV_FILE" 2>/dev/null; then
    GATEWAY_TOKEN=$(openssl rand -hex 16)
    HOOKS_TOKEN=$(openssl rand -hex 16)

    # Запрашиваем Telegram Bot Token
    echo ""
    echo -e "${YELLOW}${BOLD}  Введите Telegram Bot Token для демо-бота:${NC}"
    echo -e "  ${DIM}(Получить у @BotFather в Telegram)${NC}"
    read -r -p "  Token: " DEMO_BOT_TOKEN

    if [[ -z "$DEMO_BOT_TOKEN" ]]; then
        die "Telegram Bot Token обязателен!"
    fi

    cat > "$ENV_FILE" << EOF
# Kent Demo Bot — Переменные окружения
# Сгенерировано: $(date '+%Y-%m-%d %H:%M:%S')

OPENCLAW_GATEWAY_TOKEN=${GATEWAY_TOKEN}
OPENCLAW_HOOKS_TOKEN=${HOOKS_TOKEN}
DEMO_TELEGRAM_BOT_TOKEN=${DEMO_BOT_TOKEN}
CLIENT_TZ=Europe/Moscow
OPENCLAW_DISABLE_BONJOUR=1
OPENCLAW_VERSION=${OPENCLAW_TARGET_VERSION}

# Мониторинг (заполнить для получения алертов)
OPERATOR_TELEGRAM_BOT_TOKEN=
OPERATOR_TELEGRAM_CHAT_ID=
EOF

    ok "Токены сгенерированы, .env создан"
else
    ok ".env уже существует, пропускаю"
fi

# Безопасные права
chmod 600 "$ENV_FILE"
chmod 700 "$OPENCLAW_HOME"
ok "Права доступа: .env 600, .openclaw 700"

# ============================================================================
# [9] Установка Python-зависимостей (faster-whisper для STT)
# ============================================================================
step "Python-зависимости (faster-whisper для голосового ввода)"

if python3 -c "import faster_whisper" 2>/dev/null; then
    ok "faster-whisper уже установлен"
else
    info "Устанавливаю faster-whisper..."
    pip3 install --break-system-packages faster-whisper 2>/dev/null || \
    pip3 install faster-whisper 2>/dev/null || \
    warn "Не удалось установить faster-whisper. Голосовые сообщения могут не работать"
fi

# ============================================================================
# [10] Настройка UFW (firewall)
# ============================================================================
step "Настройка firewall (UFW)"

if command -v ufw &>/dev/null; then
    # Блокируем gateway порт снаружи (он на loopback, но на всякий случай)
    sudo ufw deny 18789/tcp 2>/dev/null && ok "Порт 18789 заблокирован извне" || warn "UFW: не удалось заблокировать 18789"
    sudo ufw allow 22/tcp 2>/dev/null && ok "SSH порт 22 разрешён" || true
    echo "y" | sudo ufw enable 2>/dev/null && ok "UFW включён" || warn "UFW уже включён или не настроен"
else
    warn "UFW не установлен, пропускаю"
fi

# ============================================================================
# [11] Установка systemd-сервиса
# ============================================================================
step "Установка systemd-сервиса"

SERVICE_SRC="${DEMO_DIR}/systemd/kent-demo.service"
SERVICE_DST="/etc/systemd/system/kent-demo.service"

if [[ -f "$SERVICE_SRC" ]]; then
    sudo cp "$SERVICE_SRC" "$SERVICE_DST"
    sudo systemctl daemon-reload
    ok "kent-demo.service установлен"
else
    warn "Файл сервиса не найден: ${SERVICE_SRC}"
fi

# ============================================================================
# [12] Настройка logrotate
# ============================================================================
step "Настройка logrotate"

sudo tee /etc/logrotate.d/kent-demo > /dev/null << 'EOF'
/home/kent/.openclaw/logs/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 kent kent
}
EOF
ok "Logrotate настроен (14 дней, сжатие)"

# ============================================================================
# [13] Настройка cron (session cleanup + monitor)
# ============================================================================
step "Настройка cron"

# Session cleanup — удаляем сессии старше 7 дней (ежедневно в 4:00)
CLEANUP_CRON="0 4 * * * find ${OPENCLAW_HOME}/sessions/ -type d -mtime +7 -exec rm -rf {} + 2>/dev/null"

# Monitor — каждые 5 минут
MONITOR_SCRIPT="${HOME}/monitor-demo.sh"
MONITOR_CRON="*/5 * * * * ${MONITOR_SCRIPT} 2>/dev/null"

# Копируем monitor
if [[ -f "${DEMO_DIR}/monitor-demo.sh" ]]; then
    cp "${DEMO_DIR}/monitor-demo.sh" "$MONITOR_SCRIPT"
    chmod +x "$MONITOR_SCRIPT"
    ok "monitor-demo.sh скопирован"
fi

# Добавляем cron (без дублирования)
(crontab -l 2>/dev/null | grep -v "kent-demo\|monitor-demo\|openclaw/sessions"; \
 echo "# kent-demo: cleanup sessions"; \
 echo "$CLEANUP_CRON"; \
 echo "# kent-demo: monitoring"; \
 echo "$MONITOR_CRON") | crontab -
ok "Cron настроен: cleanup + monitoring"

# ============================================================================
# [14] Финальная проверка
# ============================================================================
step "Финальная проверка"

ERRORS=0

# Проверяем файлы
for f in openclaw.json .env workspace/SOUL.md workspace/SECURITY.md workspace/AGENTS.md; do
    if [[ -f "${OPENCLAW_HOME}/${f}" ]]; then
        ok "✓ ${f}"
    else
        fail "✗ ${f} — НЕ НАЙДЕН"
        ERRORS=$((ERRORS + 1))
    fi
done

# Проверяем скиллы
for skill in $DEMO_SKILLS; do
    if [[ -d "${OPENCLAW_HOME}/workspace/skills/${skill}" ]]; then
        ok "✓ skill: ${skill}"
    else
        warn "✗ skill: ${skill} — не найден"
    fi
done

# Проверяем права
ENV_PERM=$(stat -c "%a" "$ENV_FILE" 2>/dev/null || stat -f "%OLp" "$ENV_FILE" 2>/dev/null)
if [[ "$ENV_PERM" == "600" ]]; then
    ok "✓ .env chmod 600"
else
    warn ".env chmod ${ENV_PERM} (должно быть 600)"
fi

# Docker
if docker info &>/dev/null; then
    ok "✓ Docker доступен"
else
    warn "Docker не доступен текущему пользователю"
fi

echo ""
if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}  ╔══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}  ║   Деплой завершён успешно!                   ║${NC}"
    echo -e "${GREEN}${BOLD}  ╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Следующие шаги:"
    echo -e "  ${CYAN}1.${NC} Авторизуйте Codex:"
    echo -e "     ${DIM}ssh -L 1455:localhost:1455 kent@<server-ip>${NC}"
    echo -e "     ${DIM}codex login${NC}"
    echo ""
    echo -e "  ${CYAN}2.${NC} Запустите бота:"
    echo -e "     ${DIM}sudo systemctl enable kent-demo${NC}"
    echo -e "     ${DIM}sudo systemctl start kent-demo${NC}"
    echo ""
    echo -e "  ${CYAN}3.${NC} Проверьте здоровье:"
    echo -e "     ${DIM}curl http://localhost:18789/healthz${NC}"
    echo ""
    echo -e "  ${CYAN}4.${NC} Запустите автотесты:"
    echo -e "     ${DIM}bash ${DEMO_DIR}/test-demo.sh${NC}"
else
    echo -e "${RED}${BOLD}  Деплой завершён с ${ERRORS} ошибками!${NC}"
    echo -e "  Проверьте лог: ${LOG_FILE}"
fi

# Удаляем бэкап при успехе
if [[ $ERRORS -eq 0 ]] && [[ -d "${OPENCLAW_HOME}.bak" ]]; then
    rm -rf "${OPENCLAW_HOME}.bak"
    info "Бэкап удалён (деплой успешен)"
fi
