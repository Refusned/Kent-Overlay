# Kent API Gateway — FastAPI service
# Лёгкий контейнер: python:3.12-slim, без лишних зависимостей.

FROM python:3.12-slim

# Set non-root user для безопасности (рекомендация Docker security)
RUN groupadd -r kent && useradd -r -g kent kent

WORKDIR /app

# Сначала ставим зависимости (кешируется если requirements.txt не менялся)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Копируем код приложения
COPY main.py langchain_module.py russian_llm.py ./

# Метаданные
LABEL org.opencontainers.image.title="Kent AI API"
LABEL org.opencontainers.image.description="FastAPI gateway for Kent AI Assistant"
LABEL org.opencontainers.image.source="https://github.com/Refusned/Kent-Overlay"
LABEL org.opencontainers.image.licenses="MIT"

# Порт и пользователь
EXPOSE 8000
USER kent

# Health-check встроен в образ
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health').read()" || exit 1

# Запуск через uvicorn
# --workers 2 — по 2 worker'а на контейнер (хватает для нашей нагрузки)
# --host 0.0.0.0 — слушаем все интерфейсы (внутри контейнера)
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]
