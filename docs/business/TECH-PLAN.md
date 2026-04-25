# Kent — Техническая реализация
## Три варианта: от MVP за выходные до масштабируемого бизнеса

---

## ВАРИАНТ 1: «Ручной MVP» — запуск за 1-2 дня, 0₽ стартовых вложений

### Суть
Ты сам разворачиваешь OpenClaw на VPS клиента, настраиваешь Telegram, берёшь оплату переводом на карту. Никакой автоматизации — чистый ручной труд. Цель: **проверить спрос и собрать первые 5-10 клиентов**.

### Стек
```
[Клиент] → пишет тебе в Telegram
    ↓
[Ты] → покупаешь VPS → разворачиваешь OpenClaw → настраиваешь → отдаёшь клиенту
    ↓
[Клиент] → пишет своему Kent-боту в Telegram → OpenClaw отвечает
```

### Шаги запуска

**День 1: Подготовка**

1. Купить VPS для демо-инстанса:
   - **Aéza** или **4VPS** (оплата в рублях, от 300₽/мес за 2 vCPU / 4GB RAM)
   - Ubuntu 24.04, локация — Москва или Амстердам

2. Развернуть OpenClaw через Docker:
```bash
ssh root@YOUR_IP

# Установка Docker
curl -fsSL https://get.docker.com | sh

# Клонирование и деплой OpenClaw
git clone https://github.com/openclaw/openclaw.git /opt/openclaw
cd /opt/openclaw
export OPENCLAW_IMAGE="ghcr.io/openclaw/openclaw:latest"
./scripts/docker/setup.sh
```

3. Подключить Telegram:
   - Создать бота через @BotFather
   - Подключить канал в OpenClaw
   - Настроить русскоязычную персону (SOUL.md)

4. Настроить бесплатные модели:
   - DeepSeek API (бесплатный tier, русский язык отлично)
   - Gemini Flash (бесплатный tier от Google)
   - Клиент начинает без API-ключей Anthropic/OpenAI

**День 2: Продажи**

5. Лендинг — Tilda, Carrd, или Next.js на Vercel (уже проектируешь)

6. Оплата — перевод на карту, далее ЮKassa

### Экономика
| Статья | Расход |
|--------|--------|
| VPS на клиента (Aéza/4VPS) | 300-600₽/мес |
| API (DeepSeek/Gemini бесплатный tier) | 0₽ |
| **Себестоимость** | **~500₽/мес** |
| **Цена для клиента** | **1 990₽/мес** |
| **Маржа** | **~1 500₽ (75%)** |

### Плюсы и минусы
✅ Запуск за 1-2 дня, 0₽ начальных вложений
✅ Проверяешь спрос реальными деньгами

❌ Не масштабируется (max 10-15 клиентов)
❌ Всё руками, нет dashboard

---

## ВАРИАНТ 2: «Полуавтомат» — запуск за 1-2 недели, ~5 000₽

### Суть
Скрипт автодеплоя + ЮKassa + мониторинг. Клиент оплачивает → бот разворачивается полуавтоматически. **Цель: 20-100 клиентов.**

### Архитектура
```
[Лендинг Next.js] → [ЮKassa] → [Webhook]
                                    ↓
                          [Скрипт автодеплоя]
                                    ↓
                    [API VPS-провайдера (Aéza)]
                          ↓              ↓
                  [Создаёт VPS]  [Деплоит OpenClaw]
                                    ↓
                  [Telegram: "Ваш Kent готов! @bot"]
```

### Ключевой скрипт автодеплоя

```bash
#!/bin/bash
# kent-deploy.sh

CLIENT_NAME=$1
TELEGRAM_TOKEN=$2

# 1. Создать VPS через API Aéza
VPS_IP=$(curl -s -X POST "https://api.aeza.net/v1/servers" \
  -H "Authorization: Bearer $AEZA_TOKEN" \
  -d '{"name":"kent-'$CLIENT_NAME'","plan":"start-2","os":"ubuntu-24-04","location":"msk"}' \
  | jq -r '.server.ip')

sleep 60

# 2. Развернуть OpenClaw
ssh root@$VPS_IP << 'REMOTE'
  curl -fsSL https://get.docker.com | sh
  git clone https://github.com/openclaw/openclaw.git /opt/openclaw
  cd /opt/openclaw
  export OPENCLAW_IMAGE="ghcr.io/openclaw/openclaw:latest"
  ./scripts/docker/setup.sh --unattended

  # Русская персона
  cat > ~/.openclaw/workspace/SOUL.md << 'SOUL'
# Kent — Твой AI-ассистент
Ты — Kent, дружелюбный AI-ассистент. Отвечай на русском.
Помогай с задачами, автоматизируй рутину, давай полезные ответы.
SOUL
REMOTE

echo "✅ Kent для $CLIENT_NAME готов: $VPS_IP"
```

### Мониторинг (cron каждые 5 минут)

```bash
#!/bin/bash
# kent-monitor.sh
while IFS=',' read -r name ip; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://$ip:18789" --max-time 5)
  if [ "$STATUS" != "200" ]; then
    curl -s "https://api.telegram.org/bot$ADMIN_BOT/sendMessage" \
      -d "chat_id=$ADMIN_CHAT" \
      -d "text=⚠️ Kent $name ($ip) недоступен!"
    ssh root@$ip "cd /opt/openclaw && docker compose restart" 2>/dev/null
  fi
done < /opt/kent/clients.csv
```

### Что добавляется к Варианту 1
- Автодеплой за 5 мин вместо 30
- ЮKassa для автоматических платежей
- Мониторинг + авто-перезапуск
- Шаблонные конфиги

### Экономика при 50 клиентах
| Статья | Расход |
|--------|--------|
| VPS на клиента | 300-600₽/мес |
| Управляющий сервер | 300₽/мес |
| ЮKassa (3.5%) | ~70₽/клиент |
| **Себестоимость** | **~700₽/мес** |
| **Цена** | **1 990-2 490₽/мес** |
| **Маржа × 50 клиентов** | **~65 000-90 000₽/мес** |

---

## ВАРИАНТ 3: «Платформа» — 1-2 месяца, ~30 000-50 000₽

### Суть
SaaS с клиентским кабинетом, автопровижнингом, биллингом. **Цель: 100-1000+ клиентов.**

### Архитектура

```
┌──────────────────────────────────────────────┐
│              KENT PLATFORM                    │
├──────────────────────────────────────────────┤
│                                               │
│  [Next.js Frontend + Dashboard]               │
│       ↕                                       │
│  [API Backend (Node.js / FastAPI)]            │
│       ↕            ↕            ↕             │
│  [PostgreSQL]  [ЮKassa]  [Provisioner]        │
│                              ↓                │
│                   [VPS Provider API]           │
│                   (Aéza / Timeweb)             │
│                        ↓                      │
│              ┌─────────────────┐              │
│              │ VPS клиента #1  │              │
│              │ Docker+OpenClaw │              │
│              │ @kent_bot_001   │              │
│              └─────────────────┘              │
│              ┌─────────────────┐              │
│              │ VPS клиента #2  │              │
│              └─────────────────┘              │
│                     ...                       │
│                                               │
│  [Uptime Kuma] — мониторинг всех VPS         │
│  [GitHub Actions] — автообновления OpenClaw   │
│  [Cron] — ежедневные бэкапы workspace        │
└──────────────────────────────────────────────┘
```

### Стек

| Компонент | Технология | Стоимость |
|-----------|-----------|-----------|
| Frontend + Dashboard | Next.js 14, Tailwind, Vercel | 0₽ (free tier) |
| Backend API | Node.js (Fastify) или Python (FastAPI) | На управл. сервере |
| БД | PostgreSQL (Supabase / Neon free) | 0₽ |
| Биллинг | ЮKassa API + рекуррентные платежи | 3.5% комиссия |
| Провижнинг | API Aéza / Timeweb Cloud | В составе VPS |
| Мониторинг | Uptime Kuma (self-hosted) | 0₽ |
| Email | Resend.com (3000/мес бесплатно) | 0₽ |
| CI/CD | GitHub Actions | 0₽ |

### Клиентский кабинет

```
/dashboard
├── Статус бота (онлайн/оффлайн, uptime %)
├── Каналы (Telegram ✅, WhatsApp ⏳)
├── Метрики (сообщений сегодня, токены, стоимость)
├── Настройки персоны (редактор SOUL.md)
├── КентБайтс — рецепты автоматизаций
│   ├── Мониторинг цен WB
│   ├── Саммари Telegram-каналов
│   ├── Email-триаж
│   └── Автоответы WhatsApp
├── API-ключи (BYOK или бесплатные)
├── Логи (последние 100 сообщений)
└── Тариф и оплата
```

### Автоматический провижнинг

```javascript
// provision.js
async function provisionClient(client) {
  // 1. Создать VPS через API провайдера
  const vps = await aezaAPI.createServer({
    name: `kent-${client.id}`,
    plan: client.plan === 'start' ? 'vps-s' : 'vps-m',
    os: 'ubuntu-24.04',
    location: 'msk',
    sshKey: KENT_SSH_KEY_ID
  });

  await waitForServer(vps.id);

  // 2. Развернуть OpenClaw через SSH
  await sshExec(vps.ip, [
    'curl -fsSL https://get.docker.com | sh',
    'git clone https://github.com/openclaw/openclaw.git /opt/openclaw',
    'cd /opt/openclaw && OPENCLAW_IMAGE=ghcr.io/openclaw/openclaw:latest ./scripts/docker/setup.sh --unattended'
  ]);

  // 3. Telegram + персона + модель
  await configureTelegram(vps.ip, client.botToken);
  await uploadSoulFile(vps.ip, client.persona || DEFAULT_RU_PERSONA);
  await configureModel(vps.ip,
    client.plan === 'start' ? 'deepseek' : client.aiProvider,
    client.plan === 'start' ? DEEPSEEK_FREE_KEY : client.apiKey
  );

  // 4. Мониторинг + БД + уведомление
  await monitoring.addTarget(vps.ip, client.id);
  await db.clients.update(client.id, { status: 'active', vpsIp: vps.ip });
  await sendTelegram(client.telegramId,
    '🎉 Ваш Kent готов! Напишите @' + client.botName
  );
}
```

### Экономика при 200 клиентах

| Статья | Расход |
|--------|--------|
| VPS на клиента | 300-600₽/мес |
| Управляющий сервер | 600₽/мес |
| DeepSeek для бесплатных | ~200₽/мес (на всех) |
| **Себестоимость на клиента** | **~600-800₽/мес** |
| **Средний чек** | **2 500₽/мес** |
| **Маржа × 200** | **~340 000₽/мес** |

---

## ВЫБОР VPS-ПРОВАЙДЕРА ДЛЯ КЛИЕНТСКИХ СЕРВЕРОВ

| Провайдер | Цена от | API | Оплата | Рекомендация |
|-----------|---------|-----|--------|--------------|
| **Aéza** | 300₽ | ✅ REST API | Рубли, СБП, крипта | **Лучший старт** — API, дёшево, Anti-DDoS |
| **Timeweb Cloud** | 299₽ | ✅ API + Terraform | Рубли, карты | **Масштаб 50+** — Terraform, почасовая оплата |
| **4VPS** | 80₽ | ✅ API | Рубли | **Самый дешёвый** — для тарифа «Старт» |
| **Selectel** | 983₽ | ✅ API | Безнал | **Enterprise** — Tier III, SLA |
| **RUVDS** | 150₽ | ❌ | Рубли, крипта | 21 город РФ, хороший пинг |

---

## РЕКОМЕНДОВАННЫЙ ПУТЬ

```
НЕДЕЛЯ 1   →  Вариант 1 (ручной MVP)
               Развернуть демо, записать видео, найти 3-5 клиентов

НЕДЕЛЯ 2-3 →  Вариант 2 (полуавтомат)
               Скрипт деплоя, ЮKassa, лендинг, 10-20 клиентов

МЕСЯЦ 2-3  →  Вариант 3 (только если 30+ клиентов)
               Dashboard, автопровижнинг, масштабирование

МЕСЯЦ 4+   →  Рост
               SEO-блог, КентБайтс, enterprise, партнёрка
```

## ПЕРВЫЕ ПРОДАЖИ — ГДЕ ИСКАТЬ КЛИЕНТОВ

1. **Telegram-каналы про AI** — пост "Как я сделал AI-помощника в Telegram за 5 минут"
2. **vc.ru / Habr** — статья "OpenClaw для бизнеса: гайд на русском"
3. **YouTube Shorts** — демо "Мой бот мониторит цены на WB"
4. **Avito / Kwork** — услуга "Настройка AI-ассистента под ключ"
5. **Telegram-чаты предпринимателей** — бесплатный 7-дневный trial

## ЧЕКЛИСТ ПЕРЕД ЗАПУСКОМ

- [ ] Демо-бот Kent работает в Telegram
- [ ] Отвечает на русском языке
- [ ] Подключена бесплатная модель (DeepSeek / Gemini Flash)
- [ ] Есть 1 готовый рецепт (мониторинг WB)
- [ ] Лендинг с ценами
- [ ] Способ оплаты (хотя бы перевод на карту)
- [ ] Telegram-канал @kent_ai
- [ ] 1 видео-демо (2-3 мин скринкаст)
