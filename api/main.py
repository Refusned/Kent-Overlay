"""
Kent API Gateway — FastAPI service на Kent overlay.

Предоставляет HTTP API для:
  - Health check (для мониторинга и health-checks в Docker)
  - Информации о боте (версия, статус, метрики)
  - Списка кастомных skills с описаниями
  - Списка интеграций
  - Базовых метрик (uptime, версия, деплой)

Swagger UI доступен по адресу: GET /docs
ReDoc:                         GET /redoc
OpenAPI schema (JSON):         GET /openapi.json

Запуск локально:
    uvicorn main:app --host 0.0.0.0 --port 8000 --reload

Запуск в продакшене (через Docker):
    uvicorn main:app --host 0.0.0.0 --port 8000 --workers 2
"""

import os
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field


# ═══════════════════════════════════════════════════════════════
#  Конфигурация
# ═══════════════════════════════════════════════════════════════

# Путь к workspace внутри контейнера. В docker-compose.yml монтируется
# `../workspace:/root/.openclaw/workspace`, так что путь стабильный.
WORKSPACE_PATH = Path(os.environ.get(
    "KENT_WORKSPACE_PATH",
    "/root/.openclaw/workspace"
))

# Стартовое время сервиса — для расчёта uptime.
START_TIME = time.time()

# Версия API — читаем из переменной окружения (передаётся через Dockerfile)
# или дефолт.
KENT_VERSION = os.environ.get("KENT_VERSION", "1.0.0")


# ═══════════════════════════════════════════════════════════════
#  Pydantic-схемы (описание формата ответов)
# ═══════════════════════════════════════════════════════════════

class HealthResponse(BaseModel):
    """Ответ health-check endpoint."""
    status: str = Field(..., description="'ok' если сервис работает")
    timestamp: str = Field(..., description="Текущее время в ISO 8601 (UTC)")


class InfoResponse(BaseModel):
    """Информация о боте."""
    name: str = Field(..., description="Имя продукта")
    version: str = Field(..., description="Версия Kent")
    description: str = Field(..., description="Описание продукта")
    docs_url: str = Field(..., description="URL Swagger UI")
    repo_url: str = Field(..., description="GitHub-репозиторий")


class Skill(BaseModel):
    """Описание одного skill'а."""
    name: str = Field(..., description="Идентификатор skill'а (имя папки)")
    title: Optional[str] = Field(None, description="Человекочитаемое название")
    description: Optional[str] = Field(None, description="Краткое описание")
    has_skill_md: bool = Field(..., description="Есть ли SKILL.md")


class SkillsResponse(BaseModel):
    """Список всех skills."""
    count: int = Field(..., description="Общее количество skills")
    skills: list[Skill] = Field(..., description="Массив skills")


class Integration(BaseModel):
    """Описание одной интеграции."""
    name: str
    category: str
    requires_auth: bool


class IntegrationsResponse(BaseModel):
    """Список интеграций."""
    count: int
    integrations: list[Integration]


class MetricsResponse(BaseModel):
    """Базовые метрики сервиса."""
    uptime_seconds: float = Field(..., description="Сколько секунд работает API")
    started_at: str = Field(..., description="Время старта (ISO 8601)")
    version: str
    skills_total: int
    integrations_total: int


# ═══════════════════════════════════════════════════════════════
#  Каталог интеграций (статический — из CHANGELOG/README)
# ═══════════════════════════════════════════════════════════════

INTEGRATIONS_CATALOG: list[Integration] = [
    # Messaging
    Integration(name="Telegram Bot API", category="messaging", requires_auth=True),
    # AI / LLM
    Integration(name="Anthropic Claude", category="llm", requires_auth=True),
    Integration(name="OpenAI GPT-4o", category="llm", requires_auth=True),
    Integration(name="DeepSeek", category="llm", requires_auth=True),
    Integration(name="Google Gemini", category="llm", requires_auth=True),
    Integration(name="DALL-E 3", category="image-gen", requires_auth=True),
    Integration(name="Whisper", category="stt", requires_auth=False),
    Integration(name="ElevenLabs", category="tts", requires_auth=True),
    # Productivity
    Integration(name="Gmail", category="productivity", requires_auth=True),
    Integration(name="Google Calendar", category="productivity", requires_auth=True),
    Integration(name="Google Drive", category="productivity", requires_auth=True),
    Integration(name="Google Sheets", category="productivity", requires_auth=True),
    Integration(name="Google Contacts", category="productivity", requires_auth=True),
    # Search & web
    Integration(name="Tavily Search", category="search", requires_auth=True),
    Integration(name="Playwright Browser", category="web-automation", requires_auth=False),
    # Social
    Integration(name="Twitter/X API", category="social", requires_auth=True),
    # IoT
    Integration(name="Yandex Smart Home", category="iot", requires_auth=True),
    # Commerce
    Integration(name="ЮKassa", category="payments", requires_auth=True),
    Integration(name="Wildberries Seller API", category="ecommerce", requires_auth=True),
    # Documents
    Integration(name="python-pptx (PowerPoint)", category="documents", requires_auth=False),
    Integration(name="python-docx (Word)", category="documents", requires_auth=False),
    Integration(name="reportlab (PDF)", category="documents", requires_auth=False),
    Integration(name="openpyxl (Excel)", category="documents", requires_auth=False),
    Integration(name="pdfplumber (PDF parsing)", category="documents", requires_auth=False),
    # Misc
    Integration(name="wttr.in (weather)", category="misc", requires_auth=False),
    Integration(name="yt-dlp (YouTube)", category="misc", requires_auth=False),
    Integration(name="faster-whisper (local STT)", category="stt", requires_auth=False),
    Integration(name="agent-browser (web search)", category="search", requires_auth=False),
]


# ═══════════════════════════════════════════════════════════════
#  Helpers — чтение skills из файловой системы
# ═══════════════════════════════════════════════════════════════

def _parse_skill_md(skill_dir: Path) -> Skill:
    """
    Прочитать SKILL.md из папки skill'а и извлечь title + description.

    Формат SKILL.md (frontmatter + markdown):

        ---
        name: humanize
        description: Перепиши AI-текст под живого человека
        ---

        # Skill content...
    """
    skill_md = skill_dir / "SKILL.md"

    if not skill_md.exists():
        return Skill(
            name=skill_dir.name,
            title=None,
            description=None,
            has_skill_md=False,
        )

    title: Optional[str] = None
    description: Optional[str] = None

    try:
        content = skill_md.read_text(encoding="utf-8")
        # Простая парсилка YAML-frontmatter (без yaml-зависимости)
        if content.startswith("---"):
            end = content.find("---", 3)
            if end > 0:
                frontmatter = content[3:end]
                for line in frontmatter.splitlines():
                    line = line.strip()
                    if line.startswith("name:"):
                        title = line.split(":", 1)[1].strip().strip('"').strip("'")
                    elif line.startswith("description:"):
                        description = line.split(":", 1)[1].strip().strip('"').strip("'")
    except (OSError, UnicodeDecodeError):
        pass

    return Skill(
        name=skill_dir.name,
        title=title or skill_dir.name,
        description=description,
        has_skill_md=True,
    )


def _list_skills() -> list[Skill]:
    """Просканировать workspace/skills/ и вернуть список всех skills."""
    skills_dir = WORKSPACE_PATH / "skills"

    if not skills_dir.exists() or not skills_dir.is_dir():
        return []

    return sorted(
        (_parse_skill_md(d) for d in skills_dir.iterdir() if d.is_dir()),
        key=lambda s: s.name,
    )


# ═══════════════════════════════════════════════════════════════
#  FastAPI приложение
# ═══════════════════════════════════════════════════════════════

app = FastAPI(
    title="Kent AI Assistant API",
    description=(
        "Управляющий API для Kent — production-ready AI-ассистента в Telegram. "
        "Позволяет посмотреть доступные skills, интеграции и метрики работы."
    ),
    version=KENT_VERSION,
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
)

# CORS middleware — разрешаем запросы с любых доменов.
# В проде имеет смысл указать конкретные allowed_origins.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)


# ═══════════════════════════════════════════════════════════════
#  Endpoints
# ═══════════════════════════════════════════════════════════════

@app.get(
    "/health",
    response_model=HealthResponse,
    tags=["system"],
    summary="Health check",
)
async def health() -> HealthResponse:
    """
    Health-check endpoint.

    Используется Docker healthcheck'ом и системами мониторинга
    (Prometheus, Grafana, UptimeRobot и т.д.).
    """
    return HealthResponse(
        status="ok",
        timestamp=datetime.now(timezone.utc).isoformat(),
    )


@app.get(
    "/",
    response_model=InfoResponse,
    tags=["system"],
    summary="Информация о Kent",
)
async def info() -> InfoResponse:
    """Базовая информация о продукте Kent."""
    return InfoResponse(
        name="Kent AI Assistant",
        version=KENT_VERSION,
        description=(
            "Production-ready AI-ассистент в Telegram на платформе OpenClaw. "
            "17+ кастомных skills, 28 интеграций, hardened Docker-деплой."
        ),
        docs_url="/docs",
        repo_url="https://github.com/Refusned/Kent-Overlay",
    )


@app.get(
    "/skills",
    response_model=SkillsResponse,
    tags=["catalog"],
    summary="Список доступных skills",
)
async def skills() -> SkillsResponse:
    """
    Вернуть список всех кастомных skills, найденных в workspace/skills/.

    Каждый skill — это папка с SKILL.md внутри. API сам парсит SKILL.md
    и возвращает имя + описание из frontmatter.
    """
    skill_list = _list_skills()
    return SkillsResponse(
        count=len(skill_list),
        skills=skill_list,
    )


@app.get(
    "/skills/{skill_name}",
    response_model=Skill,
    tags=["catalog"],
    summary="Подробности об одном skill'е",
)
async def skill_detail(skill_name: str) -> Skill:
    """Получить информацию о конкретном skill'е по имени."""
    skill_dir = WORKSPACE_PATH / "skills" / skill_name

    if not skill_dir.exists() or not skill_dir.is_dir():
        raise HTTPException(
            status_code=404,
            detail=f"Skill '{skill_name}' не найден",
        )

    return _parse_skill_md(skill_dir)


@app.get(
    "/integrations",
    response_model=IntegrationsResponse,
    tags=["catalog"],
    summary="Список интеграций",
)
async def integrations() -> IntegrationsResponse:
    """Вернуть список всех интеграций, доступных у Kent."""
    return IntegrationsResponse(
        count=len(INTEGRATIONS_CATALOG),
        integrations=INTEGRATIONS_CATALOG,
    )


@app.get(
    "/metrics",
    response_model=MetricsResponse,
    tags=["system"],
    summary="Базовые метрики сервиса",
)
async def metrics() -> MetricsResponse:
    """
    Базовые runtime-метрики Kent API.

    Для подробных метрик (latency, error rate, token usage) рекомендуется
    подключить Langfuse или Prometheus exporter.
    """
    started_at = datetime.fromtimestamp(START_TIME, timezone.utc).isoformat()
    return MetricsResponse(
        uptime_seconds=time.time() - START_TIME,
        started_at=started_at,
        version=KENT_VERSION,
        skills_total=len(_list_skills()),
        integrations_total=len(INTEGRATIONS_CATALOG),
    )
