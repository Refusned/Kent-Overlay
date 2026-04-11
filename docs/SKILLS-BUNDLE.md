# Kent v1.0 — 25 скиллов из коробки

> **Внимание:** Из описанных скиллов 17 реализованы, 8 находятся в статусе [PLANNED] и не имеют реализации в workspace/skills/.
> Актуальный статус каждого скилла: → [READINESS.md](../READINESS.md)

Финальный список скиллов, которые устанавливаются при деплое Kent. Каждый клиент получает все 25 сразу. Активация по ролям — через онбординг.

---

## Полный список (25 скиллов)

| # | Скилл | Эмодзи | Команда | Категория | Что делает (одним предложением) |
|---|-------|--------|---------|-----------|-------------------------------|
| 1 | **email-triage** | 📬 | `/mail` | Почта | Дайджест входящих, приоритизация, черновики ответов через Gmail |
| 2 | **doc-generator** | 📄 | `/doc` | Документы | Генерация счетов, договоров, актов, КП, претензий с сохранёнными реквизитами |
| 3 | **finance-tracker** | 💰 | `/finance` | Финансы | Учёт доходов/расходов, расчёт налогов ИП (УСН, НПД, патент) |
| 4 | **contract-analyzer** [PLANNED] | ⚖️ | `/contract` | Юриспруденция | Анализ договора на 10 рисков со ссылками на ГК РФ |
| 5 | **social-drafts** | ✍️ | `/content` | Контент | Генерация постов для Telegram, Instagram, VK, X с изображениями |
| 6 | **smm-manager** | 📣 | `/smm` | Маркетинг | Полный цикл SMM: стратегия, контент-план, аналитика, конкурентный анализ |
| 7 | **content-calendar** | 📅 | — | Контент | Планирование контент-календаря с синхронизацией Google Calendar |
| 8 | **humanize** | ✨ | `/humanize` | Контент | Очеловечивание AI-текста: убирает бото-язык, адаптирует под стиль |
| 9 | **lead-capture** | 🎯 | `/lead` | CRM | Захват, квалификация и ведение лидов через диалог |
| 10 | **crm-notes** | 📇 | `/crm` | CRM | Мини-CRM: контакты, история взаимодействий, заметки |
| 11 | **broadcast-composer** | 📢 | `/broadcast` | Рассылки | Составление массовых рассылок в Telegram с A/B-тестированием |
| 12 | **competitor-monitor** [PLANNED] | 🔍 | `/monitor` | Маркетинг | Мониторинг конкурентов: цены, посты, акции, алерты |
| 13 | **summarizer** [PLANNED] | 📋 | `/summary` | Утилита | Суммаризация текстов, PDF, веб-страниц, email-цепочек |
| 14 | **meeting-notes** [PLANNED] | 📝 | `/meeting` | Продуктивность | Расшифровка аудио встреч → протокол, задачи, дедлайны |
| 15 | **pptx-manager** | 📊 | `/slides` | Документы | Создание и редактирование PowerPoint-презентаций |
| 16 | **faq-responder** | ❓ | `/faq` | Поддержка | База знаний и ответы на частые вопросы |
| 17 | **youtube-summary** | 📺 | — | Медиа | Суммаризация YouTube-видео по ссылке |
| 18 | **idea-reality** | 💡 | — | Бизнес | Проверка бизнес-идеи на конкуренцию и существование |
| 19 | **coder** | 💻 | `/code` | Утилита | Написание и выполнение скриптов в Docker-песочнице |
| 20 | **wildberries-ozon** [PLANNED] | 🛒 | `/wb` | E-commerce | Мониторинг позиций, SEO карточек, отзывы на WB и Ozon |
| 21 | **vk-manager** [PLANNED] | 🔵 | `/vk` | Соцсети | Публикация, статистика, комментарии ВКонтакте |
| 22 | **gosuslugi-checker** [PLANNED] | 🏛️ | `/check` | Гос. сервисы | Проверка контрагентов по ИНН, выписки ЕГРЮЛ/ЕГРИП |
| 23 | **cdek-tracker** [PLANNED] | 📦 | `/track` | Логистика | Трекинг посылок СДЭК и Почта России |
| 24 | **alice-smarthome** | 🏠 | `/home` | Умный дом | Управление Yandex-устройствами: свет, розетки, датчики |
| 25 | **weather-fallback** | 🌤️ | — | Утилита | Прогноз погоды по городу |

---

## Распределение по категориям

```
Контент и маркетинг (6):  social-drafts, smm-manager, content-calendar,
                          humanize, broadcast-composer, competitor-monitor

CRM и продажи (2):        lead-capture, crm-notes

Документы и финансы (4):   doc-generator, finance-tracker, contract-analyzer,
                          pptx-manager

Почта и продуктивность (3): email-triage, meeting-notes, summarizer

Российские сервисы (4):    wildberries-ozon, vk-manager, gosuslugi-checker,
                          cdek-tracker

Медиа и утилиты (4):      youtube-summary, idea-reality, coder, faq-responder

Умный дом и погода (2):    alice-smarthome, weather-fallback
```

---

## Рекомендуемые скиллы по ролям

При онбординге Kent спрашивает роль пользователя и подсвечивает 8-10 релевантных скиллов. Остальные доступны, но не выводятся в приветствии.

### Предприниматель / ИП
| Приоритет | Скиллы |
|-----------|--------|
| Основные | email-triage, finance-tracker, doc-generator, crm-notes, lead-capture |
| Полезные | contract-analyzer, competitor-monitor, broadcast-composer, summarizer, pptx-manager |

**Приветственное сообщение:**
> Вот что я умею для вашего бизнеса:
> 📬 /mail — проверю почту и составлю дайджест
> 💰 /finance — веду доходы и расходы, считаю налоги
> 📄 /doc — выставлю счёт, составлю договор или КП
> 📇 /crm — запомню клиентов и историю общения
> 🎯 /lead — захвачу и квалифицирую лидов
> ⚖️ /contract — проверю договор на подводные камни
> 🔍 /monitor — отслежу конкурентов
> 📢 /broadcast — подготовлю рассылку

---

### Маркетолог / SMM
| Приоритет | Скиллы |
|-----------|--------|
| Основные | social-drafts, smm-manager, content-calendar, humanize, competitor-monitor |
| Полезные | broadcast-composer, vk-manager, summarizer, meeting-notes, youtube-summary |

**Приветственное сообщение:**
> Вот мой арсенал для SMM:
> ✍️ /content — напишу пост для любой площадки
> 📣 /smm — стратегия, контент-план, аналитика
> ✨ /humanize — уберу бото-текст, сделаю живым
> 🔍 /monitor — слежу за конкурентами
> 📢 /broadcast — подготовлю рассылку
> 🔵 /vk — публикация и статистика ВКонтакте
> 📋 /summary — кратко перескажу любой текст
> 📝 /meeting — расшифрую встречу и выделю задачи

---

### Фрилансер
| Приоритет | Скиллы |
|-----------|--------|
| Основные | email-triage, doc-generator, finance-tracker, crm-notes, humanize |
| Полезные | social-drafts, summarizer, pptx-manager, contract-analyzer, lead-capture |

**Приветственное сообщение:**
> Вот что пригодится фрилансеру:
> 📬 /mail — дайджест почты и черновики ответов
> 📄 /doc — КП, ТЗ, договор, счёт за минуту
> 💰 /finance — учёт доходов и расходов, налоги
> 📇 /crm — база клиентов и история
> ✨ /humanize — оживлю текст
> ✍️ /content — посты для продвижения
> ⚖️ /contract — проверю договор перед подписанием
> 📊 /slides — соберу презентацию

---

### Юрист
| Приоритет | Скиллы |
|-----------|--------|
| Основные | contract-analyzer, doc-generator, gosuslugi-checker, summarizer, email-triage |
| Полезные | meeting-notes, crm-notes, pptx-manager |

**Приветственное сообщение:**
> Инструменты для юридической работы:
> ⚖️ /contract — анализ договора на 10 рисков + ссылки на ГК РФ
> 📄 /doc — претензия, доверенность, исковое, правовое заключение
> 🏛️ /check — проверка контрагента по ИНН, выписка ЕГРЮЛ
> 📋 /summary — краткое содержание длинного документа
> 📬 /mail — дайджест почты
> 📝 /meeting — протокол встречи из аудиозаписи

---

### Бухгалтер / Финансист
| Приоритет | Скиллы |
|-----------|--------|
| Основные | finance-tracker, doc-generator, gosuslugi-checker, email-triage, summarizer |
| Полезные | contract-analyzer, pptx-manager, meeting-notes |

**Приветственное сообщение:**
> Для бухгалтерской работы:
> 💰 /finance — учёт, отчёты, расчёт налогов (УСН, НПД, патент)
> 📄 /doc — счёт, акт сверки, пояснительная записка
> 🏛️ /check — проверка контрагента по ИНН, долги по налогам
> 📬 /mail — дайджест входящих
> 📋 /summary — краткое содержание документов

---

### Студент
| Приоритет | Скиллы |
|-----------|--------|
| Основные | summarizer, youtube-summary, humanize, meeting-notes, doc-generator |
| Полезные | idea-reality, coder, faq-responder |

**Приветственное сообщение:**
> Помогу с учёбой:
> 📋 /summary — конспект из текста, PDF, статьи
> 📺 Пришли ссылку на YouTube — сделаю конспект видео
> ✨ /humanize — перепишу текст естественнее (для антиплагиата)
> 📝 /meeting — расшифрую аудиозапись лекции
> 📄 /doc — оформление по ГОСТ, титульный лист, список литературы
> 💡 Опиши идею — проверю, есть ли уже такое

---

### E-commerce / Селлер
| Приоритет | Скиллы |
|-----------|--------|
| Основные | wildberries-ozon, cdek-tracker, finance-tracker, competitor-monitor, crm-notes |
| Полезные | social-drafts, doc-generator, broadcast-composer, summarizer |

**Приветственное сообщение:**
> Инструменты для селлера:
> 🛒 /wb — мониторинг позиций, SEO карточек, отзывы на WB/Ozon
> 📦 /track — трекинг посылок СДЭК и Почта России
> 💰 /finance — юнит-экономика, учёт, налоги
> 🔍 /monitor — слежу за конкурентами
> 📇 /crm — база клиентов
> ✍️ /content — контент для продвижения
> 📢 /broadcast — рассылка клиентам

---

## Bundled-скиллы из ClawHub (backend)

Устанавливаются автоматически, не видны пользователю напрямую — используются другими скиллами как инфраструктура.

| Скилл | Назначение | Кто использует |
|-------|-----------|----------------|
| **gog** | Google Workspace API (Gmail, Calendar, Drive, Sheets) | email-triage, content-calendar, finance-tracker |
| **agent-browser** | Browser automation | competitor-monitor, gosuslugi-checker, cdek-tracker, wildberries-ozon |
| **summarize** | Движок суммаризации | summarizer, youtube-summary |
| **github** | GitHub API | coder |
| **healthcheck** | Мониторинг системы | Автоматический |
| **weather** | Погодный API | weather-fallback |
| **clawhub** | Каталог скиллов | Расширение через /skills |
| **session-logs** | Логирование | Диагностика |

**openclaw.json:**
```json
"skills.allowBundled": [
  "gog", "agent-browser", "summarize", "github",
  "healthcheck", "weather", "clawhub", "session-logs"
]
```

---

## Команды в Telegram (меню бота)

Все команды, доступные через кнопку "/" в Telegram:

```
/mail      — 📬 Проверить почту
/doc       — 📄 Создать документ
/finance   — 💰 Финансы и налоги
/contract  — ⚖️ Проверить договор
/content   — ✍️ Написать пост
/smm       — 📣 SMM-управление
/humanize  — ✨ Очеловечить текст
/lead      — 🎯 Работа с лидами
/crm       — 📇 CRM и контакты
/broadcast — 📢 Рассылка
/monitor   — 🔍 Мониторинг конкурентов
/summary   — 📋 Краткое содержание
/meeting   — 📝 Протокол встречи
/slides    — 📊 Презентация
/wb        — 🛒 Wildberries / Ozon
/vk        — 🔵 ВКонтакте
/check     — 🏛️ Проверка контрагента
/track     — 📦 Трекинг посылки
/home      — 🏠 Умный дом
/code      — 💻 Помощь с кодом
/faq       — ❓ Частые вопросы
/recipes   — 📚 Каталог КентБайтс
/settings  — ⚙️ Настройки
/help      — ℹ️ Справка
/feedback  — 💬 Обратная связь
/status    — 🔧 Статус системы
```

---

## Зависимости между скиллами

```
email-triage ──────→ gog (Gmail)
finance-tracker ───→ gog (Google Sheets, опционально)
content-calendar ──→ gog (Google Calendar)
doc-generator ─────→ python-docx, reportlab
pptx-manager ──────→ python-pptx, Pillow
meeting-notes ─────→ faster-whisper (STT)
youtube-summary ───→ yt-dlp, Summarizely
coder ─────────────→ Docker sandbox
competitor-monitor ─→ agent-browser, tavily-search
wildberries-ozon ──→ agent-browser
gosuslugi-checker ─→ agent-browser
cdek-tracker ──────→ СДЭК API (CDEK_CLIENT_ID)
vk-manager ────────→ VK API (VK_ACCESS_TOKEN)
alice-smarthome ───→ Yandex IoT API
smm-manager ───────→ social-drafts, content-calendar
broadcast-composer ─→ crm-notes (сегментация)
lead-capture ──────→ gog (Google Sheets)
humanize ──────────→ (нет зависимостей)
summarizer ────────→ summarize (bundled)
contract-analyzer ─→ (нет зависимостей)
idea-reality ──────→ tavily-search
faq-responder ─────→ (нет зависимостей)
weather-fallback ──→ weather (bundled) / wttr.in
crm-notes ─────────→ (нет зависимостей)
```

---

## Обязательные ENV-переменные

### Минимум для работы (Lite тариф)
```env
OPENCLAW_GATEWAY_TOKEN=...   # токен шлюза
TELEGRAM_BOT_TOKEN=...       # токен Telegram-бота
```

### Для полного набора скиллов (Business тариф)
```env
# Core
OPENCLAW_GATEWAY_TOKEN=...
TELEGRAM_BOT_TOKEN=...

# Google (email-triage, calendar, finance-tracker, lead-capture)
GOOGLE_OAUTH_TOKEN=...

# Поиск (competitor-monitor, idea-reality)
TAVILY_API_KEY=...

# Соцсети (vk-manager)
VK_ACCESS_TOKEN=...
VK_GROUP_ID=...

# Логистика (cdek-tracker)
CDEK_CLIENT_ID=...
CDEK_CLIENT_SECRET=...

# Умный дом (alice-smarthome)
YANDEX_IOT_TOKEN=...

# Медиа (опционально)
ELEVENLABS_API_KEY=...       # TTS
CHATGPT_AUTH_TOKEN=...       # DALL-E изображения

# Twitter/X (опционально)
TWITTER_API_KEY=...
```
