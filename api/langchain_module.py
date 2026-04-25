"""
LangChain + LangGraph модуль для Kent API.

Демонстрация работы со стандартным AI-стеком (LangChain/LangGraph) —
параллельно к ручной реализации в main.py через psycopg + pgvector.

Цель:
  - Показать что используем индустриальный стандарт, а не велосипед
  - Дать пример RAG через LangChain PGVector
  - Дать пример простого Chain (PromptTemplate + LLM)
  - Дать пример LangGraph workflow с условным ветвлением

Если OPENAI_API_KEY не задан — используется mock LLM (предсказуемые ответы).
"""

import os
import random
from typing import Any, Optional, TypedDict

# LangChain core
from langchain_core.language_models.fake_chat_models import FakeListChatModel
from langchain_core.messages import AIMessage, HumanMessage
from langchain_core.output_parsers import StrOutputParser
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.runnables import Runnable

# LangChain providers
try:
    from langchain_openai import ChatOpenAI, OpenAIEmbeddings
    HAS_OPENAI = True
except ImportError:
    HAS_OPENAI = False

# LangChain vector store
from langchain_postgres import PGVector
from langchain_postgres.vectorstores import PGVector as PGVectorStore
from sqlalchemy.ext.asyncio import create_async_engine

# LangGraph
from langgraph.graph import END, START, StateGraph


# ═══════════════════════════════════════════════════════════════
#  Configuration
# ═══════════════════════════════════════════════════════════════

OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "")
KENT_DB_HOST = os.environ.get("KENT_DB_HOST", "postgres")
KENT_DB_PORT = os.environ.get("KENT_DB_PORT", "5432")
KENT_DB_USER = os.environ.get("KENT_DB_USER", "kent")
KENT_DB_PASSWORD = os.environ.get("KENT_DB_PASSWORD", "kent_dev_password")
KENT_DB_NAME = os.environ.get("KENT_DB_NAME", "kent")

# Async-совместимый DSN для langchain-postgres
DB_CONNECTION_STRING = (
    f"postgresql+psycopg://{KENT_DB_USER}:{KENT_DB_PASSWORD}"
    f"@{KENT_DB_HOST}:{KENT_DB_PORT}/{KENT_DB_NAME}"
)

LANGCHAIN_COLLECTION_NAME = "kent_langchain_demo"


# ═══════════════════════════════════════════════════════════════
#  LLM & Embeddings — с fallback на mock
# ═══════════════════════════════════════════════════════════════

def _get_chat_llm() -> Runnable:
    """Получить LLM: ChatOpenAI если есть key, иначе FakeListChatModel."""
    if HAS_OPENAI and OPENAI_API_KEY:
        return ChatOpenAI(
            model="gpt-4o-mini",
            api_key=OPENAI_API_KEY,
            temperature=0.7,
        )
    # Mock: предсказуемые ответы для demo
    return FakeListChatModel(
        responses=[
            "Это mock-ответ от FakeListChatModel. Чтобы получить реальный ответ от LLM, задай OPENAI_API_KEY.",
            "Привет! Я Kent в режиме mock. Реальный LLM требует OPENAI_API_KEY в env.",
            "Понял твой запрос. Mock LLM не имеет реального понимания, но pipeline работает.",
        ]
    )


class _MockEmbeddings:
    """
    Минимальный embeddings-класс для случая когда нет OPENAI_API_KEY.

    Использует hash-based детерминированный mock — результаты не отражают
    смысл, но pipeline работает и поиск можно протестировать.
    """

    @staticmethod
    def _embed_one(text: str) -> list[float]:
        import hashlib
        rng = random.Random(hashlib.sha256(text.encode("utf-8")).digest())
        vec = [rng.uniform(-1.0, 1.0) for _ in range(1536)]
        norm = sum(v * v for v in vec) ** 0.5
        return [v / norm for v in vec] if norm > 0 else vec

    def embed_documents(self, texts: list[str]) -> list[list[float]]:
        return [self._embed_one(t) for t in texts]

    def embed_query(self, text: str) -> list[float]:
        return self._embed_one(text)

    async def aembed_documents(self, texts: list[str]) -> list[list[float]]:
        return self.embed_documents(texts)

    async def aembed_query(self, text: str) -> list[float]:
        return self.embed_query(text)


def _get_embeddings():
    """Получить embeddings: OpenAI если есть key, иначе mock."""
    if HAS_OPENAI and OPENAI_API_KEY:
        return OpenAIEmbeddings(
            model="text-embedding-3-small",
            api_key=OPENAI_API_KEY,
        )
    return _MockEmbeddings()


# ═══════════════════════════════════════════════════════════════
#  Vectorstore — LangChain PGVector
# ═══════════════════════════════════════════════════════════════

_vectorstore_cache: Optional[PGVectorStore] = None
_async_engine_cache = None


def _get_vectorstore() -> PGVectorStore:
    """Lazy-инициализация PGVector connection с async engine."""
    global _vectorstore_cache, _async_engine_cache
    if _vectorstore_cache is None:
        _async_engine_cache = create_async_engine(DB_CONNECTION_STRING)
        _vectorstore_cache = PGVector(
            embeddings=_get_embeddings(),
            collection_name=LANGCHAIN_COLLECTION_NAME,
            connection=_async_engine_cache,  # передаём AsyncEngine для async операций
            use_jsonb=True,
            async_mode=True,
        )
    return _vectorstore_cache


# ═══════════════════════════════════════════════════════════════
#  1. Простой Chain — PromptTemplate + LLM + OutputParser
# ═══════════════════════════════════════════════════════════════

def build_simple_chain() -> Runnable:
    """
    Построить простую LangChain цепочку:

        prompt template → chat LLM → string parser

    Демонстрирует базовый Composability LangChain через `|` оператор (LCEL).
    """
    prompt = ChatPromptTemplate.from_messages([
        ("system", "Ты — деловой ассистент Kent. Отвечай кратко и по делу."),
        ("human", "{question}"),
    ])
    llm = _get_chat_llm()
    parser = StrOutputParser()
    return prompt | llm | parser


async def run_simple_chain(question: str) -> str:
    """Запустить простую chain и вернуть строковый ответ."""
    chain = build_simple_chain()
    return await chain.ainvoke({"question": question})


# ═══════════════════════════════════════════════════════════════
#  2. RAG через LangChain PGVector
# ═══════════════════════════════════════════════════════════════

async def langchain_rag_add(text: str, metadata: Optional[dict] = None) -> str:
    """Добавить документ в LangChain PGVector collection."""
    vs = _get_vectorstore()
    ids = await vs.aadd_texts([text], metadatas=[metadata or {}])
    return ids[0] if ids else ""


async def langchain_rag_search(query: str, k: int = 5) -> list[dict]:
    """
    Поиск через LangChain PGVector similarity_search.

    Возвращает [{content, metadata, score}, ...].
    Score — близость по cosine; чем меньше, тем ближе.
    """
    vs = _get_vectorstore()
    results = await vs.asimilarity_search_with_score(query, k=k)
    return [
        {
            "content": doc.page_content,
            "metadata": doc.metadata,
            "score": float(score),
        }
        for doc, score in results
    ]


# ═══════════════════════════════════════════════════════════════
#  3. LangGraph workflow — условное ветвление
# ═══════════════════════════════════════════════════════════════

class WorkflowState(TypedDict):
    """Состояние LangGraph workflow."""
    user_input: str
    intent: str               # классификация: 'question' / 'command' / 'greeting'
    response: str
    used_rag: bool


def _classify_intent(state: WorkflowState) -> WorkflowState:
    """Узел: классифицировать намерение пользователя по простым правилам."""
    text = state["user_input"].lower().strip()
    if any(g in text for g in ["привет", "здарова", "hi", "hello"]):
        intent = "greeting"
    elif any(text.endswith(q) for q in ["?", " ?"]):
        intent = "question"
    elif any(text.startswith(c) for c in ["сделай", "создай", "напиши", "найди"]):
        intent = "command"
    else:
        intent = "question"  # default

    return {**state, "intent": intent}


async def _handle_greeting(state: WorkflowState) -> WorkflowState:
    """Узел: ответить на приветствие."""
    return {
        **state,
        "response": "Привет! Я Kent — твой AI-ассистент. Чем могу помочь?",
        "used_rag": False,
    }


async def _handle_command(state: WorkflowState) -> WorkflowState:
    """Узел: команды идут через LLM напрямую без RAG."""
    chain = build_simple_chain()
    response = await chain.ainvoke({"question": state["user_input"]})
    return {**state, "response": response, "used_rag": False}


async def _handle_question(state: WorkflowState) -> WorkflowState:
    """Узел: вопросы — обогащаем контекстом из RAG, потом отдаём в LLM."""
    # Достанем релевантные документы
    docs = await langchain_rag_search(state["user_input"], k=3)
    context = "\n".join(f"- {d['content']}" for d in docs) if docs else "(память пуста)"

    # Промпт с RAG-контекстом
    prompt = ChatPromptTemplate.from_messages([
        ("system", "Ты — Kent. Используй приведённый контекст для ответа.\n\nКонтекст:\n{context}"),
        ("human", "{question}"),
    ])
    chain = prompt | _get_chat_llm() | StrOutputParser()
    response = await chain.ainvoke({"context": context, "question": state["user_input"]})

    return {**state, "response": response, "used_rag": True}


def _route_by_intent(state: WorkflowState) -> str:
    """Conditional edge: направить state в нужный handler по intent."""
    return state["intent"]


def build_workflow_graph():
    """
    Построить LangGraph workflow:

        START → classify_intent → [routing] → handle_greeting | handle_question | handle_command → END

    Демонстрирует условное ветвление и stateful workflow.
    """
    graph = StateGraph(WorkflowState)

    # Узлы
    graph.add_node("classify_intent", _classify_intent)
    graph.add_node("handle_greeting", _handle_greeting)
    graph.add_node("handle_question", _handle_question)
    graph.add_node("handle_command", _handle_command)

    # Граф: START → classify_intent
    graph.add_edge(START, "classify_intent")

    # Условное ветвление по intent
    graph.add_conditional_edges(
        "classify_intent",
        _route_by_intent,
        {
            "greeting": "handle_greeting",
            "question": "handle_question",
            "command": "handle_command",
        },
    )

    # Все handler'ы → END
    graph.add_edge("handle_greeting", END)
    graph.add_edge("handle_question", END)
    graph.add_edge("handle_command", END)

    return graph.compile()


async def run_workflow(user_input: str) -> dict:
    """Запустить LangGraph workflow и вернуть финальный state."""
    workflow = build_workflow_graph()
    initial_state: WorkflowState = {
        "user_input": user_input,
        "intent": "",
        "response": "",
        "used_rag": False,
    }
    final_state = await workflow.ainvoke(initial_state)
    return dict(final_state)


# ═══════════════════════════════════════════════════════════════
#  Info — для /langchain/info endpoint
# ═══════════════════════════════════════════════════════════════

def get_info() -> dict:
    """Информация о LangChain components используемых в Kent."""
    from importlib.metadata import PackageNotFoundError, version

    def _safe_version(pkg: str) -> str:
        try:
            return version(pkg)
        except PackageNotFoundError:
            return "unknown"

    using_real_openai = bool(OPENAI_API_KEY and HAS_OPENAI)

    return {
        "langchain_version": _safe_version("langchain"),
        "langgraph_version": _safe_version("langgraph"),
        "llm_provider": "openai (gpt-4o-mini)" if using_real_openai else "mock (FakeListChatModel)",
        "embeddings_provider": "openai (text-embedding-3-small)" if using_real_openai else "mock (hash-based)",
        "vectorstore": "langchain-postgres PGVector",
        "vectorstore_collection": LANGCHAIN_COLLECTION_NAME,
        "components_demonstrated": [
            "ChatPromptTemplate",
            "ChatOpenAI / FakeListChatModel",
            "OpenAIEmbeddings / mock",
            "PGVector vectorstore",
            "LCEL pipeline (prompt | llm | parser)",
            "LangGraph StateGraph with conditional routing",
        ],
    }
