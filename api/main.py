"""
Kent API Gateway — FastAPI service на Kent overlay.

Предоставляет HTTP API для:
  - Health check (для мониторинга и health-checks в Docker)
  - Информации о боте (версия, статус, метрики)
  - Чтения skills, KentBytes-рецептов, личности (SOUL.md)
  - Каталога интеграций
  - Proxy-запросов к OpenClaw (chat, webhooks, agents)
  - WebSocket real-time событий
  - Безопасного просмотра конфига (без секретов)

Безопасность:
  - Bearer token authentication (опционально, через env KENT_API_TOKEN)
  - Rate limiting (60 req/min per IP)
  - CORS с настраиваемыми origins

Swagger UI:                    GET /docs
ReDoc:                         GET /redoc
OpenAPI schema (JSON):         GET /openapi.json
WebSocket события:              WS  /ws/events

Запуск локально:
    uvicorn main:app --host 0.0.0.0 --port 8000 --reload
"""

import asyncio
import json
import os
import re
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

import httpx
from fastapi import (
    Depends,
    FastAPI,
    HTTPException,
    Request,
    WebSocket,
    WebSocketDisconnect,
    status,
)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware
from slowapi.util import get_remote_address


# ═══════════════════════════════════════════════════════════════
#  Конфигурация
# ═══════════════════════════════════════════════════════════════

WORKSPACE_PATH = Path(os.environ.get("KENT_WORKSPACE_PATH", "/data/workspace"))
CONFIG_PATH = Path(os.environ.get("KENT_CONFIG_PATH", "/data/config"))
OPENCLAW_BASE_URL = os.environ.get("KENT_OPENCLAW_BASE_URL", "http://openclaw:18789")
OPENCLAW_TOKEN = os.environ.get("OPENCLAW_GATEWAY_TOKEN", "")

KENT_VERSION = os.environ.get("KENT_VERSION", "1.0.0")
KENT_GIT_COMMIT = os.environ.get("KENT_GIT_COMMIT", "unknown")
KENT_BUILD_DATE = os.environ.get("KENT_BUILD_DATE", "unknown")

# Bearer token для авторизации (если пустой — auth выключен, режим dev/open)
KENT_API_TOKEN = os.environ.get("KENT_API_TOKEN", "")

# CORS — список разрешённых origins. По дефолту "*", но в prod указывай конкретные.
CORS_ALLOWED_ORIGINS = [
    o.strip() for o in os.environ.get("KENT_CORS_ORIGINS", "*").split(",") if o.strip()
]

START_TIME = time.time()

_SECRET_PATTERN = re.compile(r"(token|secret|password|api[_-]?key|auth)", re.IGNORECASE)

# Public endpoints — доступны без bearer token даже если auth включена.
# Documentation и health всегда открыты для удобства мониторинга.
PUBLIC_PATHS = {"/health", "/docs", "/redoc", "/openapi.json", "/"}


# ═══════════════════════════════════════════════════════════════
#  Pydantic-схемы
# ═══════════════════════════════════════════════════════════════

class HealthResponse(BaseModel):
    status: str
    timestamp: str


class InfoResponse(BaseModel):
    name: str
    version: str
    description: str
    docs_url: str
    repo_url: str
    auth_required: bool = Field(..., description="Требуется ли bearer token для защищённых endpoints")


class Skill(BaseModel):
    name: str
    title: Optional[str] = None
    description: Optional[str] = None
    has_skill_md: bool


class SkillsResponse(BaseModel):
    count: int
    skills: list[Skill]


class ContentResponse(BaseModel):
    name: str
    path: str
    content: str
    length: int = Field(..., description="Длина контента в символах")


class Integration(BaseModel):
    name: str
    category: str
    requires_auth: bool


class IntegrationsResponse(BaseModel):
    count: int
    integrations: list[Integration]


class KentByte(BaseModel):
    name: str
    category: str


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
    reachable: bool
    status_code: Optional[int] = None
    response: Optional[Any] = None
    error: Optional[str] = None
    base_url: str


class ConfigResponse(BaseModel):
    available: bool
    sections: list[str]
    redacted: dict


class AgentsResponse(BaseModel):
    source: str = Field(..., description="Откуда получены данные: 'openclaw' или 'workspace'")
    agents: list[dict] = Field(..., description="Список агентов")


class ChatRequest(BaseModel):
    message: str = Field(..., description="Сообщение для бота", min_length=1, max_length=10000)
    user_id: Optional[str] = Field(None, description="Идентификатор пользователя")


class ChatResponse(BaseModel):
    success: bool
    forwarded_to: str
    response: Optional[Any] = None
    error: Optional[str] = None


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
#  Helpers
# ═══════════════════════════════════════════════════════════════

def _split_frontmatter(text: str) -> tuple[dict[str, str], str]:
    """Разделить markdown на YAML-frontmatter (dict) и body (markdown)."""
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
    """Первый осмысленный абзац markdown без заголовков и кода."""
    in_code_block = False
    for raw in markdown.splitlines():
        line = raw.strip()
        if line.startswith("```"):
            in_code_block = not in_code_block
            continue
        if in_code_block or not line or line.startswith("#") or line.startswith(">"):
            continue
        cleaned = re.sub(r"\*\*([^*]+)\*\*", r"\1", line)
        cleaned = re.sub(r"\*([^*]+)\*", r"\1", cleaned)
        if len(cleaned) > max_chars:
            cleaned = cleaned[: max_chars - 1].rstrip() + "…"
        return cleaned
    return None


def _parse_skill_md(skill_dir: Path) -> Skill:
    """Прочитать SKILL.md → title + description."""
    skill_md = skill_dir / "SKILL.md"
    if not skill_md.exists():
        return Skill(name=skill_dir.name, title=None, description=None, has_skill_md=False)

    title: Optional[str] = None
    description: Optional[str] = None
    try:
        content = skill_md.read_text(encoding="utf-8")
        front, body = _split_frontmatter(content)
        title = front.get("name") or skill_dir.name
        description = front.get("description") or _first_meaningful_line(body)
    except (OSError, UnicodeDecodeError):
        pass

    return Skill(name=skill_dir.name, title=title or skill_dir.name,
                 description=description, has_skill_md=True)


def _list_skills() -> list[Skill]:
    skills_dir = WORKSPACE_PATH / "skills"
    if not skills_dir.exists() or not skills_dir.is_dir():
        return []
    return sorted(
        (_parse_skill_md(d) for d in skills_dir.iterdir() if d.is_dir()),
        key=lambda s: s.name,
    )


def _list_kentbytes() -> dict[str, list[KentByte]]:
    kb_dir = WORKSPACE_PATH / "kentbytes"
    by_category: dict[str, list[KentByte]] = {}
    if not kb_dir.exists() or not kb_dir.is_dir():
        return by_category

    for category_dir in sorted(kb_dir.iterdir()):
        if not category_dir.is_dir():
            continue
        recipes = []
        for recipe_file in sorted(category_dir.iterdir()):
            if recipe_file.is_file() and recipe_file.suffix.lower() in (".md", ".txt"):
                recipes.append(KentByte(name=recipe_file.stem, category=category_dir.name))
        if recipes:
            by_category[category_dir.name] = recipes
    return by_category


def _strip_json5_comments(text: str) -> str:
    """Удалить //-комментарии и /* */ комментарии для парсинга стандартным json."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
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
                break
            else:
                result.append(c)
            i += 1
        cleaned_lines.append("".join(result))
    cleaned = "\n".join(cleaned_lines)
    cleaned = re.sub(r",(\s*[}\]])", r"\1", cleaned)
    return cleaned


def _redact_secrets(obj: Any) -> Any:
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
    config_file = CONFIG_PATH / "openclaw.json"
    if not config_file.exists():
        return None
    try:
        raw = config_file.read_text(encoding="utf-8")
        cleaned = _strip_json5_comments(raw)
        return json.loads(cleaned)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return None


def _safe_read_file(file_path: Path, max_size: int = 1_000_000) -> Optional[str]:
    """
    Прочитать файл если он существует и не превышает max_size.

    Возвращает None если файла нет или он слишком большой (защита от
    случайного чтения огромных файлов).
    """
    try:
        if not file_path.exists() or not file_path.is_file():
            return None
        if file_path.stat().st_size > max_size:
            return None
        return file_path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None


# ═══════════════════════════════════════════════════════════════
#  Auth
# ═══════════════════════════════════════════════════════════════

bearer_scheme = HTTPBearer(auto_error=False)


async def verify_token(
    request: Request,
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
) -> None:
    """
    Bearer token middleware.

    Если KENT_API_TOKEN не задан в env — auth отключена (dev mode).
    Если задан — проверяется на всех endpoints кроме PUBLIC_PATHS.
    """
    if not KENT_API_TOKEN:
        return  # Dev mode — auth disabled

    if request.url.path in PUBLIC_PATHS:
        return  # Public endpoint

    if credentials is None or credentials.credentials != KENT_API_TOKEN:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing bearer token",
            headers={"WWW-Authenticate": "Bearer"},
        )


# ═══════════════════════════════════════════════════════════════
#  Rate limiting
# ═══════════════════════════════════════════════════════════════

limiter = Limiter(
    key_func=get_remote_address,
    default_limits=["120/minute"],  # default global limit
    storage_uri="memory://",
)


# ═══════════════════════════════════════════════════════════════
#  FastAPI приложение
# ═══════════════════════════════════════════════════════════════

app = FastAPI(
    title="Kent AI Assistant API",
    description=(
        "Управляющий API для Kent — production-ready AI-ассистента в Telegram. "
        "Health, skills, integrations, kentbytes, OpenClaw proxy, WebSocket events, "
        "secure config viewer."
    ),
    version=KENT_VERSION,
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
)

# Rate limiting middleware
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
app.add_middleware(SlowAPIMiddleware)

# CORS — allowed_credentials=False обязателен с allow_origins=["*"]
app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ALLOWED_ORIGINS,
    allow_credentials=False if "*" in CORS_ALLOWED_ORIGINS else True,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)


# ═══════════════════════════════════════════════════════════════
#  Endpoints — System (public)
# ═══════════════════════════════════════════════════════════════

@app.get("/health", response_model=HealthResponse, tags=["system"], summary="Health check")
@limiter.limit("120/minute")
async def health(request: Request) -> HealthResponse:
    return HealthResponse(status="ok", timestamp=datetime.now(timezone.utc).isoformat())


@app.get("/", response_model=InfoResponse, tags=["system"], summary="Информация о Kent")
@limiter.limit("60/minute")
async def info(request: Request) -> InfoResponse:
    return InfoResponse(
        name="Kent AI Assistant",
        version=KENT_VERSION,
        description="Production-ready AI-ассистент в Telegram на платформе OpenClaw. "
                    "17+ кастомных skills, 28 интеграций, hardened Docker-деплой.",
        docs_url="/docs",
        repo_url="https://github.com/Refusned/Kent-Overlay",
        auth_required=bool(KENT_API_TOKEN),
    )


# ═══════════════════════════════════════════════════════════════
#  Endpoints — System (protected if KENT_API_TOKEN set)
# ═══════════════════════════════════════════════════════════════

@app.get("/version", response_model=VersionResponse, tags=["system"],
         dependencies=[Depends(verify_token)])
@limiter.limit("60/minute")
async def version(request: Request) -> VersionResponse:
    """Версия, git commit, build date."""
    return VersionResponse(
        version=KENT_VERSION,
        git_commit=KENT_GIT_COMMIT,
        build_date=KENT_BUILD_DATE,
        api_started_at=datetime.fromtimestamp(START_TIME, timezone.utc).isoformat(),
    )


@app.get("/metrics", response_model=MetricsResponse, tags=["system"],
         dependencies=[Depends(verify_token)])
@limiter.limit("60/minute")
async def metrics(request: Request) -> MetricsResponse:
    kentbytes_total = sum(len(items) for items in _list_kentbytes().values())
    return MetricsResponse(
        uptime_seconds=time.time() - START_TIME,
        started_at=datetime.fromtimestamp(START_TIME, timezone.utc).isoformat(),
        version=KENT_VERSION,
        skills_total=len(_list_skills()),
        integrations_total=len(INTEGRATIONS_CATALOG),
        kentbytes_total=kentbytes_total,
    )


@app.get("/openclaw/status", response_model=OpenClawStatus, tags=["system"],
         dependencies=[Depends(verify_token)])
@limiter.limit("30/minute")
async def openclaw_status(request: Request) -> OpenClawStatus:
    """Proxy /healthz к OpenClaw."""
    healthz_url = f"{OPENCLAW_BASE_URL}/healthz"
    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(3.0)) as client:
            resp = await client.get(healthz_url)
        try:
            body: Any = resp.json()
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
            error=f"{type(exc).__name__}: {exc}",
            base_url=OPENCLAW_BASE_URL,
        )


@app.get("/config", response_model=ConfigResponse, tags=["system"],
         dependencies=[Depends(verify_token)])
@limiter.limit("30/minute")
async def get_config(request: Request) -> ConfigResponse:
    """Конфиг openclaw.json с REDACTED для секретов."""
    cfg = _load_config()
    if cfg is None:
        return ConfigResponse(available=False, sections=[], redacted={})
    return ConfigResponse(
        available=True,
        sections=list(cfg.keys()) if isinstance(cfg, dict) else [],
        redacted=_redact_secrets(cfg) if isinstance(cfg, dict) else {},
    )


# ═══════════════════════════════════════════════════════════════
#  Endpoints — Catalog (protected)
# ═══════════════════════════════════════════════════════════════

@app.get("/skills", response_model=SkillsResponse, tags=["catalog"],
         dependencies=[Depends(verify_token)])
@limiter.limit("60/minute")
async def list_skills_endpoint(request: Request) -> SkillsResponse:
    skill_list = _list_skills()
    return SkillsResponse(count=len(skill_list), skills=skill_list)


@app.get("/skills/{skill_name}", response_model=Skill, tags=["catalog"],
         dependencies=[Depends(verify_token)])
@limiter.limit("60/minute")
async def skill_detail(request: Request, skill_name: str) -> Skill:
    skill_dir = WORKSPACE_PATH / "skills" / skill_name
    if not skill_dir.exists() or not skill_dir.is_dir():
        raise HTTPException(status_code=404, detail=f"Skill '{skill_name}' не найден")
    return _parse_skill_md(skill_dir)


@app.get("/skills/{skill_name}/content", response_model=ContentResponse, tags=["catalog"],
         dependencies=[Depends(verify_token)],
         summary="Полный markdown содержимое skill'а")
@limiter.limit("30/minute")
async def skill_content(request: Request, skill_name: str) -> ContentResponse:
    """Вернуть полный текст SKILL.md."""
    # Защита от path traversal — только имена без слешей и точек
    if "/" in skill_name or ".." in skill_name:
        raise HTTPException(status_code=400, detail="Invalid skill name")

    skill_md = WORKSPACE_PATH / "skills" / skill_name / "SKILL.md"
    content = _safe_read_file(skill_md)
    if content is None:
        raise HTTPException(status_code=404, detail=f"SKILL.md для '{skill_name}' не найден")
    return ContentResponse(
        name=skill_name,
        path=f"workspace/skills/{skill_name}/SKILL.md",
        content=content,
        length=len(content),
    )


@app.get("/integrations", response_model=IntegrationsResponse, tags=["catalog"],
         dependencies=[Depends(verify_token)])
@limiter.limit("60/minute")
async def integrations_endpoint(request: Request) -> IntegrationsResponse:
    return IntegrationsResponse(count=len(INTEGRATIONS_CATALOG), integrations=INTEGRATIONS_CATALOG)


@app.get("/kentbytes", response_model=KentBytesResponse, tags=["catalog"],
         dependencies=[Depends(verify_token)])
@limiter.limit("60/minute")
async def kentbytes_endpoint(request: Request) -> KentBytesResponse:
    grouped = _list_kentbytes()
    total = sum(len(items) for items in grouped.values())
    return KentBytesResponse(count=total, categories=list(grouped.keys()), by_category=grouped)


@app.get("/kentbytes/{category}/{recipe}", response_model=ContentResponse, tags=["catalog"],
         dependencies=[Depends(verify_token)],
         summary="Содержимое одного KentBytes-рецепта")
@limiter.limit("30/minute")
async def kentbyte_content(request: Request, category: str, recipe: str) -> ContentResponse:
    if "/" in category or ".." in category or "/" in recipe or ".." in recipe:
        raise HTTPException(status_code=400, detail="Invalid path")

    # Пробуем .md и .txt
    base_path = WORKSPACE_PATH / "kentbytes" / category
    for ext in (".md", ".txt"):
        candidate = base_path / f"{recipe}{ext}"
        content = _safe_read_file(candidate)
        if content is not None:
            return ContentResponse(
                name=f"{category}/{recipe}",
                path=f"workspace/kentbytes/{category}/{recipe}{ext}",
                content=content,
                length=len(content),
            )
    raise HTTPException(status_code=404, detail=f"Рецепт '{category}/{recipe}' не найден")


@app.get("/soul", response_model=ContentResponse, tags=["catalog"],
         dependencies=[Depends(verify_token)],
         summary="Личность Kent (SOUL.md)")
@limiter.limit("30/minute")
async def soul(request: Request) -> ContentResponse:
    """Прочитать workspace/SOUL.md — характер, тон и ценности бота."""
    soul_path = WORKSPACE_PATH / "SOUL.md"
    content = _safe_read_file(soul_path)
    if content is None:
        raise HTTPException(status_code=404, detail="SOUL.md не найден")
    return ContentResponse(
        name="SOUL",
        path="workspace/SOUL.md",
        content=content,
        length=len(content),
    )


# ═══════════════════════════════════════════════════════════════
#  Endpoints — OpenClaw proxy
# ═══════════════════════════════════════════════════════════════

@app.get("/agents", response_model=AgentsResponse, tags=["proxy"],
         dependencies=[Depends(verify_token)],
         summary="Список агентов")
@limiter.limit("30/minute")
async def list_agents(request: Request) -> AgentsResponse:
    """
    Получить список агентов.

    Сначала пробуем спросить у OpenClaw, при недоступности — fallback на
    конфиг (workspace/AGENTS.md или config/openclaw.json).
    """
    # Попытка через OpenClaw
    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(3.0)) as client:
            headers = {"Authorization": f"Bearer {OPENCLAW_TOKEN}"} if OPENCLAW_TOKEN else {}
            resp = await client.get(f"{OPENCLAW_BASE_URL}/agents", headers=headers)
        if resp.is_success:
            data = resp.json()
            return AgentsResponse(
                source="openclaw",
                agents=data if isinstance(data, list) else data.get("agents", []),
            )
    except httpx.HTTPError:
        pass

    # Fallback — синтезируем из skills (каждый skill = агент-умение)
    skills_data = _list_skills()
    return AgentsResponse(
        source="workspace",
        agents=[{"name": s.name, "title": s.title, "description": s.description} for s in skills_data],
    )


@app.post("/chat", response_model=ChatResponse, tags=["proxy"],
          dependencies=[Depends(verify_token)],
          summary="Отправить сообщение боту")
@limiter.limit("20/minute")
async def chat(request: Request, payload: ChatRequest) -> ChatResponse:
    """
    Proxy сообщение в OpenClaw.

    Отправляет POST на `${OPENCLAW_BASE_URL}/messages` с body:
    `{"message": "...", "user_id": "..."}`.
    """
    target_url = f"{OPENCLAW_BASE_URL}/messages"
    headers = {"Content-Type": "application/json"}
    if OPENCLAW_TOKEN:
        headers["Authorization"] = f"Bearer {OPENCLAW_TOKEN}"

    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(30.0)) as client:
            resp = await client.post(
                target_url,
                json={"message": payload.message, "user_id": payload.user_id},
                headers=headers,
            )
        try:
            body: Any = resp.json()
        except ValueError:
            body = resp.text[:1000] if resp.text else None
        return ChatResponse(
            success=resp.is_success,
            forwarded_to=target_url,
            response=body,
            error=None if resp.is_success else f"HTTP {resp.status_code}",
        )
    except httpx.HTTPError as exc:
        return ChatResponse(
            success=False,
            forwarded_to=target_url,
            response=None,
            error=f"{type(exc).__name__}: {exc}",
        )


@app.post("/webhooks/telegram", tags=["proxy"], summary="Telegram webhook receiver",
          dependencies=[Depends(verify_token)])
@limiter.limit("60/minute")
async def telegram_webhook(request: Request):
    """
    Принимает Telegram webhook и проксирует на OpenClaw.

    Telegram POST'ит сюда updates когда настроен webhook на этот URL.
    """
    target_url = f"{OPENCLAW_BASE_URL}/webhooks/telegram"
    headers = {"Content-Type": "application/json"}
    if OPENCLAW_TOKEN:
        headers["Authorization"] = f"Bearer {OPENCLAW_TOKEN}"

    body = await request.body()
    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(30.0)) as client:
            resp = await client.post(target_url, content=body, headers=headers)
        return JSONResponse(
            status_code=resp.status_code if resp.is_success else 502,
            content={"forwarded_to": target_url, "openclaw_status": resp.status_code},
        )
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=502,
            detail=f"OpenClaw недоступен: {type(exc).__name__}",
        )


# ═══════════════════════════════════════════════════════════════
#  WebSocket — real-time события
# ═══════════════════════════════════════════════════════════════

class ConnectionManager:
    """Менеджер активных WebSocket-соединений."""

    def __init__(self) -> None:
        self.active: list[WebSocket] = []

    async def connect(self, ws: WebSocket) -> None:
        await ws.accept()
        self.active.append(ws)

    def disconnect(self, ws: WebSocket) -> None:
        if ws in self.active:
            self.active.remove(ws)

    async def broadcast(self, message: dict) -> None:
        # Отправляем всем активным соединениям, удаляем сломанные
        dead: list[WebSocket] = []
        for ws in self.active:
            try:
                await ws.send_json(message)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self.disconnect(ws)


manager = ConnectionManager()


@app.websocket("/ws/events")
async def websocket_events(websocket: WebSocket) -> None:
    """
    WebSocket-стрим событий.

    Каждые 5 секунд отправляет heartbeat с текущим uptime, статусом и счётчиками.
    Также отвечает на сообщения 'ping' → 'pong'.

    Auth через query parameter `?token=...` если KENT_API_TOKEN задан.
    """
    if KENT_API_TOKEN:
        token = websocket.query_params.get("token")
        if token != KENT_API_TOKEN:
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
            return

    await manager.connect(websocket)
    try:
        # Отправим первое событие сразу
        await websocket.send_json({
            "type": "connected",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "version": KENT_VERSION,
        })

        # Цикл: heartbeat каждые 5 сек + обработка входящих сообщений
        while True:
            try:
                # Ждём входящее сообщение с таймаутом 5 сек
                data = await asyncio.wait_for(websocket.receive_text(), timeout=5.0)
                if data == "ping":
                    await websocket.send_json({"type": "pong", "timestamp": datetime.now(timezone.utc).isoformat()})
                else:
                    await websocket.send_json({
                        "type": "echo",
                        "received": data,
                        "timestamp": datetime.now(timezone.utc).isoformat(),
                    })
            except asyncio.TimeoutError:
                # Таймаут = время отправить heartbeat
                await websocket.send_json({
                    "type": "heartbeat",
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                    "uptime_seconds": time.time() - START_TIME,
                    "skills_total": len(_list_skills()),
                })
    except WebSocketDisconnect:
        manager.disconnect(websocket)
