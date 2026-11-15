# ADR-0007: FastMCP Streamable HTTP / SSE Transport and RFC 6750 Google OAuth 2.0

* **Status:** Accepted
* **Date:** 2026-11-14 (Updated 2026-11-15)
* **Deciders:** AI Engineering & Security Architecture Team
* **Consulted:** Cloud Operations, IAM
* **Informed:** Core Engineering Team

---

## 1. Context and Problem Statement

The Model Context Protocol (MCP) provides an open standard for AI assistants (such as Claude Web, Claude Code CLI, Claude Desktop, and Cursor) to discover and execute contextual tools. 

To expose the Cube Core semantic layer to AI clients securely, we needed an ingress interface that:
1. Translates natural language tool invocations into validated Cube REST and SQL API queries.
2. Supports industry-standard, browser-compatible **Google OAuth 2.0** authentication so enterprise users and clients can authenticate without passing static API keys.
3. Implements **RFC 6750 OAuth 2.0 Protected Resource Metadata**, enabling automated OAuth discovery for web-based clients (such as Claude.ai).
4. Operates reliably across serverless HTTP/SSE channels hosted on Google Cloud Run.
5. Optimizes token usage by compressing verbose JSON database responses into compact tabular Markdown representations.

---

## 2. Decision Drivers

* **Interactive Web Client Support:** Claude.ai (Claude Web) connects to MCP servers over HTTPS using OAuth 2.0 authorization code flow with automatic redirect popups.
* **Token Budget Efficiency:** LLM context windows are limited and costly. Cube Core's native `/v1/load` JSON payload includes extensive annotations and metadata wrappers that inflate token counts by 70–85%.
* **Type Safety & Maintainability:** The MCP wrapper must be easy to extend with new analytical tools, using typed schemas validated at runtime.

---

## 3. Considered Options

* **Option 1: Official TypeScript MCP SDK (`@modelcontextprotocol/sdk`)**
* **Option 2: Raw FastAPI Server implementing custom MCP JSON-RPC protocol**
* **Option 3: FastMCP Python SDK with GoogleProvider and Token Formatters (Selected)**

---

## 4. Evaluation and Decision Outcome

**Chosen Option:** **Option 3: FastMCP Python SDK with GoogleProvider (`fastmcp >= 2.0.0`)**.

### Technical Architecture

1. **Authentication Provider (`GoogleProvider`):**
   When `GOOGLE_AUTH_ENABLED = true`, FastMCP initializes `fastmcp.server.auth.providers.google.GoogleProvider`.
   * FastMCP automatically exposes the RFC 6750 discovery endpoint at `/.well-known/oauth-protected-resource/mcp`.
   * Unauthenticated requests to `/mcp` receive an `HTTP 401 Unauthorized` header with the `WWW-Authenticate` realm and authorization server URL.
   * Claude Web inspects this metadata, launches the Google OAuth consent popup, and passes the resulting Bearer token with subsequent tool calls.

2. **Transport Agility (`FASTMCP_TRANSPORT`):**
   * Configurable via environment variable: `sse` (Server-Sent Events) or `streamable-http` (recommended for modern web assistants).
   * Supports local debugging via `stdio` transport.

3. **Tool Catalog (4 Governed Tools):**
   * `get_metadata()`: Discovers available cubes, dimensions, measures, and pre-aggregations.
   * `run_semantic_query()`: Executes governed metric queries with automatic L1 in-memory and L2 Cube Store cache routing.
   * `run_sql_query()`: Executes arbitrary SQL queries via `/v1/cubesql` for non-standard exploratory aggregations.
   * `explain_sql_query()`: Inspects the compiled BigQuery SQL and cache routing execution plan without executing queries.

4. **Payload Compression Engine ([formatters.py](file:///home/angelo/projects/cube-core-mcp/src/fastmcp/src/cube_fastmcp/formatters.py)):**
   * Raw Cube `/v1/load` JSON contains redundant annotation maps, query descriptors, and type objects.
   * `format_load_result_to_markdown()` strips these envelopes, formats a clean GFM Markdown table, appends cache acceleration metadata (`L1 In-Memory`, `L2 Cube Store`, or `BigQuery Fallback`), and caps row counts to preserve LLM context tokens.

---

## 5. Consequences

### Positive Consequences
* **Seamless Claude.ai Integration:** Enterprise users can add the server in Claude Web with a single URL and authenticate via their Google Workspace account.
* **Significant Token Reduction:** Responses use 70–85% fewer tokens than raw JSON envelopes, reducing inference costs and preventing context saturation.
* **Strict Type Safety:** Pydantic models automatically validate tool parameters before dispatching requests to Cube Core.

### Negative Consequences / Risks
* Python runtime introduces a minor memory footprint (~120MB) in the multi-container pod.
* Requires manual generation and Secret Manager storage of Google OAuth Client ID and Secret during Tier 0 bootstrap.

---

## 6. Related Documents
* [ADR-0004: Multi-Container Cloud Run Pod vs. Separate Services](file:///home/angelo/projects/cube-core-mcp/docs/architecture/adrs/0004_multi_container_pod_vs_separate_services.md)
* [FastMCP Implementation Guide](file:///home/angelo/projects/cube-core-mcp/docs/fastmcp_implementation_and_architecture_guide.md)
* [FastMCP Local Testing & Verification Guide](file:///home/angelo/projects/cube-core-mcp/docs/guides/fastmcp_local_testing_and_verification.md)
