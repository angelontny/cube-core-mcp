"""Unit tests for FastMCP server tools."""

from unittest.mock import AsyncMock

import pytest

from cube_fastmcp import server


@pytest.mark.asyncio
async def test_get_metadata_tool(monkeypatch: pytest.MonkeyPatch) -> None:
    mock_meta = {
        "cubes": [
            {
                "name": "orders",
                "title": "Orders",
                "dimensions": [{"name": "orders.status", "type": "string"}],
                "measures": [{"name": "orders.count", "type": "number"}],
            }
        ]
    }
    monkeypatch.setattr(
        server.cube_client, "get_metadata", AsyncMock(return_value=mock_meta)
    )

    result = await server.get_metadata()
    assert "## Cube: `orders`" in result
    assert "`orders.status`" in result
    assert "`orders.count`" in result


@pytest.mark.asyncio
async def test_run_semantic_query_tool(monkeypatch: pytest.MonkeyPatch) -> None:
    mock_load = {
        "data": [{"orders.count": 42}],
        "usedPreAggregations": {},
    }
    monkeypatch.setattr(
        server.cube_client, "load_semantic_query", AsyncMock(return_value=mock_load)
    )

    result = await server.run_semantic_query(measures=["orders.count"])
    assert "| orders.count |" in result
    assert "| 42 |" in result


@pytest.mark.asyncio
async def test_run_sql_query_tool(monkeypatch: pytest.MonkeyPatch) -> None:
    mock_schema = [{"name": "country", "column_type": "Utf8"}]
    mock_data = [["USA"], ["India"]]
    monkeypatch.setattr(
        server.cube_client,
        "run_sql_query",
        AsyncMock(return_value=(mock_schema, mock_data, None)),
    )

    result = await server.run_sql_query("SELECT country FROM users GROUP BY 1")
    assert "| country |" in result
    assert "| USA |" in result
    assert "| India |" in result


@pytest.mark.asyncio
async def test_explain_sql_query_tool(monkeypatch: pytest.MonkeyPatch) -> None:
    mock_explain = {
        "sql": ["SELECT count(*) FROM orders"],
        "preAggregations": [],
    }
    monkeypatch.setattr(
        server.cube_client, "explain_sql_query", AsyncMock(return_value=mock_explain)
    )

    result = await server.explain_sql_query(measures=["orders.count"])
    assert "```sql" in result
    assert "SELECT count(*) FROM orders" in result
