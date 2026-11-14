"""Unit tests for payload formatters."""

from cube_fastmcp.formatters import (
    format_explain_to_markdown,
    format_load_result_to_markdown,
    format_metadata_to_markdown,
    format_sql_result_to_markdown,
)


def test_format_metadata_to_markdown() -> None:
    sample_meta = {
        "cubes": [
            {
                "name": "orders",
                "title": "Orders",
                "description": "E-commerce customer orders.",
                "dimensions": [
                    {
                        "name": "orders.order_id",
                        "type": "number",
                        "description": "Primary key",
                    },
                    {
                        "name": "orders.order_status",
                        "type": "string",
                        "description": "Status",
                    },
                ],
                "measures": [
                    {
                        "name": "orders.count",
                        "type": "number",
                        "description": "Total order count",
                    },
                    {
                        "name": "orders.total_revenue",
                        "type": "number",
                        "description": "Gross sales",
                    },
                ],
                "preAggregations": [
                    {"name": "orders_status_summary", "type": "rollup"}
                ],
            }
        ]
    }
    output = format_metadata_to_markdown(sample_meta)
    assert "## Cube: `orders` (Orders)" in output
    assert "`orders.order_id`" in output
    assert "`orders.count`" in output
    assert "orders_status_summary" in output


def test_format_load_result_to_markdown() -> None:
    sample_load = {
        "data": [
            {"orders.order_status": "Complete", "orders.count": 45000},
            {"orders.order_status": "Shipped", "orders.count": 32000},
        ],
        "usedPreAggregations": {"orders.orders_status_summary": {"type": "rollup"}},
        "extDbType": "cubestore",
        "lastRefreshTime": "2026-11-13T18:00:00Z",
    }
    output = format_load_result_to_markdown(sample_load)
    assert "| orders.order_status | orders.count |" in output
    assert "| Complete | 45000 |" in output
    assert "L2 Pre-aggregation Match" in output
    assert "cubestore" in output


def test_format_sql_result_to_markdown() -> None:
    schema = [
        {"name": "status", "column_type": "Utf8"},
        {"name": "total", "column_type": "Int64"},
    ]
    data_rows = [
        ["Complete", 12345],
        ["Cancelled", 543],
    ]
    output = format_sql_result_to_markdown(schema, data_rows)
    assert "| status | total |" in output
    assert "| Complete | 12345 |" in output
    assert "_Total rows: 2_" in output


def test_format_explain_to_markdown() -> None:
    sample_explain = {
        "sql": ["SELECT status, count(*) FROM `orders` GROUP BY 1"],
        "preAggregations": [
            {
                "preAggregationId": "orders.orders_status_summary",
                "tableName": "dev_pre_aggregations.orders_status_summary",
                "type": "rollup",
                "external": True,
            }
        ],
        "rollupMatchResults": [
            {"name": "orders.orders_status_summary", "canUsePreAggregation": True}
        ],
    }
    output = format_explain_to_markdown(sample_explain)
    assert "```sql" in output
    assert "SELECT status, count(*)" in output
    assert "Target Pre-aggregations (L2 Cache)" in output
    assert "can_use = **True**" in output
