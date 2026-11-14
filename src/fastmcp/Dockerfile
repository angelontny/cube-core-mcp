# Production Dockerfile for FastMCP Semantic Layer Service on Google Cloud Run
FROM python:3.12-slim

# Install system dependencies (curl for healthchecks, ca-certificates for TLS)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install uv for ultra-fast, deterministic dependency management
COPY --from=ghcr.io/astral-sh/uv:0.6.0 /uv /uvx /bin/

WORKDIR /app

# Enable bytecode compilation and set environment flags
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    PYTHONUNBUFFERED=1 \
    PORT=8080 \
    PATH="/app/.venv/bin:$PATH"

# Copy dependency specifications first to leverage Docker layer caching
COPY pyproject.toml uv.lock README.md ./

# Install locked production dependencies
RUN uv sync --frozen --no-dev --no-install-project

# Copy source code and install project package
COPY src ./src
RUN uv sync --frozen --no-dev

EXPOSE 8080

# Run FastMCP server over SSE / HTTP
CMD ["python", "-m", "cube_fastmcp.server"]
