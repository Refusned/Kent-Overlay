# Kent Overlay — Тесты

## Запуск

```bash
# Все статические тесты
bash tests/run-all.sh static

# Все deploy-тесты  
bash tests/run-all.sh deploy

# Все smoke-тесты (требуют запущенный инстанс)
bash tests/run-all.sh smoke

# Всё кроме smoke
bash tests/run-all.sh
```

## Структура
- `static/` — проверки без запущенного инстанса (файлы, конфиги, docs)
- `deploy/` — проверки корректности конфигурации для деплоя
- `smoke/` — проверки против живого инстанса
- `MANUAL-SMOKE-CHECKLIST.md` — ручной чеклист для полного прогона
