# Справочник по конфигурации Kent

> openclaw.json нельзя редактировать программно. Только оператор вручную.

## Gateway (шлюз)
- Порт: 18789, привязан к loopback (только localhost)
- Авторизация: token-based через ${OPENCLAW_GATEWAY_TOKEN}
- Health monitor: каждые 5 мин, stale threshold 30 мин
- Max restarts: 10/час

## Agents (настройки агентов)
- Sandbox: off (агенты выполняются без строгой песочницы)
- Context pruning: cache-ttl, TTL 1 час, сохраняет 3 последних ответа
- Compaction: floor 40K токенов, memory flush при 4K soft threshold

## Tools (инструменты)
- Profile: full (все инструменты доступны)
- Запрещены: group:automation, sessions_spawn, nodes, canvas, llm_task

## Approvals (подтверждения)
- exec.enabled: **false** (YOLO mode)
- Платформа НЕ запрашивает подтверждение на exec-операции
- Kent всё равно спрашивает подтверждение на Tier 2 действия (email, публикации, умный дом) — это поведенческий уровень через AGENTS.md и SECURITY.md
- Для включения подтверждений: изменить на `true` в openclaw.json

## Memory (память)
- Backend: builtin (файловый)

## Hooks (хуки)
- 4 внутренних: boot-md, bootstrap-extra-files (SOUL.md, SECURITY.md, AGENTS.md, IDENTITY.md), command-logger, session-memory
- Token: ${OPENCLAW_HOOKS_TOKEN}
- 5-й хук (memory-core-short-term-dreaming-cron) управляется плагином

## Telegram (канал)
- DM policy: pairing (1 сессия на пользователя)
- allowFrom: [${CLIENT_TELEGRAM_ID}]
- Группы: requireMention по умолчанию
- 20 custom commands (help, lead, content, faq, brief, home, draw, slides, smm, code, crm, broadcast, mail, doc, finance, humanize, recipes, settings, feedback, status)
- Streaming: partial, newline chunks
- Text chunk limit: 4000
- Ack reaction: 👔

## Skills (навыки)
- 54 bundled skill разрешены через allowBundled (не сокращать!)
- 17 кастомных в workspace/skills/
- 12 ClawHub-скиллов устанавливаются deploy.sh шаг [11/21]

### ClawHub-скиллы и их назначение
| Скилл | Назначение | Примечание |
|-------|-----------|-----------|
| agent-browser | Веб-поиск | Core |
| elevenlabs-tts | Озвучка текста | Требует ELEVENLABS_API_KEY |
| image-generation | DALL-E | Требует ChatGPT OAuth |
| pdf-tools | PDF обработка | Core |
| tavily-search | Поиск Tavily | Требует TAVILY_API_KEY |
| spotify-player | Музыка | Личное использование |
| crm | ClawHub CRM | Может конфликтовать с Kent crm-notes |
| humanizer | Очеловечивание | Может конфликтовать с Kent humanize |
| seo-blog-writer | SEO-контент | Опциональный |
| seo-content-engine | SEO-анализ | Опциональный |
| capability-evolver | Самоулучшение | Internal |
| self-improving-agent | Самоулучшение | Internal |

## Cron (планировщик)
- Max concurrent runs: 2
- Session retention: 24ч
- Run log: max 2MB, 2000 строк

## Sessions
- Scope: per-channel-peer

## Logging (логирование)
- Level: info (console: warn)
- Redact sensitive: tools
- File: ~/.openclaw/logs/openclaw.log

## Messages
- Debounce: 2 сек
- Queue: collect mode, cap 10
- Ack reaction scope: direct, удаляется после ответа
