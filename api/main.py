"""
Kent API Gateway — FastAPI service на Kent overlay.

Предоставляет HTTP API для:
  - Health check (для мониторинга и health-checks в Docker)
  - Информации о боте (версия, статус, метрики)
  - Списка кастомных skills с описаниями
  - Списка интеграций
  - Каталога KentBytes (рецепты по категориям)
  - Базовых метрик (uptime, версия, деплой)
  - Proxy-статуса OpenClaw (живой ли бот)
  - Безопасного просмотра конфига (без секретов)

Swagger UI:                    GET /docs
ReDoc:                         GET /redoc
OpenAPI schema (JSON):         GET /openapi.json

Запуск локально:
    uvicorn main:app --host 0.0.0.0 --port 8000 --reload

Запуск в продакшене (через Docker):
    uvicorn main:app --host 0.0.0.0 --port 8000 --workers 2
"""

import json
import os
import re
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field


# ═══════════════════════════════════════════════════════════════
#  Конфигурация
# ═══════════════════════════════════════════════════════════════

WORKSPACE_PATH = Path(os.environ.get(
    "KENT_WORKSPACE_PATH",
    "/data/workspace",
))
CONFIG_PATH = Path(os.environ.get(
    "KENT_CONFIG_PATH",
    "/data/config",
))

# OpenClaw gateway (для /openclaw/status proxy). По дефолту — имя сервиса в docker network.
OPENCLAW_BASE_URL = os.environ.get(
    "KENT_OPENCLAW_BASE_URL",
    "http://openclaw:18789",
)

# Метаданные деплоя — передаются через build args / env
KENT_VERSION = os.environ.get("KENT_VERSION", "1.0.0")
KENT_GIT_COMMIT = os.environ.get("KENT_GIT_COMMIT", "unknown")
KENT_BUILD_DATE = os.environ.get("KENT_BUILD_DATE", "unknown")

START_TIME = time.time()

# Регэксп для детекта секретов в значениях конфига
_SECRET_PATTERN = re.compile(
    r"(token|secret|password|api[_-]?key|auth)",
    re.IGNORECASE,
)


# ═══════════════════════════════════════════════════════════════
#  Pydantic-схемы
# ═══════════════════════════════════════════════════════════════

class HealthResponse(BaseModel):
    status: str = Field(..., description="'ok' если сервис работает")
    timestamp: str = Field(..., description="Текущее время в ISO 8601 (UTC)")


class InfoResponse(BaseModel):
    name: str
    version: str
    description: str
    docs_url: str
    repo_url: str


class Skill(BaseModel):
    name: str = Field(..., description="Идентификатор skill'а (имя папки)")
    title: Optional[str] = Field(None, description="Человекочитаемое название")
    description: Optional[str] = Field(None, description="Описание skill'а")
    has_skill_md: bool


class SkillsResponse(BaseModel):
    count: int
    skills: list[Skill]


class Integration(BaseModel):
    name: str
    category: str
    requires_auth: bool


class IntegrationsResponse(BaseModel):
    count: int
    integrations: list[Integration]


class KentByte(BaseModel):
    name: str = Field(..., description="Имя файла рецепта без расширения")
    category: str = Field(..., description="Папка-категория (бухгалтеры, юристы и т.д.)")


class KentBytesResponse(BaseModel):
    count: int
    categories: list[str]
    by_category: dict[str, list[KentByte]]


class MetricsResponse(BaseModel):
    uptime_seconds: float
    started_at: str
    version: str
    skills_total: int
    integrations_total: int
    kentbytes_total: int


class VersionResponse(BaseModel):
    version: str
    git_commit: str
    build_date: str
    api_started_at: str


class OpenClawStatus(BaseModel):
    reachable: bool = Field(..., description="Доступен ли OpenClaw gateway")
    status_code: Optional[int] = Field(None, description="HTTP-код ответа (если доступен)")
    response: Optional[Any] = Field(None, description="Сырой ответ /healthz")
    error: Optional[str] = Field(None, description="Описание ошибки если недоступен")
    base_url: str


class ConfigResponse(BaseModel):
    available: bool = Field(..., description="Удалось ли загрузить конфиг")
    sections: list[str] = Field(..., description="Имена top-level секций")
    redacted: dict = Field(
        ...,
        description="Конфиг с убранными секретами (значения с 'token', 'secret', 'password' → '***REDACTED***')",
    )


# ═══════════════════════════════════════════════════════════════
#  Каталог интеграций
# ═══════════════════════════════════════════════════════════════

INTEGRATIONS_CATALOG: list[Integration] = [
    Integration(name="Telegram Bot API", category="messaging", requires_auth=True),
    Integration(name="Anthropic Claude", category="llm", requires_auth=True),
    Integration(name="OpenAI GPT-4o", category="llm", requires_auth=True),
    Integration(name="DeepSeek", category="llm", requires_auth=True),
    Integration(name="Google Gemini", category="llm", requires_auth=True),
    Integration(name="DALL-E 3", category="image-gen", requires_auth=True),
    Integration(name="Whisper", category="stt", requires_auth=False),
    Integration(name="ElevenLabs", category="tts", requires_auth=True),
    Integration(name="Gmail", category="productivity", requires_auth=True),
    Integration(name="Google Calendar", category="productivity", requires_auth=True),
    Integration(name="Google Drive", category="productivity", requires_auth=True),
    Integration(name="Google Sheets", category="productivity", requires_auth=True),
    Integration(name="Google Contacts", category="productivity", requires_auth=True),
    Integration(name="Tavily Search", category="search", requires_auth=True),
    Integration(name="Playwright Browser", category="web-automation", requires_auth=False),
    Integration(name="Twitter/X API", category="social", requires_auth=True),
    Integration(name="Yandex Smart Home", category="iot", requires_auth=True),
    Integration(name="ЮKassa", category="payments", requires_auth=True),
    Integration(name="Wildberries Seller API", category="ecommerce", requires_auth=True),
    Integration(name="python-pptx (PowerPoint)", category="documents", requires_auth=False),
    Integration(name="python-docx (Word)", category="documents", requires_auth=False),
    Integration(name="reportlab (PDF)", category="documents", requires_auth=False),
    Integration(name="openpyxl (Excel)", category="documents", requires_auth=False),
    Integration(name="pdfplumber (PDF parsing)", category="documents", requires_auth=False),
    Integration(name="wttr.in (weather)", category="misc", requires_auth=False),
    Integration(name="yt-dlp (YouTube)", category="misc", requires_auth=False),
    Integration(name="faster-whisper (local STT)", category="stt", requires_auth=False),
    Integration(name="agent-browser (web search)", category="search", requires_auth=False),
]


# ═══════════════════════════════════════════════════════════════
#  Helpers — парсинг файловой системы
# ═══════════════════════════════════════════════════════════════

def _split_frontmatter(text: str) -> tuple[dict[str, str], str]:
    """
    Разделить markdown-файл на YAML-frontmatter (как dict) и body (markdown).
    Без зависимости от yaml — простая ручная парсилка для key: value.
    """
    front: dict[str, str] = {}
    body = text

    if text.startswith("---"):
        end = text.find("---", 3)
        if end > 0:
            yaml_block = text[3:end]
            body = text[end + 3:].lstrip("\n")
            for line in yaml_block.splitlines():
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if ":" in line:
                    key, _, val = line.partition(":")
                    front[key.strip()] = val.strip().strip('"').strip("'")

    return front, body


def _first_meaningful_line(markdown: str, max_chars: int = 200) -> Optional[str]:
    """
    Вернуть первый осмысленный абзац markdown (без заголовков, кода и пустых строк).
    Используется как fallback для description.
    """
    in_code_block = False

    for raw in markdown.splitlines():
        line = raw.strip()
        if line.startswith("```"):
            in_code_block = not in_code_block
            continue
        if in_code_block:
            continue
        # Skip headings, empty lines, blockquote markers
        if not line or line.startswith("#") or line.startswith(">"):
            continue
        # Strip markdown bold/italic markers and trim
        cleaned = re.sub(r"\*\*([^*]+)\*\*", r"\1", line)
        cleaned = re.sub(r"\*([^*]+)\*", r"\1", cleaned)
        if len(cleaned) > max_chars:
            cleaned = cleaned[: max_chars - 1].rstrip() + "…"
        return cleaned

    return None


def _parse_skill_md(skill_dir: Path) -> Skill:
    """Прочитать SKILL.md и извлечь title + description (frontmatter → fallback на markdown)."""
    skill_md = skill_dir / "SKILL.md"

    if not skill_md.exists():
        return Skill(name=skill_dir.name, title=None, description=None, has_skill_md=False)

    title: Optional[str] = None
    description: Optional[str] = None

    try:
        content = skill_md.read_text(encoding="utf-8")
        front, body = _split_frontmatter(content)

        title = front.get("name") or skill_dir.name
        description = front.get("description")

        if not description:
            # Fallback: первый абзац markdown
            description = _first_meaningful_line(body)
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


def _list_kentbytes() -> dict[str, list[KentByte]]:
    """
    Просканировать workspace/kentbytes/ и сгруппировать рецепты по категориям.

    Структура: workspace/kentbytes/<категория>/<рецепт>.md
    """
    kb_dir = WORKSPACE_PATH / "kentbytes"
    by_category: dict[str, list[KentByte]] = {}

    if not kb_dir.exists() or not kb_dir.is_dir():
        return by_category

    for category_dir in sorted(kb_dir.iterdir()):
        if not category_dir.is_dir():
            continue

        recipes: list[KentByte] = []
        for recipe_file in sorted(category_dir.iterdir()):
            if recipe_file.is_file() and recipe_file.suffix.lower() in (".md", ".txt"):
                recipes.append(KentByte(
                    name=recipe_file.stem,
                    category=category_dir.name,
                ))

        if recipes:
            by_category[category_dir.name] = recipes

    return by_category


def _strip_json5_comments(text: str) -> str:
    """
    Удалить //-комментарии и /* */ комментарии из JSON5 для парсинга стандартным json.

    Простой подход: pop'аем строковые литералы, чистим комментарии, восстанавливаем строки.
    """
    # Уберём блоковые /* */ комментарии (не пересекают строки сложных случаев)
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)

    # Построчно удалим //-комментарии вне строковых литералов
    cleaned_lines = []
    for line in text.splitlines():
        in_string = False
        escape = False
        result = []
        i = 0
        while i < len(line):
            c = line[i]
            if escape:
                result.append(c)
                escape = False
            elif c == "\\":
                result.append(c)
                escape = True
            elif c == '"':
                result.append(c)
                in_string = not in_string
            elif not in_string and c == "/" and i + 1 < len(line) and line[i + 1] == "/":
                break  # Остаток строки — комментарий
            else:
                result.append(c)
            i += 1
        cleaned_lines.append("".join(result))

    cleaned = "\n".join(cleaned_lines)
    # JSON5 разрешает trailing comma — стандартный json не разрешает
    cleaned = re.sub(r",(\s*[}\]])", r"\1", cleaned)
    return cleaned


def _redact_secrets(obj: Any) -> Any:
    """Рекурсивно пройти по dict/list и заменить значения с подозрительными ключами на ***REDACTED***."""
    if isinstance(obj, dict):
        return {
            k: ("***REDACTED***" if _SECRET_PATTERN.search(k) and isinstance(v, str)
                else _redact_secrets(v))
            for k, v in obj.items()
        }
    if isinstance(obj, list):
        return [_redact_secrets(item) for item in obj]
    return obj


def _load_config() -> Optional[dict]:
    """Загрузить config/openclaw.json (JSON5) и вернуть распарсенный dict."""
    config_file = CONFIG_PATH / "openclaw.json"

    if not config_file.exists():
        return None

    try:
        raw = config_file.read_text(encoding="utf-8")
        cleaned = _strip_json5_comments(raw)
        return json.loads(cleaned)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return None


# ═══════════════════════════════════════════════════════════════
#  FastAPI приложение
# ═══════════════════════════════════════════════════════════════

app = FastAPI(
    title="Kent AI Assistant API",
    description=(
        "Управляющий API для Kent — production-ready AI-ассистента в Telegram. "
        "Предоставляет endpoints для health, skills, integrations, kentbytes, metrics, и proxy на OpenClaw."
    ),
    version=KENT_VERSION,
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)


# ═══════════════════════════════════════════════════════════════
#  Endpoints — System
# ═══════════════════════════════════════════════════════════════

@app.get("/health", response_model=HealthResponse, tags=["system"], summary="Health check")
async def health() -> HealthResponse:
    """Health-check для мониторинга и Docker healthcheck."""
    return HealthResponse(
        status="ok",
        timestamp=datetime.now(timezone.utc).isoformat(),
    )


@app.get("/", response_model=InfoResponse, tags=["system"], summary="Информация о Kent")
async def info() -> InfoResponse:
    """Базовая информация о продукте."""
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


@app.get("/version", response_model=VersionResponse, tags=["system"], summary="Версия и build info")
async def version() -> VersionResponse:
    """Информация о версии, git commit и времени сборки."""
    started_at = datetime.fromtimestamp(START_TIME, timezone.utc).isoformat()
    return VersionResponse(
        version=KENT_VERSION,
        git_commit=KENT_GIT_COMMIT,
        build_date=KENT_BUILD_DATE,
        api_started_at=started_at,
    )


@app.get("/metrics", response_model=MetricsResponse, tags=["system"], summary="Метрики API")
async def metrics() -> MetricsResponse:
    """Базовые runtime-метрики."""
    started_at = datetime.fromtimestamp(START_TIME, timezone.utc).isoformat()
    kentbytes = _list_kentbytes()
    kentbytes_total = sum(len(items) for items in kentbytes.values())
    return MetricsResponse(
        uptime_seconds=time.time() - START_TIME,
        started_at=started_at,
        version=KENT_VERSION,
        skills_total=len(_list_skills()),
        integrations_total=len(INTEGRATIONS_CATALOG),
        kentbytes_total=kentbytes_total,
    )


@app.get("/openclaw/status", response_model=OpenClawStatus, tags=["system"], summary="Статус OpenClaw gateway")
async def openclaw_status() -> OpenClawStatus:
    """
    Proxy-запрос к OpenClaw `/healthz` — проверяет жив ли основной бот.

    Возвращает `reachable=true` если OpenClaw отвечает 2xx, иначе `reachable=false` + ошибка.
    """
    healthz_url = f"{OPENCLAW_BASE_URL}/healthz"
    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(3.0)) as client:
            resp = await client.get(healthz_url)
        body: Any
        try:
            body = resp.json()
        except ValueError:
            body = resp.text[:500] if resp.text else None
        return OpenClawStatus(
            reachable=resp.is_success,
            status_code=resp.status_code,
            response=body,
            error=None,
            base_url=OPENCLAW_BASE_URL,
        )
    except (httpx.HTTPError, httpx.ConnectError) as exc:
        return OpenClawStatus(
            reachable=False,
            status_code=None,
            response=None,
            error=f"{type(exc).__name__}: {exc}",
            base_url=OPENCLAW_BASE_URL,
        )


# ═══════════════════════════════════════════════════════════════
#  Endpoints — Catalog
# ═══════════════════════════════════════════════════════════════

@app.get("/skills", response_model=SkillsResponse, tags=["catalog"], summary="Список skills")
async def skills() -> SkillsResponse:
    """Список всех кастомных skills из workspace/skills/."""
    skill_list = _list_skills()
    return SkillsResponse(count=len(skill_list), skills=skill_list)


@app.get("/skills/{skill_name}", response_model=Skill, tags=["catalog"], summary="Подробности об одном skill'е")
async def skill_detail(skill_name: str) -> Skill:
    """Получить информацию о конкретном skill'е."""
    skill_dir = WORKSPACE_PATH / "skills" / skill_name
    if not skill_dir.exists() or not skill_dir.is_dir():
        raise HTTPException(status_code=404, detail=f"Skill '{skill_name}' не найден")
    return _parse_skill_md(skill_dir)


@app.get("/integrations", response_model=IntegrationsResponse, tags=["catalog"], summary="Список интеграций")
async def integrations() -> IntegrationsResponse:
    """Каталог всех 28 интеграций."""
    return IntegrationsResponse(count=len(INTEGRATIONS_CATALOG), integrations=INTEGRATIONS_CATALOG)


@app.get("/kentbytes", response_model=KentBytesResponse, tags=["catalog"], summary="Каталог KentBytes")
async def kentbytes() -> KentBytesResponse:
    """
    Список рецептов KentBytes по категориям.

    Структура: workspace/kentbytes/<категория>/<рецепт>.md
    """
    grouped = _list_kentbytes()
    total = sum(len(items) for items in grouped.values())
    return KentBytesResponse(
        count=total,
        categories=list(grouped.keys()),
        by_category=grouped,
    )


# ═══════════════════════════════════════════════════════════════
#  Endpoints — Config (read-only, redacted)
# ═══════════════════════════════════════════════════════════════

@app.get("/config", response_model=ConfigResponse, tags=["system"], summary="Публичный конфиг (без секретов)")
async def config() -> ConfigResponse:
    """
    Просмотреть конфиг openclaw.json **с убранными секретами**.

    Ключи, содержащие 'token', 'secret', 'password', 'api_key', 'auth' (case-insensitive),
    заменяются на `***REDACTED***`.
    """
    cfg = _load_config()
    if cfg is None:
        return ConfigResponse(available=False, sections=[], redacted={})

    return ConfigResponse(
        available=True,
        sections=list(cfg.keys()) if isinstance(cfg, dict) else [],
        redacted=_redact_secrets(cfg) if isinstance(cfg, dict) else {},
    )
