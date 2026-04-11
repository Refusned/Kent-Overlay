#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  Kent Overlay — скрипт обновления
#  Обновляет OpenClaw, накладывает overlay-файлы, проверяет здоровье
# ============================================================

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

banner() {
  echo ""
  echo -e "${CYAN}${BOLD}╔══════════════════════════════════════╗${NC}"
  echo -e "${CYAN}${BOLD}║         Обновление Kent              ║${NC}"
  echo -e "${CYAN}${BOLD}╚══════════════════════════════════════╝${NC}"
  echo ""
}

log()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[✗]${NC} $*" >&2; }
step()  { echo -e "\n${BOLD}▸ $*${NC}"; }

cleanup() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    echo ""
    err "Обновление завершилось с ошибкой (код $exit_code)."
    echo ""
    echo -e "${YELLOW}═══ Инструкции по откату ═══${NC}"
    if [[ -f /tmp/openclaw-version.bak ]]; then
      local old_ver
      old_ver="$(cat /tmp/openclaw-version.bak)"
      echo -e "  1. Откатить OpenClaw:"
      echo -e "     ${BOLD}pnpm add -g openclaw@${old_ver}${NC}"
    fi
    if [[ -f /tmp/overlay-version.bak ]]; then
      local old_overlay
      old_overlay="$(cat /tmp/overlay-version.bak)"
      echo -e "  2. Версия overlay до обновления: ${BOLD}${old_overlay}${NC}"
    fi
    echo -e "  3. Восстановить бэкап из последней резервной копии"
    echo -e "     (см. каталог бэкапов, созданный backup.sh)"
    echo ""
  fi
}
trap cleanup EXIT

# ------------------------------------------------------------------
#  0. Баннер
# ------------------------------------------------------------------
banner

# ------------------------------------------------------------------
#  1. Загрузка переменных окружения
# ------------------------------------------------------------------
step "Загрузка переменных окружения"

ENV_FILE="${HOME}/.openclaw/.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  log "Файл .env загружен: ${ENV_FILE}"
else
  err "Файл .env не найден: ${ENV_FILE}"
  exit 1
fi

# ------------------------------------------------------------------
#  2. Сохранение текущих версий
# ------------------------------------------------------------------
step "Сохранение текущих версий"

if command -v openclaw &>/dev/null; then
  openclaw --version > /tmp/openclaw-version.bak 2>/dev/null || true
  OLD_OPENCLAW_VERSION="$(cat /tmp/openclaw-version.bak 2>/dev/null || echo 'неизвестно')"
  log "OpenClaw: ${OLD_OPENCLAW_VERSION}"
else
  warn "Команда openclaw не найдена — пропускаем сохранение версии"
  echo "неизвестно" > /tmp/openclaw-version.bak
  OLD_OPENCLAW_VERSION="неизвестно"
fi

cat ~/.openclaw/kent-overlay-version > /tmp/overlay-version.bak 2>/dev/null || true
OLD_OVERLAY_VERSION="$(cat /tmp/overlay-version.bak 2>/dev/null || echo 'неизвестно')"
log "Overlay: ${OLD_OVERLAY_VERSION}"

# ------------------------------------------------------------------
#  3. Создание резервной копии
# ------------------------------------------------------------------
step "Создание резервной копии"

OVERLAY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly OVERLAY_DIR

BACKUP_SCRIPT="${OVERLAY_DIR}/backup.sh"
if [[ -x "$BACKUP_SCRIPT" ]]; then
  bash "$BACKUP_SCRIPT"
  log "Резервная копия создана"
else
  err "Скрипт backup.sh не найден или не исполняемый: ${BACKUP_SCRIPT}"
  exit 1
fi

# ------------------------------------------------------------------
#  4. Определение целевой версии
# ------------------------------------------------------------------
NEW_VERSION="${1:-latest}"
step "Целевая версия OpenClaw: ${NEW_VERSION}"

# ------------------------------------------------------------------
#  5. Обновление OpenClaw
# ------------------------------------------------------------------
step "Обновление OpenClaw"

if ! command -v pnpm &>/dev/null; then
  err "pnpm не найден. Установите pnpm: https://pnpm.io/installation"
  exit 1
fi

pnpm add -g "openclaw@${NEW_VERSION}"
NEW_OPENCLAW_VERSION="$(openclaw --version 2>/dev/null || echo 'неизвестно')"
log "OpenClaw обновлён до: ${NEW_OPENCLAW_VERSION}"

# ------------------------------------------------------------------
#  6. Наложение overlay-файлов
# ------------------------------------------------------------------
step "Наложение overlay-файлов"

OPENCLAW_DIR="${HOME}/.openclaw"

# Файлы, которые НУЖНО перезаписать (системные, управляемые overlay)
OVERWRITE_FILES=(
  "workspace/SOUL.md"
  "workspace/AGENTS.md"
  "workspace/SECURITY.md"
  "workspace/IDENTITY.md"
  "workspace/TOOLS.md"
  "workspace/BOOT.md"
  "config/openclaw.json"
)

for f in "${OVERWRITE_FILES[@]}"; do
  src="${OVERLAY_DIR}/${f}"
  dst="${OPENCLAW_DIR}/${f##*/}"
  # openclaw.json → корень ~/.openclaw/, остальные → workspace/
  if [[ "$f" == "config/openclaw.json" ]]; then
    dst="${OPENCLAW_DIR}/openclaw.json"
  else
    dst="${OPENCLAW_DIR}/workspace/$(basename "$f")"
  fi
  if [[ -f "$src" ]]; then
    cp -f "$src" "$dst"
    log "Обновлён: ${f}"
  else
    warn "Файл не найден в overlay: ${f}"
  fi
done

# Каталог skills/ — полностью перезаписать
if [[ -d "${OVERLAY_DIR}/workspace/skills" ]]; then
  mkdir -p "${OPENCLAW_DIR}/workspace/skills"
  rsync -a --delete "${OVERLAY_DIR}/workspace/skills/" "${OPENCLAW_DIR}/workspace/skills/"
  log "Обновлён каталог: skills/ ($(find "${OVERLAY_DIR}/workspace/skills" -type f | wc -l | tr -d ' ') файлов)"
else
  warn "Каталог workspace/skills/ не найден в overlay"
fi

# tools/pptx_tool.py
if [[ -f "${OVERLAY_DIR}/workspace/tools/pptx_tool.py" ]]; then
  mkdir -p "${OPENCLAW_DIR}/workspace/tools"
  cp -f "${OVERLAY_DIR}/workspace/tools/pptx_tool.py" "${OPENCLAW_DIR}/workspace/tools/pptx_tool.py"
  log "Обновлён: tools/pptx_tool.py"
else
  warn "Файл workspace/tools/pptx_tool.py не найден в overlay"
fi

# cron/jobs.json
if [[ -f "${OVERLAY_DIR}/cron/jobs.json" ]]; then
  mkdir -p "${OPENCLAW_DIR}/cron"
  cp -f "${OVERLAY_DIR}/cron/jobs.json" "${OPENCLAW_DIR}/cron/jobs.json"
  log "Обновлён: cron/jobs.json"
else
  warn "Файл cron/jobs.json не найден в overlay"
fi

# Файлы, которые НЕ перезаписываются (пользовательские данные)
PROTECTED=(
  ".env"
  "MEMORY.md"
  "USER.md"
  "LEARNED.md"
  "memory/"
  "workspace/smm/"
  "workspace/leads/"
  "workspace/crm/"
  "workspace/broadcasts/"
  "workspace/feedback/"
  "workspace/self-improvement/"
)
log "Защищены от перезаписи: ${PROTECTED[*]}"

# ------------------------------------------------------------------
#  7. Обновление Python-зависимостей
# ------------------------------------------------------------------
step "Обновление Python-зависимостей"

PIP_PACKAGES=(
  "faster-whisper"
  "python-pptx"
  "Pillow"
  "PyPDF2"
  "python-docx"
  "openpyxl"
  "pandas"
)

if command -v pip3 &>/dev/null; then
  pip3 install --break-system-packages --upgrade "${PIP_PACKAGES[@]}"
  log "Python-зависимости обновлены"
else
  warn "pip3 не найден — пропускаем обновление Python-зависимостей"
fi

# ------------------------------------------------------------------
#  8. Активация всех хуков
# ------------------------------------------------------------------
step "Активация всех хуков"

while IFS= read -r hook_name; do
  if [[ -n "$hook_name" ]]; then
    if openclaw hooks enable "$hook_name" 2>/dev/null; then
      log "Хук включён: ${hook_name}"
    else
      warn "Не удалось включить хук: ${hook_name} (может быть управляем плагином)"
    fi
  fi
done < <(openclaw hooks list --json 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for h in data.get('hooks', []):
        if not h.get('managedByPlugin', False):
            print(h['name'])
except: pass
" 2>/dev/null)

# ------------------------------------------------------------------
#  9. Проверка совместимости
# ------------------------------------------------------------------
step "Проверка совместимости"

if openclaw doctor; then
  log "openclaw doctor — проверка пройдена"
else
  warn "openclaw doctor обнаружил проблемы (см. вывод выше)"
fi

# ------------------------------------------------------------------
#  10. Перезапуск gateway
# ------------------------------------------------------------------
step "Перезапуск gateway"

openclaw gateway restart
log "Gateway перезапущен"

# ------------------------------------------------------------------
#  11. Health check
# ------------------------------------------------------------------
step "Проверка здоровья (health check)"

HEALTH_URL="http://localhost:18789/healthz"
MAX_WAIT=30
INTERVAL=2
elapsed=0
healthy=false

while [[ $elapsed -lt $MAX_WAIT ]]; do
  if curl -sf "$HEALTH_URL" >/dev/null 2>&1; then
    healthy=true
    break
  fi
  sleep "$INTERVAL"
  elapsed=$((elapsed + INTERVAL))
done

if $healthy; then
  log "Health check пройден (${elapsed}с)"
else
  err "Health check не пройден за ${MAX_WAIT}с — ${HEALTH_URL}"
  exit 1
fi

# ------------------------------------------------------------------
#  12. Аудит безопасности
# ------------------------------------------------------------------
step "Аудит безопасности"

if openclaw security audit --fix --deep; then
  log "Аудит безопасности завершён"
else
  warn "Аудит безопасности обнаружил проблемы (см. вывод выше)"
fi

# ------------------------------------------------------------------
#  13. Обновление версии overlay
# ------------------------------------------------------------------
step "Обновление версии overlay"

if [[ -f "${OVERLAY_DIR}/VERSION" ]]; then
  NEW_OVERLAY_VERSION="$(cat "${OVERLAY_DIR}/VERSION")"
else
  NEW_OVERLAY_VERSION="$(date +%Y%m%d-%H%M%S)"
  warn "Файл VERSION не найден, используется метка времени"
fi

echo "$NEW_OVERLAY_VERSION" > "${HOME}/.openclaw/kent-overlay-version"
log "Версия overlay: ${NEW_OVERLAY_VERSION}"

# ------------------------------------------------------------------
#  14. Итоговый отчёт
# ------------------------------------------------------------------
echo ""
echo -e "${CYAN}${BOLD}══════════════════════════════════════════${NC}"
echo -e "${CYAN}${BOLD}  Обновление Kent завершено успешно${NC}"
echo -e "${CYAN}${BOLD}══════════════════════════════════════════${NC}"
echo ""
echo -e "  OpenClaw:  ${RED}${OLD_OPENCLAW_VERSION}${NC}  →  ${GREEN}${NEW_OPENCLAW_VERSION}${NC}"
echo -e "  Overlay:   ${RED}${OLD_OVERLAY_VERSION}${NC}  →  ${GREEN}${NEW_OVERLAY_VERSION}${NC}"
echo ""
echo -e "  Gateway:   ${GREEN}работает${NC}"
echo -e "  Health:    ${GREEN}OK${NC}"
echo ""
