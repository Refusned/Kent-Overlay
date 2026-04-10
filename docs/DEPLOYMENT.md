# Руководство по развертыванию Kent

Пошаговая инструкция для оператора по установке и запуску Kent AI Assistant на выделенном сервере.

---

## Требования к серверу

| Параметр | Минимум |
|----------|---------|
| ОС | Ubuntu 24.04 LTS |
| RAM | 4 GB |
| CPU | 2 vCPU |
| Диск | 40 GB SSD |
| Сеть | Статический IP, открытый порт 22 (SSH) |

Дополнительно:
- Доменное имя не требуется (бот работает через Telegram API).
- IPv4 адрес обязателен (Telegram API не работает по IPv6 на некоторых провайдерах).
- Рекомендуемые хостинги: Hetzner, Timeweb Cloud, Selectel, DigitalOcean.

---

## Шаг 1. Создание пользователя и настройка SSH

### 1.1. Подключитесь к серверу как root

```bash
ssh root@YOUR_SERVER_IP
```

### 1.2. Создайте пользователя kent

```bash
adduser kent
usermod -aG sudo kent
```

### 1.3. Настройте SSH-ключ для пользователя kent

На вашей **локальной машине**:

```bash
ssh-copy-id kent@YOUR_SERVER_IP
```

Если ключа еще нет:

```bash
ssh-keygen -t ed25519 -C "kent-server"
ssh-copy-id kent@YOUR_SERVER_IP
```

### 1.4. Отключите вход по паролю (рекомендуется)

На сервере от root:

```bash
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd
```

### 1.5. Проверьте вход

```bash
ssh kent@YOUR_SERVER_IP
```

---

## Шаг 2. Установка Node.js 24

### Вариант A: через nodesource (рекомендуется для продакшена)

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt-get install -y nodejs
```

### Вариант B: через nvm (для разработки)

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
source ~/.bashrc
nvm install 24
nvm use 24
nvm alias default 24
```

### Проверка

```bash
node --version   # v24.x.x
npm --version    # 10.x.x или выше
```

---

## Шаг 3. Установка pnpm

```bash
npm i -g pnpm
```

Проверка:

```bash
pnpm --version   # 10.x.x
```

---

## Шаг 4. Установка Python 3 и pip3

Python необходим для навыков STT (faster-whisper), генерации PPTX, обработки PDF и других.

```bash
sudo apt-get install -y python3 python3-pip python3-venv
```

Установите зависимости Python для навыков Kent:

```bash
pip3 install --user faster-whisper python-pptx PyPDF2 Pillow
```

Проверка:

```bash
python3 --version   # Python 3.12+
pip3 --version
```

---

## Шаг 5. Установка Docker (опционально)

Docker нужен только если вы планируете использовать docker-compose для управления сервисом.

```bash
sudo apt-get install -y docker.io docker-compose-v2
sudo usermod -aG docker kent
newgrp docker
```

Проверка:

```bash
docker --version
docker compose version
```

---

## Шаг 6. Клонирование репозитория kent-overlay

```bash
cd ~
git clone https://github.com/YOUR_ORG/kent-overlay.git
cd kent-overlay
```

Если репозиторий приватный, настройте SSH-ключ для GitHub:

```bash
ssh-keygen -t ed25519 -C "kent-deploy"
cat ~/.ssh/id_ed25519.pub
# Добавьте ключ в GitHub -> Settings -> SSH Keys
```

Затем клонируйте по SSH:

```bash
git clone git@github.com:YOUR_ORG/kent-overlay.git
```

---

## Шаг 7. Запуск configure.sh

Скрипт `configure.sh` создает файл `.env`, настраивает структуру каталогов и подготавливает конфигурацию.

```bash
cd ~/kent-overlay
chmod +x configure.sh
./configure.sh
```

Скрипт запросит:
- Токен Telegram-бота (из @BotFather)
- API-ключи для сервисов (Codex, ChatGPT, ElevenLabs и др.)
- Имя клиента и параметры персонализации
- Путь к данным

> **Важно:** Не пропускайте ни одного обязательного параметра. Скрипт подскажет, какие поля обязательны.

---

## Шаг 8. Запуск deploy.sh

```bash
chmod +x deploy.sh
./deploy.sh
```

Скрипт выполнит:
1. Установку зависимостей (`pnpm install`)
2. Сборку проекта
3. Инициализацию базы данных gateway.db
4. Первичный запуск и проверку работоспособности
5. Настройку автозапуска

Дождитесь сообщения `Kent is ready` в терминале.

---

## Шаг 9. Настройка SSH-туннеля для Control UI

Control UI работает на localhost:18789 и **не должен** быть доступен из интернета напрямую. Используйте SSH-туннель.

### На вашей локальной машине:

```bash
ssh -L 18789:localhost:18789 kent@YOUR_SERVER_IP
```

После этого откройте в браузере:

```
http://localhost:18789
```

### Для постоянного туннеля (macOS / Linux):

Добавьте в `~/.ssh/config`:

```
Host kent-server
    HostName YOUR_SERVER_IP
    User kent
    LocalForward 18789 localhost:18789
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

Затем просто:

```bash
ssh kent-server
```

---

## Шаг 10. Сопряжение с Telegram-ботом

1. Откройте Control UI в браузере (http://localhost:18789).
2. Перейдите в раздел **Telegram Pairing**.
3. Введите токен бота из @BotFather.
4. Нажмите **Pair**.
5. Отправьте боту в Telegram сообщение `/start`.
6. Убедитесь, что бот ответил приветствием.

### Проверка через терминал:

```bash
# Посмотрите логи gateway
journalctl -u kent-gateway -f --no-pager
```

Вы должны увидеть:
```
Telegram bot connected
Polling started
```

---

## Шаг 11. Настройка мониторинга (cron)

Создайте скрипт проверки здоровья:

```bash
cat > ~/kent-overlay/healthcheck.sh << 'SCRIPT'
#!/bin/bash
if ! pgrep -f "kent-gateway" > /dev/null; then
    echo "[$(date)] Kent gateway is down, restarting..." >> ~/kent-overlay/logs/healthcheck.log
    cd ~/kent-overlay && ./deploy.sh restart
fi
SCRIPT
chmod +x ~/kent-overlay/healthcheck.sh
```

Добавьте в crontab:

```bash
crontab -e
```

Добавьте строку:

```
*/5 * * * * /home/kent/kent-overlay/healthcheck.sh
```

Это будет проверять и перезапускать Kent каждые 5 минут, если он упал.

### Дополнительный мониторинг: ротация логов

```bash
cat > /etc/logrotate.d/kent << 'LOGROTATE'
/home/kent/kent-overlay/logs/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 kent kent
}
LOGROTATE
```

---

## Шаг 12. Настройка systemd-сервиса

### Вариант A: systemd (рекомендуется)

```bash
sudo cat > /etc/systemd/system/kent-gateway.service << 'SERVICE'
[Unit]
Description=Kent AI Assistant Gateway
After=network.target

[Service]
Type=simple
User=kent
Group=kent
WorkingDirectory=/home/kent/kent-overlay
ExecStart=/usr/bin/node gateway/index.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production

# Логирование
StandardOutput=journal
StandardError=journal
SyslogIdentifier=kent-gateway

# Безопасность
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable kent-gateway
sudo systemctl start kent-gateway
```

Управление сервисом:

```bash
sudo systemctl status kent-gateway    # Статус
sudo systemctl restart kent-gateway   # Перезапуск
sudo systemctl stop kent-gateway      # Остановка
journalctl -u kent-gateway -f         # Логи в реальном времени
```

### Вариант B: docker-compose

```yaml
# docker-compose.yml
version: '3.8'
services:
  kent-gateway:
    build: .
    container_name: kent-gateway
    restart: always
    env_file: .env
    volumes:
      - ./data:/app/data
      - ./logs:/app/logs
    ports:
      - "127.0.0.1:18789:18789"
```

```bash
docker compose up -d
docker compose logs -f
```

---

## Чек-лист после развертывания

Убедитесь, что все пункты выполнены:

- [ ] Пользователь `kent` создан, SSH-ключ настроен
- [ ] Node.js 24 установлен и работает
- [ ] pnpm установлен глобально
- [ ] Python 3 и pip3 установлены
- [ ] Репозиторий kent-overlay клонирован
- [ ] `configure.sh` выполнен, `.env` создан
- [ ] `deploy.sh` выполнен без ошибок
- [ ] SSH-туннель для Control UI работает (localhost:18789)
- [ ] Telegram-бот сопряжен и отвечает на `/start`
- [ ] Healthcheck cron настроен (каждые 5 минут)
- [ ] systemd-сервис включен и запущен
- [ ] Логи пишутся и ротируются
- [ ] Отправлено тестовое текстовое сообщение боту
- [ ] Отправлено тестовое голосовое сообщение боту
- [ ] Проверена работа команды `/help`

---

## Быстрый деплой (TL;DR)

Для опытных операторов - все команды одним блоком:

```bash
# На сервере от root
adduser kent && usermod -aG sudo kent

# Далее от kent
sudo apt-get update && sudo apt-get install -y ca-certificates curl gnupg python3 python3-pip python3-venv
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt-get install -y nodejs
npm i -g pnpm
pip3 install --user faster-whisper python-pptx PyPDF2 Pillow

cd ~ && git clone git@github.com:YOUR_ORG/kent-overlay.git
cd kent-overlay
chmod +x configure.sh deploy.sh
./configure.sh
./deploy.sh
```

На локальной машине:

```bash
ssh -L 18789:localhost:18789 kent@YOUR_SERVER_IP
# Откройте http://localhost:18789 и сопрягите бота
```
