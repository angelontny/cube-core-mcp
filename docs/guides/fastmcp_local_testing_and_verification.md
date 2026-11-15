# FastMCP Local Testing & Verification Guide

This guide documents the procedures for inspecting, testing, and debugging the `cube-fastmcp` Model Context Protocol (MCP) server on a local workstation before deploying to Google Cloud Run.

---

## 1. Prerequisites

Ensure dependencies are installed and synchronized using `uv`:

```bash
cd src/fastmcp
uv sync
```

---

## 2. Automated Test Suite (`pytest`)

The repository includes a comprehensive unit and mock integration test suite verifying payload formatters, async Cube client mechanics (including NDJSON streaming), and server tool handlers:

```bash
cd src/fastmcp
uv run pytest tests/ -v
```

### Static Analysis & Type Checking
```bash
# Linting
uv run ruff check .

# Formatting
uv run ruff format --check .

# Strict type checking
uv run mypy .
```

---

## 3. FastMCP CLI Inspection & Direct Tool Invocation

The `fastmcp` CLI allows interacting with the server directly over standard I/O without needing a GUI or web server.

### A. Inspect Server Registration
```bash
cd src/fastmcp
uv run fastmcp inspect src/cube_fastmcp/server.py
```
*Expected Output:* Displays server metadata, FastMCP version (`4.2.0`), protocol version, and the count of registered tools (4).

### B. List Available Tools and Signatures
```bash
cd src/fastmcp
uv run fastmcp list src/cube_fastmcp/server.py
```
*Expected Output:* Lists all 4 exposed tools:
* `get_metadata()`
* `run_semantic_query(measures, dimensions, filters, time_dimensions, order, limit)`
* `run_sql_query(query, timezone)`
* `explain_sql_query(measures, dimensions, filters)`

### C. Direct Tool Invocation from the Terminal
You can execute specific tools using `fastmcp call`:

```bash
# Call get_metadata
cd src/fastmcp
uv run fastmcp call src/cube_fastmcp/server.py get_metadata

# Call run_sql_query with arguments
uv run fastmcp call src/cube_fastmcp/server.py run_sql_query query="SELECT 1 AS test"

# Call run_semantic_query with JSON arguments
uv run fastmcp call src/cube_fastmcp/server.py run_semantic_query --input-json '{"measures": ["orders.count"]}'
```

---

## 4. Interactive FastMCP Dev Web Inspector UI

FastMCP includes an interactive web UI that lets you inspect schemas, trigger tools with form inputs, and inspect responses in real time:

```bash
cd src/fastmcp
uv run fastmcp dev inspector src/cube_fastmcp/server.py
```

* This spins up a local web server (typically at `http://localhost:5173` or `http://localhost:8000`).
* Open the browser link to see all 4 tools, test parameters interactively, and view live Markdown outputs.

---

## 5. End-to-End Local Testing with Local Cube Core

To test FastMCP against a live Cube Core semantic engine locally:

### Step 1: Run Cube Core Locally
From the project root:
```bash
docker run --rm -it \
  -p 4000:4000 \
  -v "$(pwd)/src/cube/model:/cube/conf/model" \
  -v "$(pwd)/src/cube/cube.js:/cube/conf/cube.js" \
  -e CUBEJS_DB_TYPE=bigquery \
  -e CUBEJS_DB_BQ_PROJECT_ID=cube-core-mcp \
  -e CUBEJS_DB_BQ_LOCATION=asia-south1 \
  -e CUBEJS_DEV_MODE=true \
  -e CUBEJS_API_SECRET="${LOCAL_TEST_SECRET:-$(openssl rand -hex 24)}" \
  -v "$HOME/.config/gcloud/application_default_credentials.json:/root/.config/gcloud/application_default_credentials.json:ro" \
  cubejs/cube:latest
```

### Step 2: Query FastMCP Against Local Cube Core
In a second terminal:
```bash
cd src/fastmcp
export CUBE_API_URL="http://localhost:4000"
export CUBE_API_SECRET="<YOUR_LOCAL_TEST_SECRET>"

# Fetch live metadata catalog
uv run fastmcp call src/cube_fastmcp/server.py get_metadata

# Execute live semantic query
uv run fastmcp call src/cube_fastmcp/server.py run_semantic_query \
  --input-json '{"measures": ["orders.count"], "dimensions": ["orders.order_status"]}'
```

---

## 6. Local Integration with Claude Desktop

To connect your local FastMCP server to **Claude Desktop**, edit your local Claude configuration file:
* **macOS:** `~/Library/Application Support/Claude/claude_desktop_config.json`
* **Linux:** `~/.config/Claude/claude_desktop_config.json`
* **Windows:** `%APPDATA%\Claude\claude_desktop_config.json`

Add the `cube-semantic-layer` server configuration:

```json
{
  "mcpServers": {
    "cube-semantic-layer": {
      "command": "uv",
      "args": [
        "--directory",
        "/home/angelo/projects/cube-core-mcp/src/fastmcp",
        "run",
        "python",
        "-m",
        "cube_fastmcp.server"
      ],
      "env": {
        "FASTMCP_TRANSPORT": "stdio",
        "CUBE_API_URL": "http://localhost:4000",
        "CUBE_API_SECRET": "<YOUR_LOCAL_TEST_SECRET>"
      }
    }
  }
}
```

Restart Claude Desktop. The hammer icon in the chat interface will display the 4 Cube tools, allowing Claude to compose queries against BigQuery autonomously.
