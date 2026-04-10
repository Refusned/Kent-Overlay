# Восстановление после сбоя

Руководство по резервному копированию, восстановлению и миграции Kent AI Assistant.

---

## Стратегия резервного копирования

### Что нужно бэкапить

| Файл / каталог | Описание | Критичность | Размер |
|----------------|----------|-------------|--------|
| `.env` | Токены и ключи API | Критический | < 1 KB |
| `config/SOUL.md` | Личность бота | Высокая | < 10 KB |
| `config/USER.md` | Профиль клиента | Высокая | < 10 KB |
| `config/openclaw.json` | Конфигурация навыков | Высокая | < 50 KB |
| `data/gateway.db` | База данных диалогов | Высокая | 10-500 MB |
| `data/memory/` | Контекстная память (QMD) | Высокая | 1-100 MB |
| `data/leads/` | База лидов | Средняя | < 10 MB |
| `logs/` | Журналы работы | Низкая | 10-500 MB |

### Что НЕ нужно бэкапить

- `node_modules/` -- восстанавливается через `pnpm install`
- Исходный код -- восстанавливается через `git clone`
- Системные пакеты -- переустанавливаются по инструкции

---

### Автоматическое резервное копирование

#### Скрипт бэкапа

Создайте файл `~/kent-overlay/scripts/backup.sh`:

```bash
#!/bin/bash
set -euo pipefail

BACKUP_DIR="/home/kent/backups"
DATE=$(date +%Y-%m-%d_%H-%M)
BACKUP_NAME="kent-backup-${DATE}"
KENT_DIR="/home/kent/kent-overlay"

mkdir -p "${BACKUP_DIR}"

# Создаем архив критических данных
tar czf "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" \
    -C "${KENT_DIR}" \
    .env \
    config/ \
    data/ \
    2>/dev/null

# Удаляем бэкапы старше 30 дней
find "${BACKUP_DIR}" -name "kent-backup-*.tar.gz" -mtime +30 -delete

echo "[$(date)] Backup created: ${BACKUP_NAME}.tar.gz ($(du -sh "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" | cut -f1))"
```

```bash
chmod +x ~/kent-overlay/scripts/backup.sh
```

#### Расписание бэкапа (cron)

```bash
crontab -e
```

Добавьте:

```
# Ежедневный бэкап в 3:00
0 3 * * * /home/kent/kent-overlay/scripts/backup.sh >> /home/kent/kent-overlay/logs/backup.log 2>&1
```

#### Копирование бэкапа на удаленный сервер (опционально)

Добавьте в скрипт бэкапа:

```bash
# Копируем последний бэкап на удаленный сервер
scp "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" backup-user@backup-server:/backups/kent/
```

Или используйте rclone для облачных хранилищ:

```bash
# Копируем в S3-совместимое хранилище
rclone copy "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" remote:kent-backups/
```

---

## Восстановление из бэкапа

### Полное восстановление на том же сервере

**Время восстановления: ~10-15 минут**

```bash
# 1. Остановите Kent
sudo systemctl stop kent-gateway

# 2. Определите последний бэкап
ls -la ~/backups/kent-backup-*.tar.gz | tail -5

# 3. Восстановите данные
BACKUP_FILE="kent-backup-2026-04-10_03-00.tar.gz"  # укажите нужный
cd ~/kent-overlay

# 4. Сохраните текущие данные (на случай если бэкап некорректен)
mv data data.old
mv config config.old
mv .env .env.old

# 5. Распакуйте бэкап
tar xzf ~/backups/${BACKUP_FILE}

# 6. Установите зависимости (если нужно)
pnpm install

# 7. Запустите Kent
sudo systemctl start kent-gateway

# 8. Проверьте работоспособность
journalctl -u kent-gateway -n 20

# 9. Отправьте тестовое сообщение боту

# 10. Если все работает, удалите старые данные
rm -rf data.old config.old .env.old
```

### Восстановление на новом сервере

**Время восстановления: ~30-45 минут**

```bash
# 1. Выполните шаги 1-5 из DEPLOYMENT.md (пользователь, Node.js, pnpm, Python)

# 2. Клонируйте репозиторий
cd ~
git clone git@github.com:YOUR_ORG/kent-overlay.git
cd kent-overlay

# 3. Скопируйте бэкап на новый сервер (с локальной машины или старого сервера)
scp kent@OLD_SERVER:/home/kent/backups/kent-backup-LATEST.tar.gz ~/

# 4. Распакуйте бэкап
tar xzf ~/kent-backup-LATEST.tar.gz -C ~/kent-overlay/

# 5. Установите зависимости
pnpm install
pip3 install --user faster-whisper python-pptx PyPDF2 Pillow

# 6. Настройте systemd
# (скопируйте unit-файл из DEPLOYMENT.md шаг 12)

# 7. Запустите
sudo systemctl enable kent-gateway
sudo systemctl start kent-gateway

# 8. Проверьте
journalctl -u kent-gateway -f
```

> **Важно:** При миграции на новый сервер старый сервер должен быть остановлен до запуска нового. Два экземпляра с одним токеном Telegram вызовут конфликт 409.

---

## RTO и RPO

### RTO (Recovery Time Objective) -- Время восстановления

| Сценарий | RTO |
|----------|-----|
| Перезапуск сервиса (сбой процесса) | ~1 минута (автоматически через systemd) |
| Восстановление из бэкапа (тот же сервер) | ~10-15 минут |
| Восстановление на новом сервере | ~30-45 минут |
| Чистая установка с нуля | ~60-90 минут |

### RPO (Recovery Point Objective) -- Потеря данных

| Расписание бэкапа | Максимальная потеря данных |
|-------------------|--------------------------|
| Каждый час | До 1 часа диалогов |
| Ежедневно (рекомендуется) | До 24 часов диалогов |
| Еженедельно | До 7 дней диалогов |

---

## Что теряется без бэкапа

Если бэкапа нет и сервер утерян:

| Данные | Можно восстановить? | Как |
|--------|---------------------|-----|
| Код kent-overlay | Да | `git clone` из репозитория |
| `.env` (токены) | Частично | Перегенерировать токены вручную |
| `SOUL.md`, `USER.md` | Нет | Писать заново |
| `openclaw.json` | Частично | Использовать шаблон + настроить |
| `gateway.db` (диалоги) | Нет | Потеряны навсегда |
| Память (QMD) | Нет | Будет накоплена заново со временем |
| Лиды | Нет | Потеряны навсегда |

> **Вывод:** Без бэкапа вы теряете всю историю общения, накопленный контекст и базу лидов. Код и конфигурацию можно восстановить, но на это уйдет время.

---

## Сценарии частичного восстановления

### Сценарий 1: Поврежден только gateway.db

```bash
# Попытка восстановить SQLite базу
cd ~/kent-overlay/data

# Вариант A: встроенное восстановление SQLite
sqlite3 gateway.db ".recover" | sqlite3 gateway_new.db
mv gateway.db gateway.db.corrupt
mv gateway_new.db gateway.db

# Вариант B: восстановление из бэкапа только базы
tar xzf ~/backups/kent-backup-LATEST.tar.gz data/gateway.db

# Перезапуск
sudo systemctl restart kent-gateway
```

### Сценарий 2: Утерян только .env

```bash
# Вариант A: восстановить из бэкапа
tar xzf ~/backups/kent-backup-LATEST.tar.gz .env

# Вариант B: создать заново
cd ~/kent-overlay
./configure.sh

# Вам понадобятся:
# - Токен бота (из @BotFather -> /mybots -> API Token)
# - API-ключ Codex (из панели управления)
# - Остальные токены (из соответствующих сервисов)
```

### Сценарий 3: Поврежден индекс памяти

```bash
# Пересборка индекса из существующих данных
cd ~/kent-overlay
node scripts/rebuild-memory-index.js

# Перезапуск
sudo systemctl restart kent-gateway
```

### Сценарий 4: Сервер недоступен, но диск цел

Если сервер не загружается, но диск можно подключить к другому серверу:

1. Подключите диск к новому серверу.
2. Смонтируйте:
   ```bash
   sudo mount /dev/sdX1 /mnt/old-disk
   ```
3. Скопируйте данные Kent:
   ```bash
   cp -r /mnt/old-disk/home/kent/kent-overlay/data ~/kent-overlay/
   cp /mnt/old-disk/home/kent/kent-overlay/.env ~/kent-overlay/
   cp -r /mnt/old-disk/home/kent/kent-overlay/config ~/kent-overlay/
   ```
4. Продолжите с шага "Восстановление на новом сервере".

---

## Чистая переустановка

Когда нужно начать с нуля (нет бэкапа, критический сбой):

```bash
# 1. Удалите старую установку (если есть)
sudo systemctl stop kent-gateway
sudo systemctl disable kent-gateway
rm -rf ~/kent-overlay

# 2. Клонируйте репозиторий
cd ~
git clone git@github.com:YOUR_ORG/kent-overlay.git
cd kent-overlay

# 3. Запустите полную настройку
./configure.sh
./deploy.sh

# 4. Сопрягите бота через Control UI
ssh -L 18789:localhost:18789 kent@SERVER_IP
# Откройте http://localhost:18789

# 5. Отправьте /start боту
```

После чистой переустановки:
- История диалогов будет пустой.
- Память (контекст) начнет накапливаться заново.
- Лиды потеряны -- нужно вводить заново.
- SOUL.md и USER.md нужно настроить заново.

---

## Миграция между серверами

### Плановая миграция (без простоя)

1. **Подготовьте новый сервер** (DEPLOYMENT.md, шаги 1-5).
2. **Создайте свежий бэкап на старом сервере:**
   ```bash
   ~/kent-overlay/scripts/backup.sh
   ```
3. **Скопируйте бэкап на новый сервер:**
   ```bash
   scp ~/backups/kent-backup-LATEST.tar.gz kent@NEW_SERVER:~/
   ```
4. **На новом сервере разверните Kent:**
   ```bash
   cd ~
   git clone git@github.com:YOUR_ORG/kent-overlay.git
   cd kent-overlay
   tar xzf ~/kent-backup-LATEST.tar.gz
   pnpm install
   pip3 install --user faster-whisper python-pptx PyPDF2 Pillow
   ```
5. **Остановите Kent на старом сервере:**
   ```bash
   sudo systemctl stop kent-gateway
   ```
6. **Запустите Kent на новом сервере:**
   ```bash
   sudo systemctl enable kent-gateway
   sudo systemctl start kent-gateway
   ```
7. **Проверьте работоспособность.**
8. **Обновите SSH-туннели и мониторинг на новый IP.**

Простой: ~2-5 минут (между остановкой и запуском).

### Экстренная миграция

Если старый сервер уже недоступен:

1. Найдите последний бэкап (удаленное хранилище, локальная копия).
2. Разверните на новый сервер по инструкции "Восстановление на новом сервере".
3. Если бэкапа нет -- чистая переустановка.

---

## Чек-лист: готовность к сбоям

Проверяйте ежемесячно:

- [ ] Бэкапы создаются ежедневно (проверьте `ls ~/backups/`)
- [ ] Бэкапы копируются на удаленное хранилище
- [ ] Последний бэкап не старше 24 часов
- [ ] Размер бэкапа адекватный (растет, но не аномально)
- [ ] Тестовое восстановление проведено хотя бы раз
- [ ] `.env` сохранен в безопасном месте (менеджер паролей)
- [ ] Документирован процесс восстановления для этого клиента
- [ ] Healthcheck cron работает
- [ ] Свободного места на диске > 20%
