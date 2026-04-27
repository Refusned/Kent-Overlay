/**
 * k6 load-test для Kent FastAPI gateway.
 *
 * Запуск:
 *   k6 run tests/load-test.js
 *
 * Сценарии (без затрат на LLM API — все провайдеры в mock-режиме):
 *   1. /health             — самый дешёвый health check (Liveness)
 *   2. /skills             — listing (file system + JSON)
 *   3. /version            — статика
 *   4. /llm/providers      — provider registry с проверкой compliance-mode
 *   5. POST /llm/chat      — mock LLM call (yandex provider)
 *   6. POST /memory/store  — pgvector embeddings store (mock OpenAI embedding)
 *   7. GET /memory/search  — pgvector cosine similarity search
 *
 * Цель: замерить p50/p95/p99 latency и RPS gateway без I/O bottleneck'а
 * на сторонние API (для честных метрик чисто FastAPI + Pydantic + psycopg async).
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend } from 'k6/metrics';

const BASE = __ENV.KENT_BASE || 'http://localhost:8000';

// Кастомные метрики на каждый сценарий — для разделения p95 в отчёте.
const m_health     = new Trend('latency_health', true);
const m_skills     = new Trend('latency_skills', true);
const m_version    = new Trend('latency_version', true);
const m_providers  = new Trend('latency_providers', true);
const m_llm_chat   = new Trend('latency_llm_chat', true);
const m_mem_store  = new Trend('latency_memory_store', true);
const m_mem_search = new Trend('latency_memory_search', true);

/**
 * Rate limiter в Kent gateway: 30–120 req/min на endpoint (slowapi sliding window).
 *
 * Этот load-test укладывается в production-friendly нагрузку:
 *   - sustained: 4 VU * 1 cycle/2.5sec = ~1.6 cycles/sec = 11 req/sec суммарно
 *     → ~1.6 req/sec на endpoint = ~96 req/min/endpoint
 *     → ниже большинства лимитов, кроме memory/store (30/min)
 *
 * Для замера латентности под realistic production нагрузкой — этого достаточно.
 * Для stress-теста (показать где gateway падает) — отдельный сценарий ниже.
 */

export const options = {
  scenarios: {
    sustained: {
      executor: 'ramping-vus',
      startVUs: 1,
      stages: [
        { duration: '10s', target: 2 },
        { duration: '60s', target: 4 },   // sustained 4 VU за лимитом 60/min
        { duration: '10s', target: 0 },
      ],
      gracefulRampDown: '5s',
    },
  },
  thresholds: {
    'http_req_duration{endpoint:health}':        ['p(95)<200'],
    'http_req_duration{endpoint:skills}':        ['p(95)<400'],
    'http_req_duration{endpoint:llm_chat}':      ['p(95)<2000'],
    'http_req_duration{endpoint:memory_search}': ['p(95)<500'],
    'http_req_failed':                           ['rate<0.10'],
  },
};

export default function () {
  // 1. /health
  let r = http.get(`${BASE}/health`, { tags: { endpoint: 'health' } });
  check(r, { 'health 200': (x) => x.status === 200 });
  m_health.add(r.timings.duration);

  // 2. /skills
  r = http.get(`${BASE}/skills`, { tags: { endpoint: 'skills' } });
  check(r, { 'skills 200': (x) => x.status === 200 });
  m_skills.add(r.timings.duration);

  // 3. /version
  r = http.get(`${BASE}/version`, { tags: { endpoint: 'version' } });
  check(r, { 'version 200': (x) => x.status === 200 });
  m_version.add(r.timings.duration);

  // 4. /llm/providers
  r = http.get(`${BASE}/llm/providers`, { tags: { endpoint: 'providers' } });
  check(r, { 'providers 200': (x) => x.status === 200 });
  m_providers.add(r.timings.duration);

  // 5. POST /llm/chat (mock provider — без реального API)
  const chatBody = JSON.stringify({
    message: 'load-test sample query',
    provider: 'yandex',
    system: null,
  });
  r = http.post(`${BASE}/llm/chat`, chatBody, {
    headers: { 'Content-Type': 'application/json' },
    tags: { endpoint: 'llm_chat' },
  });
  check(r, { 'llm/chat 200': (x) => x.status === 200 });
  m_llm_chat.add(r.timings.duration);

  // 6. POST /memory/store (pgvector embedding + store)
  const storeBody = JSON.stringify({
    content: `Load-test memory entry at ${Date.now()} by VU ${__VU}`,
    metadata: { source: 'k6', vu: __VU, iter: __ITER },
    namespace: 'loadtest',
  });
  r = http.post(`${BASE}/memory/store`, storeBody, {
    headers: { 'Content-Type': 'application/json' },
    tags: { endpoint: 'memory_store' },
  });
  check(r, { 'memory/store 200/201': (x) => x.status === 200 || x.status === 201 });
  m_mem_store.add(r.timings.duration);

  // 7. GET /memory/search (pgvector cosine similarity)
  r = http.get(
    `${BASE}/memory/search?query=load-test+sample&limit=5&namespace=loadtest`,
    { tags: { endpoint: 'memory_search' } }
  );
  check(r, { 'memory/search 200': (x) => x.status === 200 });
  m_mem_search.add(r.timings.duration);

  // 2.5s pause = ~1 cycle/2.5s/VU → ~24 req/min/endpoint при 1 VU
  // → 96 req/min/endpoint при 4 VU (под большинством лимитов 60–120/min)
  sleep(2.5);
}
