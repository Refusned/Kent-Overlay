# Kent v1.0 — Матрица готовности

> Единственный источник правды о состоянии проекта.
> Последнее обновление: 2026-04-11

## Что умеет Kent v1 (core capabilities)

Платформенные возможности (bundled + ClawHub):

| Возможность | Источник | Статус |
|-------------|----------|--------|
| Telegram DM-чат с личностью и памятью | SOUL.md + AGENTS.md | Работает |
| Telegram группы (@mention) | openclaw.json channels | Работает |
| Онбординг новых пользователей (5 фаз) | workspace/BOOT.md | Работает |
| Голосовые сообщения (STT) | openai-whisper bundled + faster-whisper | Работает |
| Обработка файлов (PDF, DOCX, Excel, изображения) | nano-pdf, summarize bundled | Работает |
| Генерация изображений (DALL-E) | image-generation ClawHub | Требует ChatGPT OAuth |
| Озвучка текста (TTS) | elevenlabs-tts ClawHub | Требует ELEVENLABS_API_KEY |
| Веб-поиск | agent-browser ClawHub | Работает |
| Память (USER.md, MEMORY.md, daily notes) | session-memory hook | Работает |
| Крон (5 задач) | cron/jobs.json | Сконфигурирован |
| KentBytes (31 рецепт в 6 категориях) | workspace/kentbytes/ | Работает |

---

## Кастомные скиллы (17 шт.)

### Core (7) — работают из коробки

| Скилл | Строк | Команда | Ext deps | Env | Known issues |
|-------|-------|---------|----------|-----|-------------|
| humanize | 128 | /humanize | Нет | Нет | — |
| faq-responder | 214 | /faq | Нет | Нет | — |
| crm-notes | 262 | /crm | Нет | Нет | — |
| coder | 280 | /code | Docker sandbox | Нет | sandbox=off в конфиге по умолчанию |
| social-drafts | 278 | /content | DALL-E (opt) | Нет | Генерация картинок требует ChatGPT OAuth |
| content-calendar | 172 | /smm | Google Calendar (opt) | GOOGLE_* | Calendar sync опционален |
| weather-fallback | 57 | — | wttr.in API | Нет | Зависит от внешнего API |

### Beta (8) — работают при наличии интеграций

| Скилл | Строк | Команда | Ext deps | Env | Known issues |
|-------|-------|---------|----------|-----|-------------|
| lead-capture | 174 | /lead | Google Sheets | GOOGLE_* | Требует Google OAuth |
| smm-manager | 297 | /smm | social-drafts | Нет | Мета-скилл, зависит от других |
| broadcast-composer | 303 | /broadcast | crm-notes | Нет | Требует заполненную CRM |
| email-triage | 98 | /mail | Gmail API (gog) | GOOGLE_* | Требует Google OAuth |
| doc-generator | 143 | /doc | python-docx, reportlab | Нет | pip deps установлены deploy.sh |
| finance-tracker | 187 | /finance | Google Sheets (opt) | GOOGLE_* | Расчёт УСН 6% не тестирован |
| pptx-manager | 363 | /slides | python-pptx, Pillow | Нет | Зависит от pptx_tool.py |
| alice-smarthome | 385 | /home | Yandex IoT API | YANDEX_* | RU-only, требует Yandex OAuth |

### Experimental (2) — минимальная реализация

| Скилл | Строк | Команда | Ext deps | Env | Known issues |
|-------|-------|---------|----------|-----|-------------|
| youtube-summary | 52 | — | yt-dlp | Нет | SKILL.md минимален (52 строки) |
| idea-reality | 37 | — | REST API | Нет | Hardcoded внешний API, надёжность не проверена |

---

## ClawHub-скиллы (12 шт.)

Устанавливаются deploy.sh шаг [11/21]:

| Скилл | Назначение | Используется Kent |
|-------|-----------|-------------------|
| agent-browser | Веб-поиск и скрейпинг | Да (core) |
| elevenlabs-tts | Озвучка текста | Да (core, если настроен) |
| image-generation | Генерация изображений DALL-E | Да (core) |
| pdf-tools | Обработка PDF | Да (core) |
| tavily-search | Поиск (Tavily API) | Да (опционально) |
| spotify-player | Управление музыкой | Нет (личное использование) |
| crm | ClawHub CRM | ⚠️ Возможен конфликт с Kent crm-notes |
| humanizer | Очеловечивание текста | ⚠️ Возможен конфликт с Kent humanize |
| seo-blog-writer | SEO-контент | Нет (не используется Kent напрямую) |
| seo-content-engine | SEO-анализ | Нет (не используется Kent напрямую) |
| capability-evolver | Самоулучшение агента | Да (internal) |
| self-improving-agent | Самоулучшение агента | Да (internal) |

> **Known issue:** ClawHub `humanizer` и `crm` могут конфликтовать по триггерам с Kent `humanize` и `crm-notes`. Требует runtime-тестирования.

---

## Фантомные скиллы (в docs, НЕ реализованы)

Следующие скиллы упоминаются в docs/SKILLS-BUNDLE.md, но **не имеют реализации** в workspace/skills/:

| Скилл | Описание | Статус |
|-------|---------|--------|
| contract-analyzer | Анализ договоров | PLANNED |
| summarizer | Суммаризация документов | PLANNED |
| meeting-notes | Расшифровка встреч | PLANNED |
| competitor-monitor | Мониторинг конкурентов | PLANNED |
| wildberries-ozon | Маркетплейсы WB/Ozon | PLANNED |
| vk-manager | Управление ВКонтакте | PLANNED |
| gosuslugi-checker | Проверка контрагентов | PLANNED |
| cdek-tracker | Трекинг СДЭК | PLANNED |

---

## Telegram-команды (20 шт.)

Маппинг customCommands из openclaw.json:

| Команда | Скилл/функция | Тир |
|---------|--------------|-----|
| /help | Справка (встроенная) | core |
| /lead | lead-capture | beta |
| /content | social-drafts | core |
| /faq | faq-responder | core |
| /brief | Составить бриф (встроенная) | core |
| /home | alice-smarthome | beta |
| /draw | Генерация изображений (DALL-E) | core |
| /slides | pptx-manager | beta |
| /smm | smm-manager | beta |
| /code | coder | core |
| /crm | crm-notes | core |
| /broadcast | broadcast-composer | beta |
| /mail | email-triage | beta |
| /doc | doc-generator | beta |
| /finance | finance-tracker | beta |
| /humanize | humanize | core |
| /recipes | KentBytes каталог (встроенная) | core |
| /settings | Настройки бота (встроенная) | core |
| /feedback | Обратная связь (встроенная) | core |
| /status | Статус системы (встроенная) | core |

---

## Инфраструктура

| Компонент | Статус | Тест | Файл |
|-----------|--------|------|------|
| Docker deploy (2 контейнера) | Тестирован на VPS | deploy.sh 21 шаг | docker/docker-compose.yml |
| Health check | Работает | monitor.sh + cron | monitor.sh |
| Cron (5 задач) | Сконфигурирован | Не тестирован e2e | cron/jobs.json |
| Memory system | Реализован | Нет автотеста | workspace/MEMORY.md |
| Backup | Реализован | Нет теста restore | backup.sh |
| Update | Реализован | Тестирован | update.sh |
| Firewall (ufw) | Настраивается deploy.sh | Шаг [6/21] | deploy.sh |
| systemd service | Сконфигурирован | Linux-only | systemd/openclaw.service |
| Логирование | info + file rotation | Автоматическое | openclaw.json logging |

---

## Зависимости

### Python (устанавливаются deploy.sh шаг [5/21])
faster-whisper, python-pptx, Pillow, PyPDF2, python-docx, openpyxl, pandas, yt-dlp, reportlab

### Системные
Docker 24+, Node.js (pnpm), Python 3.9+, curl, jq, openssl

### Внешние API
- Telegram Bot API (обязательно)
- OpenAI Codex OAuth (обязательно для моделей)
- Google APIs (опционально: Gmail, Calendar, Drive, Sheets, Contacts)
- Yandex IoT API (опционально: умный дом)
- Twitter/X API v2 (опционально: публикации)
- ElevenLabs API (опционально: TTS)
- wttr.in (погода, без ключа)

---

## Известные ограничения v1

- Файловое хранилище (Markdown + JSON), нет БД
- Однопользовательский режим (один клиент на инстанс)
- 8 запланированных скиллов не реализованы
- Потенциальный конфликт ClawHub humanizer/crm vs Kent humanize/crm-notes
- youtube-summary и idea-reality — минимальная реализация
- Нет автоматических интеграционных тестов (только static checks)
