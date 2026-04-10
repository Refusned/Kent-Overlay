# Устранение неполадок Kent

Справочник типичных проблем и их решений.

---

## Содержание

1. [Gateway не запускается](#1-gateway-не-запускается)
2. [Telegram отключается](#2-telegram-отключается)
3. [Голосовые сообщения не работают](#3-голосовые-сообщения-не-работают)
4. [Изображения не генерируются](#4-изображения-не-генерируются)
5. [Умный дом не отвечает](#5-умный-дом-не-отвечает)
6. [Поиск по памяти возвращает пустоту](#6-поиск-по-памяти-возвращает-пустоту)
7. [Высокое потребление памяти](#7-высокое-потребление-памяти)
8. [Навыки не загружаются](#8-навыки-не-загружаются)
9. [Cron-задачи не выполняются](#9-cron-задачи-не-выполняются)
10. [Ошибки Permission Denied](#10-ошибки-permission-denied)

---

## 1. Gateway не запускается

### Проблема: SingletonLock

**Симптом:** Ошибка `Error: Could not acquire SingletonLock` или `EEXIST: file already exists`.

**Причина:** Предыдущий процесс gateway не завершился корректно и оставил lock-файл.

**Решение:**

```bash
# Найдите и удалите lock-файл
find ~/kent-overlay -name "SingletonLock" -delete
find ~/kent-overlay -name "*.lock" -delete

# Убейте зависший процесс, если есть
pkill -f "kent-gateway" || true

# Запустите заново
sudo systemctl restart kent-gateway
```

**Предотвращение:** Используйте systemd с `Restart=always` -- он корректно обрабатывает завершение процесса.

---

### Проблема: Порт уже занят

**Симптом:** Ошибка `EADDRINUSE: address already in use :::18789`.

**Причина:** Другой процесс занимает порт 18789 (Control UI) или порт gateway.

**Решение:**

```bash
# Найдите процесс, занимающий порт
sudo lsof -i :18789

# Завершите его
sudo kill -9 <PID>

# Или найдите все процессы Kent
ps aux | grep kent
sudo kill -9 <PID>

# Перезапустите
sudo systemctl restart kent-gateway
```

**Предотвращение:** Не запускайте несколько экземпляров Kent вручную. Используйте только systemd.

---

### Проблема: Отсутствует .env

**Симптом:** Ошибка `Error: Missing required environment variable` или `ENOENT: .env not found`.

**Причина:** Файл `.env` не существует или не содержит обязательных переменных.

**Решение:**

```bash
# Проверьте наличие файла
ls -la ~/kent-overlay/.env

# Если отсутствует, запустите конфигуратор
cd ~/kent-overlay && ./configure.sh

# Если файл есть, проверьте обязательные переменные
grep -E "TELEGRAM_BOT_TOKEN|CODEX_API_KEY" ~/kent-overlay/.env
```

**Обязательные переменные:**
- `TELEGRAM_BOT_TOKEN`
- `CODEX_API_KEY`
- `TELEGRAM_ADMIN_ID`

**Предотвращение:** Всегда делайте резервную копию `.env` перед обновлениями.

---

### Проблема: Неверная версия Node.js

**Симптом:** Ошибка `SyntaxError: Unexpected token` или `Cannot use import statement outside a module`.

**Причина:** Установлена старая версия Node.js.

**Решение:**

```bash
node --version  # Должно быть v24.x.x

# Обновите Node.js
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt-get install -y nodejs
```

**Предотвращение:** Зафиксируйте версию Node.js при установке. Не используйте системный Node.js без проверки версии.

---

## 2. Telegram отключается

### Проблема: Rate Limits

**Симптом:** Ошибка `429 Too Many Requests. Retry after X seconds`. Бот перестает отвечать на время.

**Причина:** Превышены лимиты Telegram Bot API (примерно 30 сообщений/секунду в одном чате, 20 сообщений/минуту в группе).

**Решение:**

```bash
# Проверьте логи
journalctl -u kent-gateway | grep -i "429\|rate.limit\|retry"

# Перезапустите gateway -- он автоматически восстановит соединение
sudo systemctl restart kent-gateway
```

**Предотвращение:**
- Не отправляйте множество сообщений подряд.
- Включите очередь сообщений в конфигурации.
- Используйте `sendMessage` с задержкой для массовых операций.

---

### Проблема: Некорректный токен

**Симптом:** Ошибка `401 Unauthorized` или `Not Found: bot token is invalid`.

**Причина:** Токен бота неверный, истек (после `/revoke`) или бот удален.

**Решение:**

```bash
# Проверьте токен
curl "https://api.telegram.org/bot<YOUR_TOKEN>/getMe"

# Если ответ содержит ошибку, получите новый токен:
# 1. Откройте @BotFather в Telegram
# 2. /mybots -> выберите бота -> API Token
# 3. Обновите .env
nano ~/kent-overlay/.env  # Замените TELEGRAM_BOT_TOKEN

# Перезапустите
sudo systemctl restart kent-gateway
```

**Предотвращение:** Не делайте `/revoke` в BotFather, если не планируете обновлять `.env`.

---

### Проблема: Конфликт экземпляров (409 Conflict)

**Симптом:** Ошибка `409 Conflict: terminated by other getUpdates request`.

**Причина:** Два процесса используют один и тот же токен бота (например, тестовый и продакшен).

**Решение:**

```bash
# Остановите все процессы Kent
sudo systemctl stop kent-gateway
pkill -f "kent-gateway" || true

# Подождите 5 секунд
sleep 5

# Запустите один экземпляр
sudo systemctl start kent-gateway
```

**Предотвращение:** Используйте уникальный токен для каждого сервера. Не запускайте бота локально с продакшен-токеном.

---

## 3. Голосовые сообщения не работают

### Проблема: faster-whisper не установлен

**Симптом:** Ошибка `ModuleNotFoundError: No module named 'faster_whisper'` или голосовое сообщение игнорируется.

**Причина:** Библиотека faster-whisper не установлена или установлена для другого пользователя.

**Решение:**

```bash
# Установите faster-whisper
pip3 install --user faster-whisper

# Проверьте установку
python3 -c "import faster_whisper; print('OK')"

# Если ошибка "command not found: pip3"
sudo apt-get install python3-pip
pip3 install --user faster-whisper
```

**Предотвращение:** Включите установку faster-whisper в скрипт деплоя.

---

### Проблема: Модель не скачана

**Симптом:** Ошибка `FileNotFoundError` или очень долгая обработка первого голосового сообщения (модель скачивается на лету).

**Причина:** Модель Whisper не была скачана заранее.

**Решение:**

```bash
# Скачайте модель вручную
python3 -c "from faster_whisper import WhisperModel; m = WhisperModel('base'); print('Model downloaded')"

# Для модели small (лучше качество, больше RAM)
python3 -c "from faster_whisper import WhisperModel; m = WhisperModel('small'); print('Model downloaded')"
```

**Предотвращение:** Скачивайте модель сразу после установки faster-whisper, до запуска gateway.

---

### Проблема: Некорректный формат аудио

**Симптом:** Ошибка `ValueError: Audio format not supported` или пустая транскрипция.

**Причина:** Telegram отправляет голосовые в формате OGG/OPUS. Иногда конвертация сбоит.

**Решение:**

```bash
# Установите ffmpeg (для конвертации аудио)
sudo apt-get install -y ffmpeg

# Проверьте
ffmpeg -version
```

**Предотвращение:** Установите ffmpeg при первоначальном деплое.

---

## 4. Изображения не генерируются

### Проблема: ChatGPT Session Token истек

**Симптом:** Ошибка `403 Forbidden` или `Authentication required` при генерации изображений.

**Причина:** Session token ChatGPT истекает каждые 1-2 недели.

**Решение:**

1. Откройте https://chat.openai.com/ в браузере.
2. Войдите в аккаунт.
3. Откройте DevTools (F12) -> Application -> Cookies.
4. Найдите `__Secure-next-auth.session-token`.
5. Скопируйте значение.
6. Обновите `.env`:
   ```bash
   nano ~/kent-overlay/.env
   # Замените CHATGPT_SESSION_TOKEN
   ```
7. Перезапустите:
   ```bash
   sudo systemctl restart kent-gateway
   ```

**Предотвращение:** Установите напоминание на обновление токена каждые 7 дней.

---

### Проблема: Подписка ChatGPT неактивна

**Симптом:** Ошибка `402 Payment Required` или лимит генерации достигнут.

**Причина:** Подписка ChatGPT Plus истекла или достигнут лимит DALL-E.

**Решение:**
- Проверьте статус подписки на https://chat.openai.com/
- Продлите подписку при необходимости.
- Подождите сброса лимитов (обычно раз в 3 часа).

---

## 5. Умный дом не отвечает

### Проблема: Yandex-токен истек

**Симптом:** Ошибка `401 Unauthorized` при обращении к устройствам умного дома.

**Причина:** OAuth-токен Яндекс истек.

**Решение:**

1. Перейдите на https://oauth.yandex.ru/
2. Повторно авторизуйтесь.
3. Скопируйте новый токен.
4. Обновите `.env`:
   ```env
   YANDEX_TOKEN=новый_токен
   ```
5. Перезапустите gateway.

**Предотвращение:** Яндекс-токены обычно живут долго (до 1 года), но установите напоминание на проверку.

---

### Проблема: Устройство офлайн

**Симптом:** Kent отвечает "Устройство не отвечает" или "Устройство не найдено".

**Причина:** Устройство отключено, нет Wi-Fi, или сменился аккаунт Яндекс.

**Решение:**
1. Проверьте устройство в приложении "Яндекс -- с Алисой".
2. Убедитесь, что устройство онлайн.
3. Попробуйте управлять им из приложения напрямую.
4. Если работает из приложения, но не из Kent -- перезапустите gateway.

---

## 6. Поиск по памяти возвращает пустоту

### Проблема: QMD не прогрелся

**Симптом:** Kent не помнит предыдущие разговоры, `/memory` показывает пустой результат.

**Причина:** Индекс памяти (QMD) еще не инициализирован или поврежден.

**Решение:**

```bash
# Проверьте, существуют ли файлы памяти
ls -la ~/kent-overlay/data/memory/

# Если каталог пуст, память еще не накоплена -- это нормально для нового деплоя

# Если файлы есть, но поиск пустой, пересоберите индекс
cd ~/kent-overlay
node scripts/rebuild-memory-index.js
```

**Предотвращение:** Индекс памяти автоматически обновляется при каждом сообщении. Проблемы возникают только после сбоя или неполного восстановления из бэкапа.

---

### Проблема: Поврежденный gateway.db

**Симптом:** Ошибки `SQLITE_CORRUPT` или `database disk image is malformed`.

**Причина:** Неожиданное отключение питания, переполнение диска.

**Решение:**

```bash
# Попытка восстановления
cd ~/kent-overlay/data
sqlite3 gateway.db ".recover" | sqlite3 gateway_recovered.db

# Если успешно, замените базу
mv gateway.db gateway.db.broken
mv gateway_recovered.db gateway.db

# Перезапустите
sudo systemctl restart kent-gateway
```

Если восстановление не помогло, см. [DISASTER-RECOVERY.md](DISASTER-RECOVERY.md).

---

## 7. Высокое потребление памяти

### Проблема: Утечка памяти / раздувание heap

**Симптом:** Процесс Node.js потребляет больше 2 GB RAM. Сервер начинает свопить.

**Причина:** Длинные сессии без перезапуска, большие файлы в обработке, утечки памяти.

**Решение:**

```bash
# Проверьте потребление
ps aux | grep kent-gateway | grep -v grep

# Текущее использование RAM
free -h

# Перезапустите gateway (сбросит память)
sudo systemctl restart kent-gateway
```

**Настройка ограничения памяти:**

Добавьте в systemd-сервис:

```ini
[Service]
MemoryMax=2G
MemorySwapMax=0
```

```bash
sudo systemctl daemon-reload
sudo systemctl restart kent-gateway
```

**Предотвращение:**
- Настройте автоматический перезапуск раз в сутки через cron:
  ```
  0 4 * * * sudo systemctl restart kent-gateway
  ```
- Уменьшите размер модели STT (используйте `base` вместо `small`).

---

### Проблема: Логи занимают много места

**Симптом:** Диск переполнен. `df -h` показывает мало свободного места.

**Причина:** Логи не ротируются и растут неограниченно.

**Решение:**

```bash
# Проверьте размер логов
du -sh ~/kent-overlay/logs/

# Очистите старые логи
find ~/kent-overlay/logs/ -name "*.log" -mtime +7 -delete

# Настройте ротацию (logrotate)
sudo cat > /etc/logrotate.d/kent << 'EOF'
/home/kent/kent-overlay/logs/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 0640 kent kent
    postrotate
        systemctl reload kent-gateway 2>/dev/null || true
    endscript
}
EOF
```

Для journald:

```bash
# Ограничить размер журнала systemd
sudo journalctl --vacuum-size=500M
```

---

## 8. Навыки не загружаются

### Проблема: pnpm зависимости

**Симптом:** Ошибка `MODULE_NOT_FOUND` или `Cannot find module`.

**Причина:** Зависимости не установлены или повреждены.

**Решение:**

```bash
cd ~/kent-overlay

# Удалите node_modules и переустановите
rm -rf node_modules
pnpm install

# Перезапустите
sudo systemctl restart kent-gateway
```

**Предотвращение:** Всегда запускайте `pnpm install` после `git pull`.

---

### Проблема: Некорректный openclaw.json

**Симптом:** Ошибка `SyntaxError: Unexpected token` при загрузке конфигурации.

**Причина:** Ошибка синтаксиса JSON в файле конфигурации.

**Решение:**

```bash
# Проверьте валидность JSON
python3 -m json.tool ~/kent-overlay/config/openclaw.json

# Если ошибка, исправьте файл
nano ~/kent-overlay/config/openclaw.json
```

Частые ошибки:
- Запятая после последнего элемента в массиве/объекте.
- Незакрытые кавычки.
- Незакрытые скобки.

---

### Проблема: Навык не поддерживает текущую версию

**Симптом:** Ошибка `Skill version mismatch` или навык молча не работает.

**Причина:** После обновления kent-overlay навык стал несовместим.

**Решение:**

```bash
# Обновите все зависимости
cd ~/kent-overlay
git pull origin main
pnpm install
sudo systemctl restart kent-gateway
```

---

### Проблема: Инструменты заблокированы whitelist-ом (tools.allow)

**Симптом:** Несколько инструментов не работают одновременно: погода даёт только ссылку, изображения не генерируются, презентации зависают, файлы не записываются. При этом браузер работает нормально.

**Причина:** В `config/openclaw.json` параметр `tools.allow` установлен как массив (например, `["browser"]`). Когда `tools.allow` — непустой массив, ТОЛЬКО перечисленные инструменты доступны агенту. Все остальные (exec, write, weather, image и т.д.) блокируются.

**Решение:**

1. Удалите строку `"allow": [...]` из секции `tools` в `config/openclaw.json`
2. Используйте `tools.deny` для блокировки ненужных инструментов
3. Перезапустите gateway: `sudo systemctl restart kent-gateway`

**Предотвращение:** Не добавляйте `tools.allow` в конфигурацию — используйте `tools.deny` для ограничений. Deny-подход позволяет новым инструментам и навыкам работать сразу после установки.

---

## 9. Cron-задачи не выполняются

### Проблема: Неверный часовой пояс

**Симптом:** Задачи выполняются не в то время (со сдвигом на несколько часов).

**Причина:** Часовой пояс сервера не совпадает с часовым поясом клиента.

**Решение:**

```bash
# Проверьте текущий часовой пояс
timedatectl

# Установите нужный часовой пояс
sudo timedatectl set-timezone Europe/Moscow

# Перезапустите cron
sudo systemctl restart cron
```

**Предотвращение:** Устанавливайте часовой пояс при деплое. Убедитесь, что `TIMEZONE` в `.env` совпадает с системным.

---

### Проблема: Cron daemon не запущен

**Симптом:** Ни одна cron-задача не выполняется. `crontab -l` показывает задачи, но они не запускаются.

**Причина:** Служба cron остановлена.

**Решение:**

```bash
# Проверьте статус
sudo systemctl status cron

# Если остановлен, запустите
sudo systemctl enable cron
sudo systemctl start cron

# Проверьте, что задачи зарегистрированы
crontab -l
```

---

### Проблема: Скрипт не имеет прав на выполнение

**Симптом:** В `/var/log/syslog` видно `permission denied` для cron-скрипта.

**Причина:** Скрипт healthcheck.sh не имеет флага executable.

**Решение:**

```bash
chmod +x ~/kent-overlay/healthcheck.sh
```

---

## 10. Ошибки Permission Denied

### Проблема: Нет доступа к файлам данных

**Симптом:** Ошибка `EACCES: permission denied` при записи в `data/` или `logs/`.

**Причина:** Файлы/каталоги принадлежат другому пользователю (например, root).

**Решение:**

```bash
# Проверьте владельца
ls -la ~/kent-overlay/data/
ls -la ~/kent-overlay/logs/

# Исправьте владельца
sudo chown -R kent:kent ~/kent-overlay/data/
sudo chown -R kent:kent ~/kent-overlay/logs/

# Установите правильные права
chmod -R 755 ~/kent-overlay/data/
chmod -R 755 ~/kent-overlay/logs/
```

**Предотвращение:** Не запускайте Kent от root. Всегда используйте пользователя `kent`.

---

### Проблема: Нет доступа к .env

**Симптом:** Ошибка `EACCES: permission denied, open '.env'`.

**Причина:** Неправильные права на файл `.env`.

**Решение:**

```bash
sudo chown kent:kent ~/kent-overlay/.env
chmod 600 ~/kent-overlay/.env  # Только владелец может читать/писать
```

---

### Проблема: pip устанавливает в недоступное место

**Симптом:** Python-модули установлены, но Kent не может их найти.

**Причина:** Модули установлены для другого пользователя или в системный каталог без прав.

**Решение:**

```bash
# Установите от пользователя kent
sudo -u kent pip3 install --user faster-whisper python-pptx PyPDF2

# Проверьте PATH
echo $PATH
# Должен содержать /home/kent/.local/bin
```

Добавьте в `~/.bashrc` пользователя kent:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

---

## Диагностика: полезные команды

### Просмотр логов

```bash
# Логи gateway в реальном времени
journalctl -u kent-gateway -f

# Последние 100 строк
journalctl -u kent-gateway -n 100

# Логи за последний час
journalctl -u kent-gateway --since "1 hour ago"

# Только ошибки
journalctl -u kent-gateway -p err
```

### Состояние системы

```bash
# Использование RAM и CPU
htop

# Использование диска
df -h

# Размер каталогов Kent
du -sh ~/kent-overlay/*/

# Сетевые соединения
ss -tlnp | grep node
```

### Проверка конфигурации

```bash
# Валидность .env
cat ~/kent-overlay/.env | grep -v "^#" | grep -v "^$"

# Валидность JSON
python3 -m json.tool ~/kent-overlay/config/openclaw.json > /dev/null && echo "OK"

# Версии ПО
node --version
pnpm --version
python3 --version
pip3 list | grep -E "faster-whisper|python-pptx|PyPDF2"
```

---

## Когда обращаться за помощью

Если проблема не решается по этому руководству:

1. Соберите диагностику:
   ```bash
   journalctl -u kent-gateway -n 200 > /tmp/kent-logs.txt
   cat ~/kent-overlay/.env | sed 's/=.*/=***/' > /tmp/kent-env-masked.txt
   uname -a > /tmp/kent-system.txt
   node --version >> /tmp/kent-system.txt
   free -h >> /tmp/kent-system.txt
   df -h >> /tmp/kent-system.txt
   ```
2. Отправьте файлы из `/tmp/kent-*.txt` разработчику.
3. Опишите: что делали, что ожидали, что произошло.
