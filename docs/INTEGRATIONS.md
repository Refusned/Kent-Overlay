# Справочник интеграций Kent

Детальное руководство по настройке всех 26 интеграций Kent AI Assistant.

---

## Содержание

1. [Core](#core) -- Telegram, Codex, ChatGPT
2. [Google](#google) -- Gmail, Calendar, Drive
3. [Social](#social) -- Twitter/X, Instagram, VK, LinkedIn
4. [Media](#media) -- ElevenLabs TTS, faster-whisper STT, Image Generation, PPTX
5. [Smart Home](#smart-home) -- Yandex Alice
6. [Search](#search) -- Tavily, Agent Browser
7. [Dev](#dev) -- GitHub, Coder

---

## Core

### 1. Telegram

**Что делает:** Основной канал связи с пользователем. Прием и отправка сообщений, файлов, голосовых.

**Предварительные требования:**
- Аккаунт Telegram
- Созданный бот через @BotFather (см. [BOTFATHER.md](BOTFATHER.md))

**Настройка:**

1. Создайте бота через @BotFather и получите токен.
2. Укажите токен в `.env`:
   ```env
   TELEGRAM_BOT_TOKEN=7000000000:AAxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
   ```
3. Укажите Telegram ID администратора:
   ```env
   TELEGRAM_ADMIN_ID=123456789
   ```
   Чтобы узнать свой ID, отправьте любое сообщение боту @userinfobot.

4. Перезапустите gateway:
   ```bash
   sudo systemctl restart kent-gateway
   ```

**Проверка:**
- Отправьте `/start` боту. Должен ответить приветствием.
- Отправьте текстовое сообщение. Бот должен ответить.

**Устранение неполадок:**
- *Бот не отвечает:* Проверьте токен, проверьте логи gateway.
- *Бот отвечает с задержкой:* Проверьте соединение с интернетом на VPS.
- *Ошибка 409 Conflict:* Убедитесь, что не запущен второй экземпляр с тем же токеном.

---

### 2. Codex (языковые модели)

**Что делает:** Обеспечивает работу AI-моделей для генерации текста, анализа, рассуждений.

**Предварительные требования:**
- Активная подписка Codex (Claude / GPT и др.)
- API-ключ

**Настройка:**

1. Получите API-ключ из панели управления Codex.
2. Укажите в `.env`:
   ```env
   CODEX_API_KEY=sk-xxxxxxxxxxxxxxxxxxxxxxxx
   CODEX_MODEL=claude-sonnet-4-20250514
   ```
3. Опционально настройте параметры модели:
   ```env
   CODEX_MAX_TOKENS=4096
   CODEX_TEMPERATURE=0.7
   ```

**Проверка:**
- Отправьте боту вопрос. Он должен дать развернутый ответ.
- Проверьте в логах, что нет ошибок API.

**Устранение неполадок:**
- *401 Unauthorized:* Неверный API-ключ. Проверьте и обновите.
- *429 Rate Limit:* Слишком много запросов. Подождите или повысьте план.
- *500 Server Error:* Проблема на стороне провайдера. Попробуйте позже.

---

### 3. ChatGPT (генерация изображений)

**Что делает:** Генерация изображений по текстовому описанию через DALL-E.

**Предварительные требования:**
- Активная подписка ChatGPT Plus / Team / Enterprise
- Session token

**Настройка:**

1. Войдите в chat.openai.com в браузере.
2. Откройте DevTools (F12) -> Application -> Cookies.
3. Найдите cookie `__Secure-next-auth.session-token`.
4. Скопируйте значение и укажите в `.env`:
   ```env
   CHATGPT_SESSION_TOKEN=eyJhxxxxxxxxxxxxxxxxxxxxxxxx
   ```

**Проверка:**
- Отправьте боту: "Нарисуй котика в космосе".
- Kent должен вернуть изображение в течение 30-60 секунд.

**Устранение неполадок:**
- *Изображения не генерируются:* Session token истек. Повторите шаги 1-4.
- *Ошибка 403:* Подписка ChatGPT неактивна или недостаточна.
- *Token нужно обновлять:* Примерно каждые 1-2 недели. Рассмотрите автоматизацию.

> **Важно:** Session token истекает периодически. Настройте напоминание для обновления.

---

## Google

### 4. Gmail

**Что делает:** Чтение, поиск и отправка email через Gmail.

**Предварительные требования:**
- Google аккаунт
- Google Cloud Console проект с включенным Gmail API

**Настройка:**

1. Перейдите на https://console.cloud.google.com/
2. Создайте новый проект (или используйте существующий).
3. Включите Gmail API:
   - APIs & Services -> Library -> Gmail API -> Enable
4. Создайте OAuth 2.0 credentials:
   - APIs & Services -> Credentials -> Create Credentials -> OAuth client ID
   - Application type: Desktop App
   - Скачайте JSON с credentials.
5. Получите refresh token:
   ```bash
   cd ~/kent-overlay
   python3 scripts/google_auth.py --service gmail
   ```
   Следуйте инструкциям в терминале. Будет открыт браузер для авторизации.
6. Добавьте в `.env`:
   ```env
   GOOGLE_CLIENT_ID=xxxxxxxxxxxxx.apps.googleusercontent.com
   GOOGLE_CLIENT_SECRET=GOCSPx-xxxxxxxxxxxxxxxx
   GOOGLE_REFRESH_TOKEN=1//xxxxxxxxxxxxxxxx
   GMAIL_ENABLED=true
   ```

**Проверка:**
- Отправьте боту: "Покажи последние 5 писем".
- Kent должен показать список писем из Gmail.

**Устранение неполадок:**
- *401 Invalid credentials:* Refresh token истек. Повторите шаг 5.
- *403 Insufficient permissions:* Убедитесь, что при авторизации дали доступ к Gmail.
- *Не видит письма:* Проверьте, что Gmail API включен в Google Cloud Console.

---

### 5. Google Calendar

**Что делает:** Создание, просмотр и управление событиями в Google Calendar.

**Предварительные требования:**
- Google аккаунт (тот же, что и для Gmail)
- Google Calendar API включен

**Настройка:**

1. В Google Cloud Console включите Calendar API:
   - APIs & Services -> Library -> Google Calendar API -> Enable
2. Используйте тот же OAuth credential, что и для Gmail.
3. Если refresh token уже получен для Gmail, добавьте scope:
   ```bash
   python3 scripts/google_auth.py --service calendar --existing-token
   ```
4. Добавьте в `.env`:
   ```env
   GOOGLE_CALENDAR_ENABLED=true
   GOOGLE_CALENDAR_ID=primary
   ```

**Проверка:**
- Отправьте боту: "Что у меня в календаре на сегодня?"
- Отправьте: "Создай событие: встреча с Олегом завтра в 15:00".

**Устранение неполадок:**
- *Не видит события:* Проверьте GOOGLE_CALENDAR_ID. Для основного календаря используйте `primary`.
- *Не создает события:* Проверьте, что scope включает запись в календарь.
- *Неверное время:* Проверьте TIMEZONE в `.env`.

---

### 6. Google Drive

**Что делает:** Поиск, загрузка и управление файлами на Google Drive.

**Предварительные требования:**
- Google аккаунт
- Google Drive API включен

**Настройка:**

1. В Google Cloud Console включите Drive API:
   - APIs & Services -> Library -> Google Drive API -> Enable
2. Добавьте scope для Drive:
   ```bash
   python3 scripts/google_auth.py --service drive --existing-token
   ```
3. Добавьте в `.env`:
   ```env
   GOOGLE_DRIVE_ENABLED=true
   ```

**Проверка:**
- Отправьте боту: "Найди на Drive файл с отчетом".
- Kent должен показать список найденных файлов.

**Устранение неполадок:**
- *Файлы не находятся:* Проверьте, что Drive API включен и scope корректен.
- *Нет доступа к файлу:* Убедитесь, что файл принадлежит авторизованному аккаунту или расшарен для него.

---

## Social

### 7. Twitter/X

**Что делает:** Публикация твитов, чтение ленты, поиск по Twitter.

**Предварительные требования:**
- Аккаунт Twitter/X
- Twitter Developer Account с API-ключами (free tier)

**Настройка:**

1. Перейдите на https://developer.twitter.com/
2. Зарегистрируйте приложение (Developer Portal -> Projects & Apps).
3. Получите API Key, API Secret, Access Token, Access Token Secret.
4. Добавьте в `.env`:
   ```env
   TWITTER_API_KEY=xxxxxxxxxxxxxxxxxxxxxxxx
   TWITTER_API_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
   TWITTER_ACCESS_TOKEN=xxxxxxxxxxxxxxxxxxxx-xxxxxxxxxxxxxxxxxxxxxxxx
   TWITTER_ACCESS_TOKEN_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
   TWITTER_ENABLED=true
   ```

**Проверка:**
- Отправьте боту: "Опубликуй твит: Тестовый пост от Kent".
- Проверьте, что твит появился в аккаунте.

**Устранение неполадок:**
- *403 Forbidden:* Free tier имеет ограничения. Проверьте лимиты.
- *401 Unauthorized:* Неверные ключи. Перегенерируйте в Developer Portal.
- *Дубликат:* Twitter не позволяет публиковать идентичные твиты подряд.

---

### 8. Instagram (ручная публикация)

**Что делает:** Kent готовит контент (текст + изображение), оператор или клиент публикует вручную.

**Предварительные требования:**
- Аккаунт Instagram
- Бизнес- или Creator-аккаунт (для статистики)

**Настройка:**

1. Включите навык в конфигурации:
   ```env
   INSTAGRAM_ENABLED=true
   INSTAGRAM_MODE=manual
   ```
2. Kent будет генерировать:
   - Текст поста с хештегами
   - Изображение (если есть интеграция ChatGPT)
   - Рекомендации по времени публикации

**Процесс публикации:**

1. Попросите Kent: "Подготовь пост для Instagram про наш новый продукт".
2. Kent сгенерирует текст и изображение.
3. Скачайте изображение из чата Telegram.
4. Скопируйте текст.
5. Опубликуйте через приложение Instagram.

**Устранение неполадок:**
- *Нет изображения:* Убедитесь, что ChatGPT интеграция работает.
- *Текст слишком длинный:* Попросите Kent сократить (лимит Instagram -- 2200 символов).

---

### 9. VK (ручная публикация)

**Что делает:** Kent готовит контент для VK, публикация -- вручную.

**Предварительные требования:**
- Аккаунт VK
- Группа или личная страница

**Настройка:**

```env
VK_ENABLED=true
VK_MODE=manual
```

**Процесс:**
1. Попросите Kent подготовить пост для VK.
2. Kent сгенерирует текст, адаптированный под формат VK.
3. Скопируйте и опубликуйте через VK.

---

### 10. LinkedIn (ручная публикация)

**Что делает:** Kent готовит профессиональный контент для LinkedIn.

**Предварительные требования:**
- Аккаунт LinkedIn

**Настройка:**

```env
LINKEDIN_ENABLED=true
LINKEDIN_MODE=manual
```

**Процесс:**
1. Попросите Kent: "Напиши пост для LinkedIn про [тема]".
2. Kent сгенерирует текст в профессиональном стиле LinkedIn.
3. Скопируйте и опубликуйте через LinkedIn.

---

## Media

### 11. ElevenLabs TTS (озвучка текста)

**Что делает:** Превращает текст в речь с естественным голосом. Kent отправляет аудиосообщение в Telegram.

**Предварительные требования:**
- Аккаунт ElevenLabs (https://elevenlabs.io)
- API-ключ (есть бесплатный tier)

**Настройка:**

1. Зарегистрируйтесь на https://elevenlabs.io
2. Перейдите в Profile -> API Keys.
3. Скопируйте API-ключ.
4. Выберите голос в Voice Library и скопируйте Voice ID.
5. Добавьте в `.env`:
   ```env
   ELEVENLABS_API_KEY=xxxxxxxxxxxxxxxxxxxxxxxx
   ELEVENLABS_VOICE_ID=xxxxxxxxxxxxxxxxxxxxxxxx
   ELEVENLABS_MODEL=eleven_multilingual_v2
   ELEVENLABS_ENABLED=true
   ```

**Доступные голоса (русский язык):**
- Выберите голос в Voice Library с поддержкой русского языка.
- Можно клонировать свой голос (платный plan).

**Проверка:**
- Отправьте боту: "/tts Привет, это тестовое сообщение".
- Kent должен прислать голосовое сообщение.

**Устранение неполадок:**
- *Нет звука:* Проверьте API-ключ и Voice ID.
- *Голос на английском:* Используйте модель `eleven_multilingual_v2`.
- *Превышен лимит:* Бесплатный tier -- 10 000 символов/месяц. Повысьте план при необходимости.

---

### 12. faster-whisper STT (распознавание речи)

**Что делает:** Распознает голосовые сообщения в текст. Работает локально на сервере, без отправки данных на внешние API.

**Предварительные требования:**
- Python 3.10+
- pip3
- 1-2 GB свободного места для модели

**Настройка:**

1. Установите faster-whisper:
   ```bash
   pip3 install --user faster-whisper
   ```
2. Скачайте модель при первом запуске (автоматически) или вручную:
   ```bash
   python3 -c "from faster_whisper import WhisperModel; WhisperModel('base')"
   ```
3. Добавьте в `.env`:
   ```env
   STT_ENGINE=faster-whisper
   STT_MODEL=base
   STT_LANGUAGE=ru
   STT_ENABLED=true
   ```

**Доступные модели:**

| Модель | Размер | Качество | Скорость |
|--------|--------|----------|----------|
| `tiny` | ~75 MB | Базовое | Очень быстро |
| `base` | ~150 MB | Хорошее | Быстро |
| `small` | ~500 MB | Отличное | Средне |
| `medium` | ~1.5 GB | Превосходное | Медленно |

Рекомендуется `base` для баланса качества и скорости на 4GB RAM.

**Проверка:**
- Отправьте голосовое сообщение боту.
- Kent должен распознать речь и ответить текстом.

**Устранение неполадок:**
- *ModuleNotFoundError:* `pip3 install --user faster-whisper`.
- *Модель не найдена:* Скачайте вручную (см. шаг 2).
- *Плохое распознавание:* Попробуйте модель `small`. Проверьте качество микрофона у клиента.
- *Нехватка RAM:* Используйте модель `tiny` или `base`.

---

### 13. Генерация изображений

**Что делает:** Создает изображения по текстовому описанию. Использует ChatGPT (DALL-E) как backend.

**Предварительные требования:**
- Настроенная интеграция ChatGPT (см. раздел Core -> ChatGPT)

**Настройка:**
Интеграция настраивается автоматически при наличии ChatGPT session token.

```env
IMAGE_GENERATION_ENABLED=true
IMAGE_SIZE=1024x1024
```

**Проверка:**
- `/image Красивый закат над морем в стиле импрессионизма`

**Устранение неполадок:**
- *Генерация не работает:* Обновите ChatGPT session token.
- *Изображение не соответствует запросу:* Уточните промпт, добавьте детали стиля.

---

### 14. PPTX (презентации)

**Что делает:** Создает файлы PowerPoint (.pptx) по запросу пользователя.

**Предварительные требования:**
- Python 3
- pip3

**Настройка:**

1. Установите python-pptx:
   ```bash
   pip3 install --user python-pptx Pillow
   ```
2. Добавьте в `.env`:
   ```env
   PPTX_ENABLED=true
   ```

**Проверка:**
- Отправьте боту: "/pptx Сделай презентацию на 5 слайдов про AI в бизнесе".
- Kent должен прислать файл .pptx.

**Устранение неполадок:**
- *ModuleNotFoundError python-pptx:* `pip3 install --user python-pptx`.
- *Файл не открывается:* Попробуйте открыть в Google Slides или LibreOffice.
- *Нет изображений в слайдах:* Убедитесь, что Pillow установлен.

---

## Smart Home

### 15. Yandex Alice (умный дом)

**Что делает:** Управление умными устройствами через Yandex IoT API: свет, розетки, кондиционеры, сценарии.

**Предварительные требования:**
- Аккаунт Яндекс
- Устройства, подключенные к Яндекс Умному Дому
- OAuth-токен Яндекс

**Настройка:**

1. Получите OAuth-токен:
   - Перейдите на https://oauth.yandex.ru/
   - Создайте приложение с правами `iot:view` и `iot:control`.
   - Авторизуйтесь и получите токен.
2. Добавьте в `.env`:
   ```env
   YANDEX_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
   YANDEX_IOT_ENABLED=true
   ```
3. Перезапустите gateway.

**Проверка:**
- Отправьте боту: "Покажи список устройств умного дома".
- Отправьте: "Включи свет в гостиной".

**Устранение неполадок:**
- *Не видит устройства:* Проверьте, что устройства добавлены в приложение Яндекс.
- *401 Unauthorized:* Токен истек. Получите новый.
- *Устройство не отвечает:* Проверьте, что устройство онлайн в приложении Яндекс.

---

## Search

### 16. Tavily Search

**Что делает:** Поиск актуальной информации в интернете с AI-оптимизированными результатами.

**Предварительные требования:**
- Аккаунт Tavily (https://tavily.com)
- API-ключ

**Настройка:**

1. Зарегистрируйтесь на https://tavily.com
2. Получите API-ключ в дашборде.
3. Добавьте в `.env`:
   ```env
   TAVILY_API_KEY=tvly-xxxxxxxxxxxxxxxxxxxxxxxx
   TAVILY_ENABLED=true
   ```

**Проверка:**
- Отправьте боту: "/search Последние новости про AI".
- Kent должен вернуть актуальные результаты.

**Устранение неполадок:**
- *Пустые результаты:* Попробуйте другой запрос. Проверьте API-ключ.
- *Превышен лимит:* Free tier -- 1000 запросов/месяц. Повысьте план.

---

### 17. Agent Browser

**Что делает:** Открывает веб-страницы, читает содержимое, извлекает данные. Работает как встроенный браузер.

**Предварительные требования:**
- Нет внешних зависимостей (встроен в Kent)

**Настройка:**

```env
AGENT_BROWSER_ENABLED=true
AGENT_BROWSER_TIMEOUT=30000
```

**Проверка:**
- Отправьте боту: "Открой сайт example.com и расскажи, что там".
- Kent должен открыть страницу и описать содержимое.

**Устранение неполадок:**
- *Таймаут:* Увеличьте `AGENT_BROWSER_TIMEOUT`.
- *Не может открыть сайт:* Некоторые сайты блокируют автоматический доступ.
- *Пустая страница:* Сайт использует JavaScript-рендеринг, который Agent Browser может не поддерживать.

---

## Dev

### 18. GitHub

**Что делает:** Работа с репозиториями GitHub: просмотр issues, PR, коммитов, создание и управление.

**Предварительные требования:**
- Аккаунт GitHub
- Personal Access Token (classic или fine-grained)

**Настройка:**

1. Перейдите на https://github.com/settings/tokens
2. Создайте новый token (classic):
   - Scopes: `repo`, `read:user`, `read:org`
3. Добавьте в `.env`:
   ```env
   GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
   GITHUB_ENABLED=true
   GITHUB_DEFAULT_REPO=owner/repo
   ```

**Проверка:**
- Отправьте боту: "Покажи последние issues в моем репозитории".
- Kent должен показать список issues.

**Устранение неполадок:**
- *401 Bad credentials:* Токен неверный или истек. Перегенерируйте.
- *404 Not Found:* Убедитесь, что у токена есть доступ к репозиторию.
- *Нет доступа к приватному репо:* Добавьте scope `repo` к токену.

---

### 19. Coder (программирование)

**Что делает:** Kent может писать, объяснять и анализировать код. Поддерживает множество языков программирования.

**Предварительные требования:**
- Нет дополнительных зависимостей (использует Codex для генерации)

**Настройка:**

```env
CODER_ENABLED=true
CODER_DEFAULT_LANGUAGE=python
```

**Проверка:**
- Отправьте боту: "Напиши функцию на Python, которая сортирует список словарей по ключу".
- Kent должен вернуть рабочий код с объяснением.

**Устранение неполадок:**
- *Некорректный код:* Попросите Kent исправить или уточните требования.
- *Не поддерживает язык:* Kent поддерживает все популярные языки. Укажите язык явно.

---

## Полный список интеграций

| # | Интеграция | Категория | Внешний API | Стоимость |
|---|-----------|-----------|-------------|-----------|
| 1 | Telegram | Core | Telegram Bot API | Бесплатно |
| 2 | Codex | Core | Codex API | Подписка |
| 3 | ChatGPT | Core | OpenAI | Подписка |
| 4 | Gmail | Google | Gmail API | Бесплатно |
| 5 | Google Calendar | Google | Calendar API | Бесплатно |
| 6 | Google Drive | Google | Drive API | Бесплатно |
| 7 | Twitter/X | Social | Twitter API | Free tier |
| 8 | Instagram | Social | -- (ручной) | Бесплатно |
| 9 | VK | Social | -- (ручной) | Бесплатно |
| 10 | LinkedIn | Social | -- (ручной) | Бесплатно |
| 11 | ElevenLabs TTS | Media | ElevenLabs API | Free / от $5 |
| 12 | faster-whisper STT | Media | Локально | Бесплатно |
| 13 | Image Generation | Media | ChatGPT | Подписка |
| 14 | PPTX | Media | Локально | Бесплатно |
| 15 | Yandex Alice | Smart Home | Yandex IoT API | Бесплатно |
| 16 | Tavily Search | Search | Tavily API | Free / от $0 |
| 17 | Agent Browser | Search | Встроен | Бесплатно |
| 18 | GitHub | Dev | GitHub API | Бесплатно |
| 19 | Coder | Dev | Codex | Подписка |

> **Примечание:** Интеграции 20-26 являются суб-навыками основных интеграций (отправка email, создание событий, загрузка файлов, чтение ленты, генерация хештегов, резюмирование страниц, парсинг PDF) и настраиваются автоматически при включении родительской интеграции.

---

## Общие рекомендации

### Порядок настройки

1. Начните с Core (Telegram, Codex) -- без них Kent не работает.
2. Добавьте STT (faster-whisper) -- голосовые сообщения нужны почти всем.
3. Настройте Google интеграции, если клиент использует Google Workspace.
4. Добавьте остальные по потребностям клиента.

### Безопасность токенов

- Никогда не коммитьте `.env` в git.
- Используйте разные токены для разных клиентов.
- Периодически ротируйте токены (особенно ChatGPT session token).
- Храните резервные копии токенов в безопасном месте (менеджер паролей).

### Мониторинг

Проверяйте работоспособность интеграций:

```bash
# Статус интеграций в логах
journalctl -u kent-gateway | grep -i "integration"

# Или через бота
/status
```
