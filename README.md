# Kent AI Assistant

Персонализированный AI бизнес-ассистент и SMM-менеджер, доставляемый как Telegram-бот.
Overlay (надстройка) над платформой [OpenClaw](https://openclaw.dev).

## Быстрый старт

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Refusned/Kent-Overlay/main/install.sh)
```

Ручной деплой: `prerequisites.sh` -> `configure.sh` -> `deploy.sh`

## Что умеет Kent v1

| | |
|---|---|
| **Core** | Telegram-чат с личностью и памятью, онбординг, голосовые, файлы, генерация картинок, веб-поиск, TTS |
| **Скиллы** | 7 core + 8 beta + 2 experimental ([подробности](READINESS.md)) |
| **Автоматизация** | 5 cron-задач: утренний брифинг, health-check, отчёт, SMM, бэкап |
| **Рецепты** | 31 KentBytes в 6 категориях (бухгалтеры, предприниматели, фрилансеры, юристы, SMM, студенты) |

## Требования

- Ubuntu 24.04 LTS
- 4 GB RAM, 2 vCPU, 40 GB SSD
- Docker 24+
- Telegram Bot Token (от @BotFather)
- Подписка OpenAI Codex (для моделей)

## Документация

| Документ | Описание |
|----------|---------|
| [READINESS.md](READINESS.md) | Матрица готовности всех компонентов |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | Гайд по деплою |
| [docs/CONFIG-REFERENCE.md](docs/CONFIG-REFERENCE.md) | Справочник по конфигурации |
| [docs/INTEGRATIONS.md](docs/INTEGRATIONS.md) | Настройка интеграций |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Решение проблем |
| [docs/CUSTOMIZATION.md](docs/CUSTOMIZATION.md) | Кастомизация под клиента |

## Тестирование

```bash
bash tests/run-all.sh          # static + deploy тесты
bash tests/run-all.sh smoke    # smoke-тесты (требуют запущенный инстанс)
```

Ручной чеклист: [tests/MANUAL-SMOKE-CHECKLIST.md](tests/MANUAL-SMOKE-CHECKLIST.md)

## Структура проекта

```
kent-overlay/
  workspace/           # Рантайм агента: личность, правила, память, скиллы
    SOUL.md            # Характер и тон (432 строки)
    SECURITY.md        # Неизменяемые правила безопасности
    AGENTS.md          # Операционное поведение (602 строки)
    skills/            # 17 кастомных скиллов
    kentbytes/         # 31 рецепт в 6 категориях
  config/
    openclaw.json      # Конфиг OpenClaw (JSON5)
  docker/
    docker-compose.yml # openclaw + browser контейнеры
  tests/               # Автоматические и ручные тесты
  docs/                # 14 файлов документации
```

## Версия

1.0.0 | OpenClaw 2026.4.10 | [CHANGELOG.md](CHANGELOG.md)
