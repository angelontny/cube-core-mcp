"""Payload compression formatters to minimize LLM context window consumption.

Transforms verbose Cube JSON payloads into token-efficient Markdown tables and summaries.
"""

from typing import Any


def format_metadata_to_markdown(meta: dict[str, Any]) -> str:
    """Format Cube /v1/meta output into a dense, token-efficient Markdown data catalog."""
    cubes = meta.get("cubes", [])
    if not cubes:
        return "No cubes or semantic models defined in Cube Core."

    lines: list[str] = ["# Semantic Data Catalog", ""]

    for cube in cubes:
        name = cube.get("name", "Unnamed Cube")
        title = cube.get("title", name)
        description = cube.get("description", "No description provided.")

        lines.append(f"## Cube: `{name}` ({title})")
        lines.append(f"_{description}_\n")

        # Dimensions
        dimensions = cube.get("dimensions", [])
        if dimensions:
            lines.append("### Dimensions")
            lines.append("| Dimension | Type | Description |")
            lines.append("| :--- | :--- | :--- |")
            for dim in dimensions:
                dim_name = dim.get("name", "")
                dim_type = dim.get("type", "string")
                dim_desc = dim.get("description", "-")
                lines.append(f"| `{dim_name}` | `{dim_type}` | {dim_desc} |")
            lines.append("")

        # Measures
        measures = cube.get("measures", [])
        if measures:
            lines.append("### Measures")
            lines.append("| Measure | Type | Description |")
            lines.append("| :--- | :--- | :--- |")
            for measure in measures:
                meas_name = measure.get("name", "")
                meas_type = measure.get("type", "number")
                meas_desc = measure.get("description", "-")
                lines.append(f"| `{meas_name}` | `{meas_type}` | {meas_desc} |")
            lines.append("")

        # Segments
        segments = cube.get("segments", [])
        if segments:
            lines.append("### Segments (Filters)")
            lines.append("| Segment | Description |")
            lines.append("| :--- | :--- |")
            for seg in segments:
                seg_name = seg.get("name", "")
                seg_desc = seg.get("description", "-")
                lines.append(f"| `{seg_name}` | {seg_desc} |")
            lines.append("")

        # Pre-aggregations
        pre_aggs = cube.get("preAggregations", [])
        if pre_aggs:
            lines.append("### Pre-aggregations (L2 Cache)")
            for pa in pre_aggs:
                pa_name = pa.get("name", "")
                pa_type = pa.get("type", "rollup")
                lines.append(f"- `{pa_name}` (`{pa_type}`)")
            lines.append("")

        lines.append("---")
        lines.append("")

    return "\n".join(lines).strip()


def format_load_result_to_markdown(
    load_result: dict[str, Any], max_rows: int = 50
) -> str:
    """Format Cube /v1/load JSON result into a Markdown table with cache metadata."""
    data = load_result.get("data", [])
    if not data:
        return "Query executed successfully. Result set is empty (0 rows)."

    # Collect column headers from the first record
    headers = list(data[0].keys())

    lines: list[str] = []
    lines.append("| " + " | ".join(headers) + " |")
    lines.append("| " + " | ".join([":---" for _ in headers]) + " |")

    display_rows = data[:max_rows]
    for row in display_rows:
        row_values = [
            str(row.get(h, "")) if row.get(h) is not None else "NULL" for h in headers
        ]
        lines.append("| " + " | ".join(row_values) + " |")

    lines.append("")

    # Summary and Cache status
    total_count = len(data)
    truncation_note = (
        f"\n_Showing {len(display_rows)} of {total_count} rows._"
        if total_count > max_rows
        else f"\n_Total rows: {total_count}_"
    )
    lines.append(truncation_note)

    # Cache metadata
    used_pre_aggs = load_result.get("usedPreAggregations", {})
    external = load_result.get("external", False)
    ext_db = load_result.get("extDbType", "none")
    refresh_time = load_result.get("lastRefreshTime")

    cache_info: list[str] = []
    if used_pre_aggs:
        pa_names = list(used_pre_aggs.keys())
        cache_info.append(
            f"L2 Pre-aggregation Match: `{', '.join(pa_names)}` ({ext_db})"
        )
    elif external:
        cache_info.append(f"Accelerated by external store: `{ext_db}`")
    else:
        cache_info.append("Executed directly against warehouse (BigQuery)")

    if refresh_time:
        cache_info.append(f"Cache Timestamp: `{refresh_time}`")

    lines.append(f"_Execution Metadata: {' | '.join(cache_info)}_")

    return "\n".join(lines)


def format_sql_result_to_markdown(
    schema: list[dict[str, str]],
    data_rows: list[list[Any]],
    used_pre_aggs: dict[str, Any] | None = None,
    max_rows: int = 50,
) -> str:
    """Format NDJSON /v1/cubesql result into a Markdown table."""
    if not schema:
        return "Query executed successfully. Result schema is empty."

    headers = [col.get("name", f"col_{idx}") for idx, col in enumerate(schema)]

    if not data_rows:
        return f"Query returned 0 rows.\n\nColumns: {', '.join([f'`{h}`' for h in headers])}"

    lines: list[str] = []
    lines.append("| " + " | ".join(headers) + " |")
    lines.append("| " + " | ".join([":---" for _ in headers]) + " |")

    display_rows = data_rows[:max_rows]
    for row in display_rows:
        row_values = [str(val) if val is not None else "NULL" for val in row]
        lines.append("| " + " | ".join(row_values) + " |")

    lines.append("")
    total_count = len(data_rows)
    truncation_note = (
        f"_Showing {len(display_rows)} of {total_count} rows._"
        if total_count > max_rows
        else f"_Total rows: {total_count}_"
    )
    lines.append(truncation_note)

    if used_pre_aggs:
        pa_names = list(used_pre_aggs.keys())
        lines.append(f"_L2 Pre-aggregations: {', '.join(pa_names)}_")

    return "\n".join(lines)


def format_explain_to_markdown(explain_result: dict[str, Any]) -> str:
    """Format /v1/sql query planner output into fenced SQL and cache routing analysis."""
    sql_queries = explain_result.get("sql", {})
    if isinstance(sql_queries, dict):
        raw_sql = sql_queries.get("sql", [str(sql_queries)])
    elif isinstance(sql_queries, list):
        raw_sql = sql_queries
    else:
        raw_sql = [str(sql_queries)]

    formatted_sql = "\n\n".join(raw_sql) if isinstance(raw_sql, list) else str(raw_sql)

    lines: list[str] = [
        "### Generated Warehouse SQL",
        "```sql",
        formatted_sql,
        "```",
        "",
    ]

    pre_aggs = explain_result.get("preAggregations", [])
    if pre_aggs:
        lines.append("### Target Pre-aggregations (L2 Cache)")
        for pa in pre_aggs:
            pa_id = pa.get("preAggregationId", "unknown")
            pa_table = pa.get("tableName", "unknown")
            pa_type = pa.get("type", "rollup")
            external = pa.get("external", False)
            lines.append(
                f"- **{pa_id}** (`{pa_type}`) -> Table: `{pa_table}` (Cube Store: {external})"
            )
        lines.append("")

    match_results = explain_result.get("rollupMatchResults", [])
    if match_results:
        lines.append("### Rollup Match Evaluations")
        for mr in match_results:
            name = mr.get("name", "unknown")
            can_use = mr.get("canUsePreAggregation", False)
            lines.append(f"- `{name}`: can_use = **{can_use}**")
        lines.append("")

    return "\n".join(lines).strip()
