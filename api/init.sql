-- ═══════════════════════════════════════════════════════════════
--  Kent — PostgreSQL init script
--  Создаёт расширение pgvector и таблицу для RAG-памяти
--
--  Выполняется автоматически при первом запуске контейнера postgres
--  (docker-entrypoint-initdb.d/*.sql)
-- ═══════════════════════════════════════════════════════════════

-- Расширение pgvector — добавляет тип vector(N) и оператор поиска ближайших <->
CREATE EXTENSION IF NOT EXISTS vector;

-- ───────────────────────────────────────────────────────────────
--  Таблица embeddings — основное хранилище RAG-памяти
--
--  Каждая запись = кусок текста + его embedding (1536-мерный вектор
--  от OpenAI text-embedding-3-small) + метаданные.
-- ───────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS embeddings (
    id          BIGSERIAL PRIMARY KEY,
    namespace   TEXT NOT NULL DEFAULT 'default',  -- разделение по контекстам (user, agent, etc.)
    content     TEXT NOT NULL,                     -- исходный текст
    embedding   vector(1536),                      -- OpenAI text-embedding-3-small dimension
    metadata    JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ───────────────────────────────────────────────────────────────
--  Индексы для быстрого поиска
-- ───────────────────────────────────────────────────────────────

-- HNSW-индекс для быстрого ANN-поиска (Approximate Nearest Neighbor).
-- Лучше IVF для большинства случаев — быстрее на запросах.
-- vector_cosine_ops — используем cosine similarity (стандарт для текстовых embeddings).
CREATE INDEX IF NOT EXISTS embeddings_hnsw_idx
    ON embeddings
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);

-- Индекс по namespace для фильтрации (например, "только память пользователя X")
CREATE INDEX IF NOT EXISTS embeddings_namespace_idx
    ON embeddings (namespace);

-- Индекс по дате создания для retention-политик
CREATE INDEX IF NOT EXISTS embeddings_created_at_idx
    ON embeddings (created_at DESC);

-- ───────────────────────────────────────────────────────────────
--  Грантим права пользователю kent
-- ───────────────────────────────────────────────────────────────

GRANT SELECT, INSERT, UPDATE, DELETE ON embeddings TO kent;
GRANT USAGE, SELECT ON SEQUENCE embeddings_id_seq TO kent;
