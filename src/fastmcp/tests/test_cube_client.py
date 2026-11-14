"""Unit tests for CubeClient."""

import json
from typing import Any

import httpx
import pytest

from cube_fastmcp.cube_client import CubeClient, CubeClientError


@pytest.mark.asyncio
async def test_get_metadata_success(monkeypatch: pytest.MonkeyPatch) -> None:
    expected_data = {"cubes": [{"name": "orders"}]}

    async def mock_get(self: Any, url: str, **kwargs: Any) -> httpx.Response:
        return httpx.Response(
            200, json=expected_data, request=httpx.Request("GET", url)
        )

    monkeypatch.setattr(httpx.AsyncClient, "get", mock_get)

    client = CubeClient(base_url="http://mock-cube:4000")
    result = await client.get_metadata()
    assert result == expected_data


@pytest.mark.asyncio
async def test_load_semantic_query_success(monkeypatch: pytest.MonkeyPatch) -> None:
    expected_data = {"data": [{"orders.count": 100}], "usedPreAggregations": {}}

    async def mock_post(self: Any, url: str, **kwargs: Any) -> httpx.Response:
        return httpx.Response(
            200, json=expected_data, request=httpx.Request("POST", url)
        )

    monkeypatch.setattr(httpx.AsyncClient, "post", mock_post)

    client = CubeClient(base_url="http://mock-cube:4000")
    result = await client.load_semantic_query({"measures": ["orders.count"]})
    assert result == expected_data


@pytest.mark.asyncio
async def test_run_sql_query_ndjson(monkeypatch: pytest.MonkeyPatch) -> None:
    ndjson_body = (
        json.dumps(
            {
                "schema": [{"name": "status", "column_type": "Utf8"}],
                "usedPreAggregations": {},
            }
        )
        + "\n"
        + json.dumps({"data": [["Complete"], ["Shipped"]]})
        + "\n"
    )

    async def mock_post(self: Any, url: str, **kwargs: Any) -> httpx.Response:
        return httpx.Response(200, text=ndjson_body, request=httpx.Request("POST", url))

    monkeypatch.setattr(httpx.AsyncClient, "post", mock_post)

    client = CubeClient(base_url="http://mock-cube:4000")
    schema, data, _pre_aggs = await client.run_sql_query("SELECT status FROM orders")
    assert len(schema) == 1
    assert schema[0]["name"] == "status"
    assert len(data) == 2
    assert data[0] == ["Complete"]
    assert data[1] == ["Shipped"]


@pytest.mark.asyncio
async def test_client_error_handling(monkeypatch: pytest.MonkeyPatch) -> None:
    async def mock_post(self: Any, url: str, **kwargs: Any) -> httpx.Response:
        return httpx.Response(
            500, text="Internal Server Error", request=httpx.Request("POST", url)
        )

    monkeypatch.setattr(httpx.AsyncClient, "post", mock_post)

    client = CubeClient(base_url="http://mock-cube:4000")
    with pytest.raises(CubeClientError) as exc_info:
        await client.load_semantic_query({"measures": ["orders.count"]})
    assert exc_info.value.status_code == 500
