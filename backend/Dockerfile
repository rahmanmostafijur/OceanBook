# syntax=docker/dockerfile:1.7
# One image, several roles: api | worker | scheduler | relay | migrate (selected by the command).

FROM python:3.13-slim-bookworm AS builder
COPY --from=ghcr.io/astral-sh/uv:0.10 /uv /usr/local/bin/uv
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PYTHON_DOWNLOADS=never
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv uv sync --frozen --no-dev --no-install-project
COPY app ./app
COPY migrations ./migrations
COPY alembic.ini ./
RUN --mount=type=cache,target=/root/.cache/uv uv sync --frozen --no-dev

FROM python:3.13-slim-bookworm AS runtime
# The runtime never installs packages: drop pip/ensurepip (their vendored urllib3, msgpack and setuptools
# carry CVEs and are pure attack surface). Dependencies come only from the locked venv built above.
RUN python -m pip uninstall -y pip  && rm -rf /usr/local/lib/python3.13/ensurepip /usr/local/bin/pip*  && groupadd --system --gid 10001 app && useradd --system --uid 10001 --gid app --no-create-home app
ENV PATH="/app/.venv/bin:$PATH" PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 FORWARDED_ALLOW_IPS=127.0.0.1
WORKDIR /app
COPY --from=builder --chown=app:app /app /app
USER app
EXPOSE 8000
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2).status == 200 else 1)"
# Graceful shutdown: uvicorn drains in-flight requests on SIGTERM.
CMD ["uvicorn", "app.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000", \
     "--proxy-headers", "--timeout-graceful-shutdown", "30", "--no-server-header"]
# Set FORWARDED_ALLOW_IPS to the load balancer subnets (uvicorn reads it); never "*" in production.
