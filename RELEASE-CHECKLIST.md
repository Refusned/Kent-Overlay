# Kent v1.0 — Release Checklist

## Pre-Release

- [ ] `bash tests/run-all.sh` — все static и deploy тесты проходят
- [ ] READINESS.md актуален и совпадает с workspace/skills/ (17 скиллов)
- [ ] Нет .env или credentials в git: `git diff --cached --name-only | grep -E '\.env|credential'`
- [ ] README.md существует и точен
- [ ] CHANGELOG.md документирует релиз
- [ ] VERSION содержит 1.0.0
- [ ] docs/SKILLS-BUNDLE.md закоммичен (не untracked)
- [ ] Все фантомные скиллы помечены [PLANNED] в docs

## Deploy Test (на чистом Ubuntu 24.04 VPS)

- [ ] `bash install.sh` — end-to-end без ошибок
- [ ] `docker ps` — 2 контейнера running (openclaw + browser)
- [ ] `curl -f http://localhost:18789/healthz` — 200 OK
- [ ] Бот отвечает на /start в Telegram
- [ ] `bash monitor.sh` — все проверки OK

## Smoke Test

- [ ] Пройти [tests/MANUAL-SMOKE-CHECKLIST.md](tests/MANUAL-SMOKE-CHECKLIST.md):
  - [ ] Онбординг работает (все 5 фаз)
  - [ ] Голосовые расшифровываются
  - [ ] Файлы обрабатываются
  - [ ] Минимум 5 core-скиллов отвечают корректно
  - [ ] Память сохраняется между сессиями
  - [ ] @mention в группе работает
  - [ ] Бот молчит в группе без @mention

## Documentation

- [ ] docs/ организованы (метки на маркетинговых и planning docs)
- [ ] CONFIG-REFERENCE.md соответствует openclaw.json
- [ ] .env.example содержит все переменные с комментариями

## Ship

```bash
git add -A
git commit -m "release: Kent v1.0.0"
git tag v1.0.0
git push origin main --tags
gh release create v1.0.0 --title "Kent v1.0.0" --notes-file CHANGELOG.md
```
