# FastMCP Implementation & Architecture Guide

This guide documents the implementation, design patterns, security model, token-optimization strategy, and operational workflows for the **FastMCP Semantic Layer Server** ([src/fastmcp/](file:///home/angelo/projects/cube-core-mcp/src/fastmcp)).

---

## 1. Architectural Purpose & Overview

The FastMCP service is a serverless Python translation wrapper that exposes the **Cube Core Semantic Layer** to Large Language Model (LLM) clients over the **Model Context Protocol (MCP)**. It bridges the gap between natural language reasoning agents and governed data warehouse queries.

```text
┌─────────────────────────────────────────────────────────────────────────┐
│ Client Tier: Claude Web, Claude Desktop, Antigravity CLI, Cursor        │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │ Streamable HTTP (/mcp) or SSE (/sse)
                                     │ With Google OAuth 2.0 Bearer Token
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Google Cloud Run v2 Pod: "cube-mcp" (asia-south1)                       │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │ Container 1: Ingress ("fastmcp")                                  │  │
│  │ - Port: 8080 (Public Ingress)                                     │  │
│  │ - FastMCP Framework v4.2.0 (Python 3.12, uv)                      │  │
│  │ - Google OAuth 2.0 Provider (RFC 6750 / CIMD Support)             │  │
│  │ - Token-dense Markdown Table Serializers                          │  │
│  └─────────────────────────────────┬─────────────────────────────────┘  │
│                                    │ Loopback HTTP (127.0.0.1:4000)     │
│                                    │ Zero Network Latency & Zero IAM    │
│                                    ▼                                    │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │ Container 2: Sidecar ("cube-core")                                │  │
│  │ - Internal Port: 4000 (No public exposure)                        │  │
│  │ - Cube.js Semantic Engine (Direct BigQuery & Cube Store Driver)   │  │
│  │ - Startup Probe: GET /readyz:4000                                 │  │
│  └─────────────────────────────────┬─────────────────────────────────┘  │
└────────────────────────────────────┼────────────────────────────────────┘
                                     │ Direct VPC Egress (10.10.0.0/24)
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Cache Tier: Cube Store L2 Pre-aggregations (Spot VM, 10.10.0.10:3030)   │
└─────────────────────────────────────────────────────────────────────────┘
```

### Key Architectural Tenets
1. **Multi-Container Pod Colocation**: In Cloud Run v2, `fastmcp` and `cube-core` run within the same network namespace. FastMCP reaches Cube Core over local loopback (`http://127.0.0.1:4000`), eliminating service-to-service Google IAM tokens, external DNS lookups, and inter-service latency.
2. **Dual-Tier Zero-Trust Perimeter**: Cloud Run network edge filtering combined with application-level Google OAuth 2.0 guarantees that only authenticated, authorized users can invoke tools.
3. **Payload Compression (Rule 5 Compliance)**: Verbose JSON responses from Cube Core are compressed into token-efficient Markdown tables and CSV strings before returning to the LLM context window.
4. **Transport Flexibility**: Supports modern **Streamable HTTP** (`/mcp`), legacy **HTTP+SSE** (`/sse`), and local **Stdio** execution.

---

## 2. Directory Layout & Core Modules

```text
src/fastmcp/
├── Dockerfile                   # Multi-stage production container build (Python 3.12-slim + uv)
├── pyproject.toml               # Project metadata, dependencies, ruff, and mypy configurations
├── README.md                    # Service quickstart and local developer guide
├── src/
│   └── cube_fastmcp/
│       ├── __init__.py          # Package initialization
│       ├── config.py            # Pydantic Settings loaded from environment variables
│       ├── cube_client.py       # Async HTTP client with NDJSON streaming parser
│       ├── formatters.py        # Token-optimized Markdown serializer
│       └── server.py            # FastMCP server definition, tool handlers, and entrypoint
└── tests/
    ├── __init__.py
    ├── test_cube_client.py      # Unit tests for HTTP mechanics and error handling
    ├── test_formatters.py       # Unit tests for Markdown formatting and cache metadata
    └── test_server.py           # Unit tests for tool routing and responses
```

---

## 3. Core Module Breakdown

### A. Configuration Management ([config.py](file:///home/angelo/projects/cube-core-mcp/src/fastmcp/src/cube_fastmcp/config.py))
Uses `pydantic-settings` to parse configuration from environment variables or `.env` files:

* `CUBE_API_URL`: Base URL for Cube Core (defaults to `http://127.0.0.1:4000` in Cloud Run).
* `CUBE_API_SECRET`: JWT secret for Cube Core API handshake.
* `GOOGLE_AUTH_ENABLED`: Master boolean toggle to enforce Google OAuth 2.0 authentication.
* `GOOGLE_CLIENT_ID`: Google OAuth 2.0 Web Client ID (mounted from Google Secret Manager).
* `GOOGLE_CLIENT_SECRET`: Google OAuth 2.0 Web Client Secret (mounted from Google Secret Manager).
* `FASTMCP_PUBLIC_URL`: Canonical public base URL (`https://cube-mcp-h3ungosjsa-el.a.run.app`) used to build OAuth authorization and redirect URIs.
* `PORT`: Listening port injected automatically by Cloud Run (defaults to `8080`).

### B. Asynchronous Cube Client ([cube_client.py](file:///home/angelo/projects/cube-core-mcp/src/fastmcp/src/cube_fastmcp/cube_client.py))
An asynchronous HTTP client built on `httpx`:

* **`get_metadata()`**: Queries `GET /cubejs-api/v1/meta` to discover declared cubes, measures, dimensions, and pre-aggregations.
* **`load_semantic_query(query)`**: Sends JSON payloads to `POST /cubejs-api/v1/load`, handling server-side pre-aggregation calculation states (`Continue wait`).
* **`run_sql_query(query, timezone)`**: Connects to `POST /cubejs-api/v1/cubesql`, utilizing an asynchronous generator to parse newline-delimited JSON (NDJSON) streaming data chunks.
* **`explain_sql_query(query)`**: Posts to `POST /cubejs-api/v1/dry-run` or `/v1/sql` to inspect the generated BigQuery SQL and cache routing paths without executing heavy warehouse scans.

### C. Payload Compression & Formatters ([formatters.py](file:///home/angelo/projects/cube-core-mcp/src/fastmcp/src/cube_fastmcp/formatters.py))
Translates verbose JSON outputs into dense Markdown tables for LLM token savings:

* **Catalog Optimization**: Renders schema metadata as structured Markdown tables per cube, presenting column types and descriptions without nested JSON schema boilerplate.
* **Data Flattening**: Converts nested record dictionaries into compact Markdown tables.
* **Cache Introspection**: Appends a dense metadata footer indicating cache performance (e.g. `_Execution Metadata: L2 Pre-aggregation Match: dev_pre_aggregations.orders_orders_status_summary (cubestore)_`).

### D. Server & Tool Registration ([server.py](file:///home/angelo/projects/cube-core-mcp/src/fastmcp/src/cube_fastmcp/server.py))
Initializes the `FastMCP` application, registers tools, and manages OAuth handlers.

---

## 4. Exposed MCP Tools Specification

| Tool Name | Arguments | Purpose & Description |
| :--- | :--- | :--- |
| **`get_metadata`** | *None* | Discovers all valid cubes, dimensions, measures, segments, and pre-aggregations. LLMs invoke this tool first to discover correct metric and dimension names. |
| **`run_semantic_query`** | `measures` *(list)*<br>`dimensions` *(list)*<br>`filters` *(list)*<br>`time_dimensions` *(list)*<br>`order` *(dict)*<br>`limit` *(int)* | Executes a governed dimensional semantic query through Cube Core. Leverages L1 memory and L2 Cube Store pre-aggregations automatically. |
| **`run_sql_query`** | `query` *(string)*<br>`timezone` *(string)* | Executes arbitrary ANSI SQL queries against Cube Core's SQL API (`/cubejs-api/v1/cubesql`). |
| **`explain_sql_query`** | `measures` *(list)*<br>`dimensions` *(list)*<br>`filters` *(list)* | Returns the raw BigQuery SQL query and explains whether Cube Core will serve the query from pre-aggregations or direct warehouse scan. |

---

## 5. Security & Authentication Architecture

FastMCP implements a dual-layer security model:

### Layer 1: Cloud Run Network Edge (IAM Perimeter)
* **Unauthenticated Access Disabled (Private Mode)**: Requests must carry a Google IAM Identity Bearer token (`roles/run.invoker`) minted via Service Account impersonation. Google Front End rejects unapproved callers with `HTTP 403 Forbidden` before packets reach the container.
* **Public Ingress (Web / Claude Web Mode)**: When `invoker_members` includes `"allUsers"`, Cloud Run permits inbound HTTPS connections, delegating identity verification entirely to FastMCP's Google OAuth layer.

### Layer 2: FastMCP Application Layer (Google OAuth 2.0)
* Controlled by the `GOOGLE_AUTH_ENABLED` toggle.
* Implements FastMCP's native `GoogleProvider` OAuth proxy.
* Exposes standard OAuth Protected Resource metadata at `/.well-known/oauth-protected-resource/sse` and `/.well-known/oauth-protected-resource/mcp`.
* **CIMD (Client ID Metadata Document) Support**: FastMCP automatically verifies Claude's client identity from Anthropic's published URLs (`enable_cimd = True`), enabling seamless one-click sign-in on Claude Web.
* **Secret Storage**: Credentials (`GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`) are stored in Google Secret Manager and injected at container startup.

---

## 6. Supported Transport Protocols

FastMCP supports three transport protocols configured via the `FASTMCP_TRANSPORT` environment variable:

### 1. Modern Streamable HTTP (`streamable-http`) - Recommended
* **Mounted Endpoint**: `https://<service-url>/mcp`
* **Specification**: MCP 2025-03-26 Streamable HTTP transport.
* **Standard**: Uses standard HTTP POST requests with streaming chunked responses.
* **Client Compatibility**: Required for Claude Web (eliminates the SSE deprecation warning) and Antigravity CLI.

### 2. Legacy HTTP+SSE (`sse`)
* **Mounted Endpoint**: `https://<service-url>/sse`
* **Specification**: MCP 2024-11-05 Server-Sent Events draft.
* **Client Compatibility**: Legacy desktop clients and older MCP inspectors.

### 3. Local Stdio (`stdio`)
* Communicates directly via standard input and standard output.
* Used for local command-line testing via `fastmcp run` or terminal debugging.

---

## 7. Connecting MCP Clients

### A. Claude Web (claude.ai)
1. In Claude.ai, open **Settings** > **Integrations** > **Add custom connector**.
2. **Connector URL**: `https://cube-mcp-h3ungosjsa-el.a.run.app/mcp`
3. **Authentication**: Select **Sign in now**.
4. **OAuth Client**: Select **Use Claude’s published identity (Recommended)**.
5. **Request Headers**: Leave blank.
6. Click **Save** and complete the Google login prompt.

### B. Antigravity CLI
Configured globally in [~/.gemini/config/mcp_config.json](file:///home/angelo/.gemini/config/mcp_config.json):

```json
{
  "mcpServers": {
    "cube-core": {
      "command": "npx",
      "args": [
        "-y",
        "mcp-remote",
        "https://cube-mcp-h3ungosjsa-el.a.run.app/mcp"
      ]
    }
  }
}
```

### C. Claude Desktop (`claude_desktop_config.json`)
```json
{
  "mcpServers": {
    "cube-core": {
      "command": "npx",
      "args": [
        "-y",
        "mcp-remote",
        "https://cube-mcp-h3ungosjsa-el.a.run.app/mcp"
      ]
    }
  }
}
```

---

## 8. Build & Deployment Runbook

### Building and Pushing the FastMCP Image
Because Docker is not installed on local workstations, images are compiled and pushed via Google Cloud Build:

```bash
cd src/fastmcp && /home/angelo/Downloads/google-cloud-sdk/bin/gcloud builds submit \
  --project=cube-core-mcp \
  --region=asia-south1 \
  --impersonate-service-account="terraform@cube-core-mcp.iam.gserviceaccount.com" \
  --tag="asia-south1-docker.pkg.dev/cube-core-mcp/cube-repo/fastmcp-api:latest"
```

### Updating Cloud Run Revisions
To trigger a new revision deployment using the updated image:

```bash
/home/angelo/Downloads/google-cloud-sdk/bin/gcloud run services update cube-mcp \
  --region=asia-south1 \
  --project=cube-core-mcp \
  --impersonate-service-account="terraform@cube-core-mcp.iam.gserviceaccount.com" \
  --container=fastmcp \
  --image="asia-south1-docker.pkg.dev/cube-core-mcp/cube-repo/fastmcp-api:latest"
```

---

## 9. Automated Testing & Verification

Run tests, linting, and strict type checking inside the local environment:

```bash
cd src/fastmcp

# 1. Run unit test suite
uv run pytest tests/ -v

# 2. Run Ruff linter
uv run ruff check .

# 3. Run strict Mypy type validation
uv run mypy src
```
All modules pass with 0 linting errors, 0 type errors, and 100% test pass rate.
