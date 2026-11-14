"""FastMCP Server exposing the Cube Core Semantic Layer to LLM Clients.

Supports:
- Google OAuth 2.0 authentication via GoogleProvider
- Semantic query execution with L1/L2 cache metadata
- Arbitrary SQL query execution via Cube SQL API (/v1/cubesql)
- Schema catalog discovery and query explanation
- Automatic token-optimized Markdown formatting
"""

import logging
import os
from typing import Any, Literal, cast

from fastmcp import FastMCP
from fastmcp.server.auth.providers.google import GoogleProvider

from cube_fastmcp.config import settings
from cube_fastmcp.cube_client import CubeClientError, cube_client
from cube_fastmcp.formatters import (
    format_explain_to_markdown,
    format_load_result_to_markdown,
    format_metadata_to_markdown,
    format_sql_result_to_markdown,
)

# Configure logging
logging.basicConfig(
    level=getattr(logging, settings.log_level.upper(), logging.INFO),
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("cube_fastmcp.server")

# Configure authentication provider if Google OAuth is explicitly enabled and credentials configured
auth_provider = None
if settings.google_auth_enabled:
    if not settings.google_client_id:
        logger.warning(
            "GOOGLE_AUTH_ENABLED is true, but GOOGLE_CLIENT_ID is not configured."
        )
    else:
        logger.info(
            f"Enabling FastMCP Google OAuth provider with Client ID: {settings.google_client_id[:12]}..."
        )
        auth_provider = GoogleProvider(
            client_id=settings.google_client_id,
            client_secret=settings.google_client_secret or "",
            base_url=settings.fastmcp_public_url,
        )

# Initialize FastMCP Server instance
mcp = FastMCP(
    name="Cube Semantic Layer MCP",
    auth=auth_provider,
)


@mcp.tool(
    name="get_metadata",
    description=(
        "Retrieve the complete semantic data catalog from Cube Core. Returns all defined cubes, "
        "dimensions, measures, segments, data types, descriptions, and pre-aggregations. "
        "Use this tool first to discover valid table names, column names, and metrics."
    ),
)
async def get_metadata() -> str:
    """Fetch the semantic schema catalog formatted as token-efficient Markdown."""
    try:
        raw_meta = await cube_client.get_metadata()
        return format_metadata_to_markdown(raw_meta)
    except CubeClientError as err:
        logger.error(f"Failed to fetch metadata from Cube Core: {err}")
        return f"Error fetching metadata from Cube Core (HTTP {err.status_code}): {err}"
    except Exception as exc:
        logger.exception("Unexpected error fetching metadata")
        return f"Unexpected error fetching metadata: {exc}"


@mcp.tool(
    name="run_semantic_query",
    description=(
        "Execute a standardized semantic query against Cube Core using governed measures and dimensions. "
        "Guarantees metric consistency and automatically leverages L1 in-memory and L2 Cube Store "
        "pre-aggregation caches. Formats the response as a compact Markdown table."
    ),
)
async def run_semantic_query(
    measures: list[str],
    dimensions: list[str] | None = None,
    filters: list[dict[str, Any]] | None = None,
    time_dimensions: list[dict[str, Any]] | None = None,
    order: dict[str, str] | None = None,
    limit: int | None = 100,
) -> str:
    """Execute a structured semantic query against Cube Core.

    Args:
        measures: List of measure identifiers (e.g. ['orders.count', 'orders.total_revenue']).
        dimensions: Optional list of dimension identifiers (e.g. ['orders.order_status', 'users.country']).
        filters: Optional filter objects: [{'member': 'orders.order_status', 'operator': 'equals', 'values': ['Complete']}].
        time_dimensions: Optional time filters: [{'dimension': 'orders.created_at', 'dateRange': 'Last year', 'granularity': 'month'}].
        order: Optional ordering: {'orders.total_revenue': 'desc'}.
        limit: Max rows to return (default 100).
    """
    query: dict[str, Any] = {"measures": measures}
    if dimensions:
        query["dimensions"] = dimensions
    if filters:
        query["filters"] = filters
    if time_dimensions:
        query["timeDimensions"] = time_dimensions
    if order:
        query["order"] = order
    if limit:
        query["limit"] = limit

    try:
        raw_result = await cube_client.load_semantic_query(query)
        return format_load_result_to_markdown(raw_result)
    except CubeClientError as err:
        logger.error(f"Failed to run semantic query: {err}")
        return f"Error executing semantic query (HTTP {err.status_code}): {err}"
    except Exception as exc:
        logger.exception("Unexpected error executing semantic query")
        return f"Unexpected error executing semantic query: {exc}"


@mcp.tool(
    name="run_sql_query",
    description=(
        "Execute an arbitrary SQL query against Cube Core's SQL API (/cubejs-api/v1/cubesql). "
        "Use this for custom or niche analytical questions that are not pre-modeled as measures. "
        "Cubes act as tables, dimensions act as columns. Supports PostgreSQL syntax, standard aggregates "
        "(SUM, COUNT, AVG), window functions, CTEs, and pushdown to BigQuery."
    ),
)
async def run_sql_query(query: str, timezone: str = "UTC") -> str:
    """Execute an arbitrary SQL query via Cube SQL API and stream results.

    Args:
        query: Standard SQL query (e.g. 'SELECT orders.order_status, COUNT(*) FROM orders GROUP BY 1 LIMIT 20').
        timezone: Timezone for timestamp operations (default 'UTC').
    """
    try:
        schema, data_rows, used_pre_aggs = await cube_client.run_sql_query(
            query, timezone=timezone
        )
        return format_sql_result_to_markdown(
            schema, data_rows, used_pre_aggs=used_pre_aggs
        )
    except CubeClientError as err:
        logger.error(f"Failed to run SQL query: {err}")
        return f"Error executing SQL query (HTTP {err.status_code}): {err}"
    except Exception as exc:
        logger.exception("Unexpected error executing SQL query")
        return f"Unexpected error executing SQL query: {exc}"


@mcp.tool(
    name="explain_sql_query",
    description=(
        "Inspect the BigQuery SQL query and cache routing plan that Cube Core would generate "
        "without executing the query. Useful for debugging pre-aggregation rollups and inspecting data warehouse costs."
    ),
)
async def explain_sql_query(
    measures: list[str],
    dimensions: list[str] | None = None,
    filters: list[dict[str, Any]] | None = None,
) -> str:
    """Explain the query plan and target BigQuery SQL."""
    query: dict[str, Any] = {"measures": measures}
    if dimensions:
        query["dimensions"] = dimensions
    if filters:
        query["filters"] = filters

    try:
        raw_explain = await cube_client.explain_sql_query(query)
        return format_explain_to_markdown(raw_explain)
    except CubeClientError as err:
        logger.error(f"Failed to explain query: {err}")
        return f"Error explaining query (HTTP {err.status_code}): {err}"
    except Exception as exc:
        logger.exception("Unexpected error explaining query")
        return f"Unexpected error explaining query: {exc}"


def main() -> None:
    """Entrypoint for running FastMCP server on Cloud Run or locally."""
    # Detect port from Cloud Run environment variable $PORT or fall back to settings
    port = int(os.environ.get("PORT", str(settings.port)))
    host = settings.host
    raw_transport = os.environ.get("FASTMCP_TRANSPORT", "sse")
    valid_transports = {"stdio", "http", "sse", "streamable-http"}
    transport = cast(
        Literal["stdio", "http", "sse", "streamable-http"],
        raw_transport if raw_transport in valid_transports else "sse",
    )

    logger.info(
        f"Starting Cube FastMCP server on {host}:{port} with transport '{transport}'"
    )
    mcp.run(transport=transport, host=host, port=port)


if __name__ == "__main__":
    main()
