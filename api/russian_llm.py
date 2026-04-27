"""
Russian LLM providers — YandexGPT и GigaChat.

Унифицированный интерфейс для работы с российскими LLM (требуются для
корпоративных клиентов Сбер, Тинькофф, Яндекс, банки) параллельно с
зарубежными (OpenAI, Anthropic).

Демонстрирует Provider pattern: один интерфейс, несколько реализаций,
переключение через параметр.

Без API ключей провайдеры работают в mock-режиме — можно тестировать
pipeline без реальных credentials.
"""

import asyncio
import base64
import os
import ssl
import uuid
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Optional

import httpx


# ═══════════════════════════════════════════════════════════════
#  Configuration
# ═══════════════════════════════════════════════════════════════

# OpenAI / Anthropic
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "")
ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")

# YandexGPT — Yandex Cloud Foundation Models API
# Получить: https://yandex.cloud/ru/docs/foundation-models/operations/get-api-key
YANDEX_API_KEY = os.environ.get("YANDEX_API_KEY", "")
YANDEX_FOLDER_ID = os.environ.get("YANDEX_FOLDER_ID", "")
YANDEX_MODEL = os.environ.get("YANDEX_MODEL", "yandexgpt-lite")  # или yandexgpt

# GigaChat — Sber Cloud
# Получить: https://developers.sber.ru/docs/ru/gigachat/api/integration
GIGACHAT_CLIENT_ID = os.environ.get("GIGACHAT_CLIENT_ID", "")
GIGACHAT_CLIENT_SECRET = os.environ.get("GIGACHAT_CLIENT_SECRET", "")
GIGACHAT_AUTH_KEY = os.environ.get("GIGACHAT_AUTH_KEY", "")  # base64(client_id:client_secret)
GIGACHAT_SCOPE = os.environ.get("GIGACHAT_SCOPE", "GIGACHAT_API_PERS")
GIGACHAT_MODEL = os.environ.get("GIGACHAT_MODEL", "GigaChat")


# ═══════════════════════════════════════════════════════════════
#  Provider interface
# ═══════════════════════════════════════════════════════════════

@dataclass
class ChatResponse:
    """Унифицированный ответ от любого LLM-провайдера."""
    text: str
    provider: str
    model: str
    is_mock: bool
    raw: Optional[dict] = None


class LLMProvider(ABC):
    """Абстрактный базовый класс для всех LLM-провайдеров."""

    name: str = "base"
    model: str = "unknown"

    @abstractmethod
    async def chat(self, message: str, system: Optional[str] = None) -> ChatResponse:
        """Отправить сообщение в LLM и получить ответ."""

    def is_configured(self) -> bool:
        """Настроен ли провайдер (есть ли API ключи)."""
        return False


# ═══════════════════════════════════════════════════════════════
#  Mock provider — для тестов без реальных API
# ═══════════════════════════════════════════════════════════════

class MockProvider(LLMProvider):
    """
    Mock LLM — возвращает шаблонный ответ.

    Используется когда у провайдера нет API ключа. Позволяет тестировать
    pipeline без реальных вызовов и оплаты.
    """

    def __init__(self, name: str, model: str = "mock") -> None:
        self.name = name
        self.model = model

    async def chat(self, message: str, system: Optional[str] = None) -> ChatResponse:
        return ChatResponse(
            text=(
                f"Mock-ответ от {self.name}. Чтобы получить реальный ответ, "
                f"задай API ключ в env: {self._env_var_name()}."
            ),
            provider=self.name,
            model=self.model,
            is_mock=True,
        )

    def _env_var_name(self) -> str:
        return {
            "yandex": "YANDEX_API_KEY и YANDEX_FOLDER_ID",
            "gigachat": "GIGACHAT_AUTH_KEY (или CLIENT_ID + CLIENT_SECRET)",
            "openai": "OPENAI_API_KEY",
            "anthropic": "ANTHROPIC_API_KEY",
        }.get(self.name, "<API key>")


# ═══════════════════════════════════════════════════════════════
#  YandexGPT provider
# ═══════════════════════════════════════════════════════════════

class YandexGPTProvider(LLMProvider):
    """
    YandexGPT через Yandex Cloud Foundation Models API.

    Документация: https://yandex.cloud/ru/docs/foundation-models/concepts/yandexgpt/
    Endpoint: POST https://llm.api.cloud.yandex.net/foundationModels/v1/completion
    """

    name = "yandex"
    URL = "https://llm.api.cloud.yandex.net/foundationModels/v1/completion"

    def __init__(self) -> None:
        self.api_key = YANDEX_API_KEY
        self.folder_id = YANDEX_FOLDER_ID
        self.model = YANDEX_MODEL

    def is_configured(self) -> bool:
        return bool(self.api_key and self.folder_id)

    async def chat(self, message: str, system: Optional[str] = None) -> ChatResponse:
        messages = []
        if system:
            messages.append({"role": "system", "text": system})
        messages.append({"role": "user", "text": message})

        body = {
            "modelUri": f"gpt://{self.folder_id}/{self.model}/latest",
            "completionOptions": {
                "stream": False,
                "temperature": 0.7,
                "maxTokens": "1000",
            },
            "messages": messages,
        }
        headers = {
            "Authorization": f"Api-Key {self.api_key}",
            "Content-Type": "application/json",
            "x-folder-id": self.folder_id,
        }

        async with httpx.AsyncClient(timeout=httpx.Timeout(30.0)) as client:
            resp = await client.post(self.URL, headers=headers, json=body)
            resp.raise_for_status()
            data = resp.json()

        # YandexGPT response format:
        # {"result": {"alternatives": [{"message": {"text": "..."}}], ...}}
        text = data["result"]["alternatives"][0]["message"]["text"]
        return ChatResponse(
            text=text,
            provider=self.name,
            model=f"{self.model}/latest",
            is_mock=False,
            raw=data,
        )


# ═══════════════════════════════════════════════════════════════
#  GigaChat provider
# ═══════════════════════════════════════════════════════════════

class GigaChatProvider(LLMProvider):
    """
    GigaChat от Сбера через OAuth2 + Chat Completions API.

    Документация: https://developers.sber.ru/docs/ru/gigachat/api/integration
    OAuth: POST https://ngw.devices.sberbank.ru:9443/api/v2/oauth
    Chat:  POST https://gigachat.devices.sberbank.ru/api/v1/chat/completions

    GigaChat использует self-signed SSL cert от Минцифры — для production
    нужно добавить их CA в trust store. Для dev/demo используем verify=False
    (с предупреждением).
    """

    name = "gigachat"
    OAUTH_URL = "https://ngw.devices.sberbank.ru:9443/api/v2/oauth"
    CHAT_URL = "https://gigachat.devices.sberbank.ru/api/v1/chat/completions"

    def __init__(self) -> None:
        self.auth_key = GIGACHAT_AUTH_KEY
        # Если auth_key не задан, попробуем сформировать из client_id + client_secret
        if not self.auth_key and GIGACHAT_CLIENT_ID and GIGACHAT_CLIENT_SECRET:
            credentials = f"{GIGACHAT_CLIENT_ID}:{GIGACHAT_CLIENT_SECRET}"
            self.auth_key = base64.b64encode(credentials.encode()).decode()
        self.scope = GIGACHAT_SCOPE
        self.model = GIGACHAT_MODEL
        self._access_token: Optional[str] = None
        self._token_lock = asyncio.Lock()

    def is_configured(self) -> bool:
        return bool(self.auth_key)

    async def _get_access_token(self) -> str:
        """Получить OAuth access token. Кэшируется до перезапуска."""
        async with self._token_lock:
            if self._access_token:
                return self._access_token

            headers = {
                "Authorization": f"Basic {self.auth_key}",
                "RqUID": str(uuid.uuid4()),
                "Content-Type": "application/x-www-form-urlencoded",
                "Accept": "application/json",
            }
            data = {"scope": self.scope}

            # verify=False для self-signed cert от Минцифры (в prod — pinned CA)
            async with httpx.AsyncClient(timeout=httpx.Timeout(15.0), verify=False) as client:
                resp = await client.post(self.OAUTH_URL, headers=headers, data=data)
                resp.raise_for_status()
                payload = resp.json()
                self._access_token = payload["access_token"]
                return self._access_token

    async def chat(self, message: str, system: Optional[str] = None) -> ChatResponse:
        access_token = await self._get_access_token()

        messages = []
        if system:
            messages.append({"role": "system", "content": system})
        messages.append({"role": "user", "content": message})

        body = {
            "model": self.model,
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 1000,
        }
        headers = {
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        }

        async with httpx.AsyncClient(timeout=httpx.Timeout(30.0), verify=False) as client:
            resp = await client.post(self.CHAT_URL, headers=headers, json=body)
            resp.raise_for_status()
            data = resp.json()

        # GigaChat response — OpenAI-compatible: {"choices": [{"message": {"content": "..."}}]}
        text = data["choices"][0]["message"]["content"]
        return ChatResponse(
            text=text,
            provider=self.name,
            model=self.model,
            is_mock=False,
            raw=data,
        )


# ═══════════════════════════════════════════════════════════════
#  OpenAI и Anthropic — для unified интерфейса
# ═══════════════════════════════════════════════════════════════

class OpenAIProvider(LLMProvider):
    """OpenAI GPT-4o-mini через chat completions API."""

    name = "openai"
    URL = "https://api.openai.com/v1/chat/completions"

    def __init__(self) -> None:
        self.api_key = OPENAI_API_KEY
        self.model = "gpt-4o-mini"

    def is_configured(self) -> bool:
        return bool(self.api_key)

    async def chat(self, message: str, system: Optional[str] = None) -> ChatResponse:
        messages = []
        if system:
            messages.append({"role": "system", "content": system})
        messages.append({"role": "user", "content": message})

        async with httpx.AsyncClient(timeout=httpx.Timeout(30.0)) as client:
            resp = await client.post(
                self.URL,
                headers={
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": "application/json",
                },
                json={"model": self.model, "messages": messages, "temperature": 0.7},
            )
            resp.raise_for_status()
            data = resp.json()

        return ChatResponse(
            text=data["choices"][0]["message"]["content"],
            provider=self.name,
            model=self.model,
            is_mock=False,
            raw=data,
        )


class AnthropicProvider(LLMProvider):
    """Anthropic Claude через Messages API."""

    name = "anthropic"
    URL = "https://api.anthropic.com/v1/messages"

    def __init__(self) -> None:
        self.api_key = ANTHROPIC_API_KEY
        self.model = "claude-haiku-4-5"

    def is_configured(self) -> bool:
        return bool(self.api_key)

    async def chat(self, message: str, system: Optional[str] = None) -> ChatResponse:
        body = {
            "model": self.model,
            "max_tokens": 1000,
            "messages": [{"role": "user", "content": message}],
        }
        if system:
            body["system"] = system

        async with httpx.AsyncClient(timeout=httpx.Timeout(30.0)) as client:
            resp = await client.post(
                self.URL,
                headers={
                    "x-api-key": self.api_key,
                    "anthropic-version": "2023-06-01",
                    "Content-Type": "application/json",
                },
                json=body,
            )
            resp.raise_for_status()
            data = resp.json()

        text = data["content"][0]["text"] if data.get("content") else ""
        return ChatResponse(
            text=text,
            provider=self.name,
            model=self.model,
            is_mock=False,
            raw=data,
        )


# ═══════════════════════════════════════════════════════════════
#  Provider registry — factory + список
# ═══════════════════════════════════════════════════════════════

PROVIDER_CLASSES = {
    "yandex": YandexGPTProvider,
    "gigachat": GigaChatProvider,
    "openai": OpenAIProvider,
    "anthropic": AnthropicProvider,
}

# Российские провайдеры — для compliance-режима (152-ФЗ ПДн в РФ).
RUSSIA_ONLY_PROVIDERS = {"yandex", "gigachat"}

# Compliance-флаг — форсит on-prem РФ-only providers.
# Используется при коммерческом deployment с обработкой ПДн российских граждан
# (152-ФЗ запрещает передачу ПДн за рубеж).
#
# Когда KENT_RUSSIA_COMPLIANCE_MODE=true:
#   - get_provider("openai") → ValueError (запрещён в РФ-режиме)
#   - get_provider("yandex") → YandexGPTProvider (разрешён)
#   - list_providers() помечает запрещённые провайдеры как blocked_by_compliance
def is_russia_compliance_mode() -> bool:
    """Включён ли режим 152-ФЗ-совместимости (только on-prem РФ providers)."""
    return os.environ.get("KENT_RUSSIA_COMPLIANCE_MODE", "").lower() in (
        "1", "true", "yes", "on",
    )


def get_provider(name: str) -> LLMProvider:
    """
    Получить LLM-провайдер по имени.

    Если провайдер настроен — возвращаем его, иначе — MockProvider.

    Если включён KENT_RUSSIA_COMPLIANCE_MODE — провайдеры вне РФ блокируются
    с ValueError (для 152-ФЗ deployments).
    """
    name_lower = name.lower()

    if is_russia_compliance_mode() and name_lower not in RUSSIA_ONLY_PROVIDERS:
        raise ValueError(
            f"Provider '{name}' blocked by KENT_RUSSIA_COMPLIANCE_MODE. "
            f"152-ФЗ запрещает передачу ПДн за рубеж. "
            f"Доступные провайдеры в compliance-режиме: {sorted(RUSSIA_ONLY_PROVIDERS)}."
        )

    cls = PROVIDER_CLASSES.get(name_lower)
    if cls is None:
        raise ValueError(
            f"Unknown provider '{name}'. Доступные: {list(PROVIDER_CLASSES.keys())}"
        )
    instance = cls()
    if not instance.is_configured():
        return MockProvider(name=name_lower, model=f"{name}-mock")
    return instance


def list_providers() -> list[dict]:
    """Список всех провайдеров с информацией о их статусе."""
    compliance_on = is_russia_compliance_mode()
    result = []
    for name, cls in PROVIDER_CLASSES.items():
        instance = cls()
        blocked = compliance_on and name not in RUSSIA_ONLY_PROVIDERS
        if blocked:
            status = "blocked_by_compliance (152-ФЗ mode)"
        elif instance.is_configured():
            status = "ready"
        else:
            status = "mock (no API key)"
        result.append({
            "name": name,
            "model": instance.model,
            "configured": instance.is_configured(),
            "country": _country_for_provider(name),
            "status": status,
            "blocked_by_compliance": blocked,
        })
    return result


def _country_for_provider(name: str) -> str:
    return {
        "yandex": "Russia",
        "gigachat": "Russia",
        "openai": "USA",
        "anthropic": "USA",
    }.get(name, "Unknown")
