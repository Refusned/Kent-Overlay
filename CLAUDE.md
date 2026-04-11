# Kent Overlay

Kent — персонализированный AI бизнес-ассистент и SMM-менеджер, работающий как overlay (надстройка) над платформой OpenClaw. Доставляется клиенту как Telegram-бот с характером, памятью и навыками. Это не чатбот — это цифровой сотрудник.

Версия: 1.0.0 | Платформа: OpenClaw 2026.4.x | Язык: русский (основной), английский (fallback)

## Структура проекта

```
kent-overlay/
  workspace/           # Рантайм агента: личность, правила, память, скиллы
    SOUL.md            # Характер, тон, ценности (загружается первым)
    SECURITY.md        # Неизменяемые правила безопасности (красные линии)
    AGENTS.md          # Операционное поведение, управление памятью
    BOOT.md            # Онбординг новых пользователей (5 фаз)
    USER.md.template   # Шаблон профиля клиента
    MEMORY.md          # Долгосрочная память
    LEARNED.md         # Выученные паттерны
    skills/            # 17 скиллов (каждый — папка с SKILL.md)
    tools/             # Инструменты (pptx_tool.py)
    content/           # Контент-план и черновики
    smm/               # SMM: стратегии, бренд-буки, аналитика
    kentbytes/         # Библиотека рецептов (6 категорий)
  config/
    openclaw.json      # Единый конфиг OpenClaw (JSON5, ~264 строк)
  docker/
    docker-compose.yml # Продакшн: openclaw + browser контейнеры
    .env.docker.example
  cron/
    jobs.json          # 5 автоматических задач (брифинг, мониторинг, бэкап)
  systemd/
    openclaw.service   # Linux systemd-сервис
  docs/                # 14 файлов документации (~4000 строк)
  deploy.sh            # Основной деплой (20 шагов, идемпотентный)
  install.sh           # Установка одной командой (curl|bash)
  configure.sh         # Интерактивная настройка
  prerequisites.sh     # Проверка зависимостей
  update.sh            # Обновление
  backup.sh            # Бэкап
  monitor.sh           # Мониторинг здоровья
  .env.example         # Шаблон переменных окружения
  VERSION              # Текущая версия
```

## Технологии

- **Платформа:** OpenClaw (контейнеризированная оркестрация агентов)
- **Канал:** Telegram Bot API
- **Деплой:** Docker Compose (openclaw + browser контейнеры)
- **Скрипты:** Bash (deploy, configure, monitor, backup, update)
- **Инструменты:** Python 3 (pptx_tool.py, idea_reality_check.py)
- **Конфиг:** JSON5 (openclaw.json), Markdown (workspace/*.md)
- **Модели:** Codex (OAuth), DeepSeek, Google Gemini Flash, ChatGPT (DALL-E)
- **Инфра:** Ubuntu 24.04 LTS, 4 GB RAM, 2 vCPU, Docker 24+

## 17 скиллов

Каждый скилл — `workspace/skills/<name>/SKILL.md` с метаданными, триггерами и инструкциями.

| Скилл | Назначение |
|-------|-----------|
| lead-capture | Захват и квалификация лидов, мини-CRM |
| content-calendar | Контент-планирование для соцсетей |
| social-drafts | Генерация постов с хэштегами и картинками |
| smm-manager | Полный цикл SMM: стратегия, аналитика, посты |
| coder | Написание и запуск кода (Python/Node/Bash в Docker sandbox) |
| faq-responder | База знаний и ответы на частые вопросы |
| crm-notes | Контакты, история взаимодействий, напоминания |
| broadcast-composer | Массовые рассылки с A/B тестами |
| pptx-manager | Создание и редактирование презентаций PowerPoint |
| email-triage | Управление почтой Gmail (дайджесты, черновики) |
| finance-tracker | Учет доходов/расходов, отчеты, расчет УСН 6% |
| doc-generator | Генерация документов (договоры, КП, акты, счета) |
| humanize | Переписывание AI-текста в естественный стиль |
| alice-smarthome | Управление умным домом через Yandex IoT API |
| idea-reality | Проверка бизнес-идей на существование аналогов |
| youtube-summary | Суммаризация видео YouTube |
| weather-fallback | Прогноз погоды через wttr.in |

## Конфигурация

- **`config/openclaw.json`** — основной конфиг: gateway (порт 18789, loopback), агент, память, инструменты, скиллы, крон, логирование
- **`.env`** — секреты (gitignored): `OPENCLAW_GATEWAY_TOKEN`, `TELEGRAM_BOT_TOKEN`, Google OAuth, Twitter API, ElevenLabs, Yandex OAuth, клиентские данные
- **`cron/jobs.json`** — 5 задач: утренний брифинг, health-check, недельный отчет, SMM-напоминания, ежедневный бэкап

## Деплой

Установка одной командой:
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Refusned/Kent-Overlay/main/install.sh)
```

Ручной деплой: `prerequisites.sh` -> `configure.sh` -> `deploy.sh`

Docker-сервисы:
- **openclaw** — основной контейнер (порт 127.0.0.1:18789, лимит 2 GB RAM)
- **browser** — Chromium для веб-скрейпинга (2 GB SHM, внутренняя сеть)

Health-check: `curl -f http://localhost:18789/healthz`

## Правила разработки

### Запрещено редактировать программно (через скиллы/код):
- `workspace/SECURITY.md` — только оператор вручную
- `config/openclaw.json` — только оператор вручную
- `.env` — только оператор вручную

### Хуки и скиллы
Все 4 бандловых хука OpenClaw (boot-md, bootstrap-extra-files, command-logger, session-memory) и все бандловые скиллы (54 шт. в `skills.allowBundled`) должны быть включены при каждой установке и обновлении. 5-й хук (memory-core-short-term-dreaming-cron) управляется плагином автоматически. Никогда не сокращать список без явной инструкции.

### Безопасность (из SECURITY.md)
- Никогда не отправлять данные пользователя наружу
- Никогда не отправлять email/сообщения без подтверждения
- Корзина вместо удаления (обратимые операции)
- Внешние действия — всегда с подтверждением
- Данные из ЛС не утекают в группы
- Данные одного клиента не попадают к другому
- Умный дом: Tier 1 (статус — без подтверждения), Tier 2 (управление — с подтверждением), Tier 3 (замки/камеры — запрещено)

### Хранилище
Файловое: Markdown + JSON. Без БД в MVP. Данные в Docker volumes. Секреты только в `.env` (gitignored).

### Язык
Весь проект, документация, скиллы и комментарии — на русском. Код и конфиги — на английском.

## Интеграции

Google (Gmail, Calendar, Drive, Sheets, Contacts), Twitter/X, Telegram, ChatGPT/DALL-E, ElevenLabs TTS, faster-whisper STT, Yandex IoT (умный дом), Tavily/Agent Browser (поиск). Подробности: `docs/INTEGRATIONS.md`.

## Git

- Ветка: `main`
- `origin` -> `github.com/Refusned/Kent-Overlay.git` (основной)
- `old-kent` -> `github.com/Refusned/Kent.git` (legacy)

## Полезные файлы

| Файл | Для чего |
|------|----------|
| `workspace/SOUL.md` | Личность и характер бота (432 строки) |
| `workspace/AGENTS.md` | Правила поведения и память (602 строки) |
| `docs/DEPLOYMENT.md` | Гайд по деплою |
| `docs/TROUBLESHOOTING.md` | Решение проблем (740 строк) |
| `docs/INTEGRATIONS.md` | Настройка 28 интеграций |
| `docs/CUSTOMIZATION.md` | Кастомизация под клиента |
| `ПОЛНЫЙ_ПРОЕКТ_KENT.md` (корень) | Полная спецификация проекта |
| `Kent_Tech_Plan.md` (корень) | Три варианта деплоя с экономикой |
