# Cube FastMCP Service

A high-performance Model Context Protocol (MCP) server bridging enterprise data warehouses (Google BigQuery) and LLM client interfaces (Claude Desktop, Claude Code) through Cube Core's semantic engine.

## Features

- **Semantic Query Execution (`run_semantic_query`)**: Executes governed metrics and dimensions via Cube Core's `/cubejs-api/v1/load`, automatically leveraging L1 memory and L2 Cube Store pre-aggregation caches.
- **Arbitrary SQL Execution (`run_sql_query`)**: Executes custom, unmodeled SQL queries directly against Cube Core's SQL API (`/cubejs-api/v1/cubesql`), streaming NDJSON chunks and pushing down to BigQuery.
- **Data Catalog Discovery (`get_metadata`)**: Exposes cubes, dimensions, measures, segments, and descriptions via `/cubejs-api/v1/meta`.
- **Query Planner & Cost Explanation (`explain_sql_query`)**: Generates BigQuery warehouse SQL and pre-aggregation rollup match analysis via `/cubejs-api/v1/sql` without executing.
- **Payload Token Optimization**: Compresses verbose JSON responses into dense Markdown tables and CSV strings to minimize LLM context window consumption.
- **Google OAuth 2.0**: Native authentication provider integration (`GoogleProvider`) validating bearer tokens and extracting user identity.
- **Cloud Run Native**: Zero-trust service-to-service IAM authentication using Google Application Default Credentials (ADC) ID tokens.

## Architecture

```text
[ LLM Client / Claude ] 
       │ (SSE / Streamable HTTP)
       ▼
[ FastMCP on Cloud Run ] (Port 8080)
       │ (GCP ID Token + CUBEJS_API_SECRET)
       ▼
[ Cube Core on Cloud Run ] (Port 4000)
       │
       ├── L1 Cache (In-Memory)
       ├── L2 Cache (Cube Store on Spot VM: 10.10.0.10:3030)
       └── Source Warehouse (Google BigQuery)
```

## Quickstart

### Prerequisites
- Python `>= 3.12`
- `uv` package manager (`curl -LsSf https://astral.sh/uv/install.sh | sh`)

### Local Setup
```bash
cd src/fastmcp
uv sync
```

### Environment Variables
Configure the following in `.env` or your runtime environment:

| Variable | Description | Default |
| :--- | :--- | :--- |
| `CUBE_API_URL` | Base URL of the Cube Core API service | `http://localhost:4000` |
| `CUBE_API_SECRET` | Secret token configured in `CUBEJS_API_SECRET` on Cube Core | `""` |
| `GOOGLE_CLIENT_ID` | Google OAuth 2.0 Client ID (optional, enables GoogleProvider) | `""` |
| `GOOGLE_CLIENT_SECRET` | Google OAuth 2.0 Client Secret | `""` |
| `FASTMCP_PUBLIC_URL` | Public base URL for OAuth callbacks | `http://localhost:8080` |
| `GOOGLE_AUTH_ENABLED` | Whether to enforce Google OAuth authentication | `false` |
| `PORT` | HTTP/SSE server listening port | `8080` |
| `FASTMCP_TRANSPORT` | Server transport protocol (`sse`, `http`, `stdio`) | `sse` |

### Running Locally
```bash
uv run python -m cube_fastmcp.server
```

### Running Tests and Quality Checks
```bash
# Unit & integration tests
uv run pytest tests/

# Linting
uv run ruff check .

# Formatting
uv run ruff format --check .

# Type checking
uv run mypy .
```
