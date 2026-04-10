#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Скрипт резервного копирования OpenClaw (Kent)
# Создаёт tar.gz архив конфигов, воркспейса, БД и cron-заданий.
# Хранит последние 30 бэкапов, старые удаляет.
# ============================================================

OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
BACKUP_ROOT="${OPENCLAW_HOME}/backups"
BACKUP_DIR="${BACKUP_ROOT}/$(date +%Y-%m-%d_%H%M%S)"
ARCHIVE_NAME="kent-backup.tar.gz"
LOG_DIR="${OPENCLAW_HOME}/logs"
LOG_FILE="${LOG_DIR}/backup.log"
MAX_BACKUPS=30

# --- Загружаем .env (для BACKUP_REMOTE, если задана) ---
ENV_FILE="${OPENCLAW_HOME}/.env"
if [[ -f "$ENV_FILE" ]]; then
    set +e
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set -e
fi

# --- Логирование ---
mkdir -p "$LOG_DIR"

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$LOG_FILE"
}

die() {
    log "ОШИБКА: $1"
    exit 1
}

# --- Собираем список файлов/каталогов для бэкапа ---
declare -a BACKUP_SOURCES=()

add_source() {
    if [[ -e "$1" ]]; then
        BACKUP_SOURCES+=("$1")
    else
        log "ПРЕДУПРЕЖДЕНИЕ: $1 не найден, пропускаю"
    fi
}

add_source "${OPENCLAW_HOME}/openclaw.json"
add_source "${OPENCLAW_HOME}/.env"
add_source "${OPENCLAW_HOME}/workspace"
add_source "${OPENCLAW_HOME}/credentials"
add_source "${OPENCLAW_HOME}/gateway.db"
add_source "${OPENCLAW_HOME}/cron/jobs.json"

if [[ ${#BACKUP_SOURCES[@]} -eq 0 ]]; then
    die "Нет файлов для резервного копирования. Проверьте ${OPENCLAW_HOME}"
fi

# --- Создаём каталог бэкапа ---
mkdir -p "$BACKUP_DIR" || die "Не удалось создать каталог ${BACKUP_DIR}"

ARCHIVE_PATH="${BACKUP_DIR}/${ARCHIVE_NAME}"

log "--- Начало резервного копирования ---"
log "Источники: ${BACKUP_SOURCES[*]}"

# --- Создаём архив ---
if ! tar -czf "$ARCHIVE_PATH" "${BACKUP_SOURCES[@]}" 2>>"$LOG_FILE"; then
    die "Не удалось создать архив ${ARCHIVE_PATH}"
fi

# --- Проверяем целостность архива ---
if ! tar -tzf "$ARCHIVE_PATH" >/dev/null 2>>"$LOG_FILE"; then
    die "Архив повреждён: ${ARCHIVE_PATH}"
fi

log "Архив успешно создан и проверен"

# --- Размер и путь ---
ARCHIVE_SIZE=$(du -sh "$ARCHIVE_PATH" | cut -f1)
log "Размер архива: ${ARCHIVE_SIZE}"
log "Путь: ${ARCHIVE_PATH}"

# --- Ротация: оставляем только последние MAX_BACKUPS ---
EXISTING_BACKUPS=$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | sort)
BACKUP_COUNT=$(echo "$EXISTING_BACKUPS" | wc -l | tr -d ' ')

if [[ "$BACKUP_COUNT" -gt "$MAX_BACKUPS" ]]; then
    DELETE_COUNT=$((BACKUP_COUNT - MAX_BACKUPS))
    log "Удаляю ${DELETE_COUNT} старых бэкапов (лимит: ${MAX_BACKUPS})"
    echo "$EXISTING_BACKUPS" | head -n "$DELETE_COUNT" | while read -r old_backup; do
        rm -rf "$old_backup"
        log "Удалён: ${old_backup}"
    done
fi

# --- Отправка на удалённый сервер (если BACKUP_REMOTE задана) ---
if [[ -n "${BACKUP_REMOTE:-}" ]]; then
    log "Отправка на удалённый сервер: ${BACKUP_REMOTE}"
    if rsync -az "$ARCHIVE_PATH" "${BACKUP_REMOTE}/" 2>>"$LOG_FILE"; then
        log "Успешно отправлено на ${BACKUP_REMOTE}"
    else
        log "ПРЕДУПРЕЖДЕНИЕ: не удалось отправить на ${BACKUP_REMOTE}"
    fi
fi

log "--- Резервное копирование завершено успешно ---"
echo ""
echo "Бэкап готов: ${ARCHIVE_PATH} (${ARCHIVE_SIZE})"
exit 0
