# Kent Demo Bot

Конфигурация для публичного демо-бота @KentDemoBot.

## Быстрый старт

1. Создай бота через @BotFather, получи токен
2. Скопируй `.env.demo.example` → `.env` и заполни
3. Скопируй `openclaw-demo.json` в `~/.openclaw/openclaw.json` на VPS
4. Скопируй `AGENTS-DEMO.md` в `~/.openclaw/workspace/AGENTS.md` на VPS
5. Основные файлы (SOUL.md, SECURITY.md, skills/) — берутся из основного workspace

## Отличия от полной версии

- `dmPolicy: open` — бот доступен всем (не только одному клиенту)
- Лимит 15 ответов/сессию (реализован в AGENTS-DEMO.md)
- Только 5 скиллов: humanize, social-drafts, faq, weather, coder
- Нет cron-задач, нет интеграций с Google/Twitter
- Нет генерации изображений
- Более жёсткие лимиты контекста (20K tokens вместо 40K)
