# Changelog

## [1.0.0] — 2026-04-11

### Core
- Telegram-бот с личностью Kent (SOUL.md, 432 строки)
- 5-фазный онбординг для новых пользователей (BOOT.md)
- Система памяти: USER.md, MEMORY.md, LEARNED.md, ежедневные заметки
- Правила безопасности (SECURITY.md): красные линии, тиры умного дома
- Операционное поведение (AGENTS.md, 602 строки): загрузка, память, fallback
- Группы Telegram с @mention

### Кастомные скиллы (17)
- **Core (7):** humanize, faq-responder, crm-notes, coder, social-drafts, content-calendar, weather-fallback
- **Beta (8):** lead-capture, smm-manager, broadcast-composer, email-triage, doc-generator, finance-tracker, pptx-manager, alice-smarthome
- **Experimental (2):** youtube-summary, idea-reality

### ClawHub-скиллы (12)
agent-browser, elevenlabs-tts, image-generation, pdf-tools, tavily-search, spotify-player, crm, humanizer, seo-blog-writer, seo-content-engine, capability-evolver, self-improving-agent

### Инфраструктура
- Docker Compose: openclaw + browser контейнеры (hardened: cap_drop ALL, loopback)
- Идемпотентный deploy.sh (21 шаг)
- monitor.sh: мониторинг здоровья с Telegram-алертами
- 5 cron-задач: утренний брифинг, health-check, недельный отчёт, SMM-напоминания, бэкап
- Автоматические тесты: static + deploy + smoke
- GitHub Actions CI для статических проверок

### KentBytes
31 рецепт в 6 категориях: бухгалтеры, предприниматели, фрилансеры, юристы, SMM, студенты

### Документация
- README.md, READINESS.md, CHANGELOG.md
- 14 docs файлов: деплой, интеграции, troubleshooting, кастомизация, pricing
- CONFIG-REFERENCE.md: справочник по openclaw.json

### Известные ограничения
- Файловое хранилище (Markdown + JSON), нет БД
- Однопользовательский режим (один клиент на инстанс)
- 8 запланированных скиллов не реализованы (contract-analyzer, summarizer, meeting-notes, competitor-monitor, wildberries-ozon, vk-manager, gosuslugi-checker, cdek-tracker)
- Потенциальный конфликт ClawHub humanizer/crm vs Kent humanize/crm-notes
- youtube-summary и idea-reality — минимальная реализация
