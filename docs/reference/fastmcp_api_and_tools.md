# FastMCP Analytical Tools & API Reference

This document provides the reference specification for the **FastMCP Python Service** ([src/fastmcp/](file:///home/angelo/projects/cube-core-mcp/src/fastmcp/)), detailing the 4 governed analytical tools, transport protocols, Google OAuth 2.0 implementation, and payload compression formats.

---

## 1. Tool Catalog Summary

| Tool Name | Invocation Purpose | Target Cube Endpoint | Output Format |
| :--- | :--- | :--- | :--- |
| **`get_metadata`** | Schema discovery: cubes, dimensions, measures, segments, and pre-aggregations. | `GET /cubejs-api/v1/meta` | Formatted Markdown Catalog |
| **`run_semantic_query`** | Governed metric queries with automatic L1 in-memory and L2 Cube Store caching. | `POST /cubejs-api/v1/load` | Markdown Table + Cache Summary |
| **`run_sql_query`** | Ad-hoc or exploratory SQL queries using Cube's SQL API with BigQuery pushdown. | `POST /cubejs-api/v1/cubesql` | Markdown Table + Row Summary |
| **`explain_sql_query`** | Query plan inspection, SQL dialect generation, and cache match analysis. | `POST /cubejs-api/v1/explain` | Formatted Plan + Raw SQL Block |

---

## 2. Detailed Tool Specifications

### 2.1 `get_metadata`

Retrieves the complete data catalog modeled in Cube Core. AI assistants should call this tool first to discover valid measure names, dimensions, and join structures.

#### Arguments
*None.*

#### Response Schema
Returns a dense Markdown catalog documenting every cube:
```markdown
# Semantic Data Catalog

## Cube: `orders` (Orders)
_Order-level grain fact table containing total sale amounts, margins, and statuses._

### Dimensions
| Dimension | Type | Description |
| :--- | :--- | :--- |
| `order_id` | `number` | Primary key of the order. |
| `order_status` | `string` | Current status of the order. |
| `created_at` | `time` | Timestamp when the order was placed. |

### Measures
| Measure | Type | Description |
| :--- | :--- | :--- |
| `count` | `count` | Total number of orders. |
| `total_revenue` | `sum` | Gross merchandise value across all orders. |
| `profit_margin_rate` | `number` | Gross profit margin percentage across all orders. |

### Pre-aggregations (L2 Cache)
- `orders_status_summary` (`rollup`)
```

---

### 2.2 `run_semantic_query`

Executes structured analytical queries against Cube Core using governed measures, dimensions, and filters.

#### Arguments
| Parameter | Type | Required | Default | Description | Example |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `measures` | `list[str]` | Yes | - | List of measure names to aggregate. | `["orders.total_revenue", "orders.count"]` |
| `dimensions` | `list[str]` | No | `None` | Dimensions to group by. | `["orders.order_status"]` |
| `filters` | `list[dict]` | No | `None` | Structured filter objects. | `[{"member": "orders.order_status", "operator": "equals", "values": ["Complete"]}]` |
| `time_dimensions` | `list[dict]` | No | `None` | Temporal filters and granularities. | `[{"dimension": "orders.created_at", "dateRange": "Last year", "granularity": "month"}]` |
| `order` | `dict[str, str]` | No | `None` | Ordering specifications. | `{"orders.total_revenue": "desc"}` |
| `limit` | `int` | No | `100` | Maximum rows to return. | `50` |

#### Output Format
Transforms raw Cube JSON into a compact Markdown table followed by execution performance metadata:
```markdown
| orders.order_status | orders.total_revenue | orders.count |
| :--- | :--- | :--- |
| Complete | 185420.50 | 1240 |
| Shipped | 94310.20 | 610 |
| Processing | 43210.00 | 280 |

*Query executed in 42ms via L2 Cube Store Pre-aggregation (orders_status_summary).*
```

---

### 2.3 `run_sql_query`

Executes arbitrary SQL queries using Cube's SQL API (`/v1/cubesql`). Useful for complex analytical operations such as window functions, nested subqueries, and non-modeled metrics.

#### Arguments
| Parameter | Type | Required | Default | Description | Example |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `query` | `str` | Yes | - | SQL query conforming to Cube SQL syntax. | `"SELECT orders.order_status, COUNT(*) FROM orders GROUP BY 1"` |
| `timezone` | `str` | No | `"UTC"` | Timezone for timestamp operations. | `"America/New_York"` |

#### Streaming & Parsing Mechanics
* FastMCP connects to `/cubejs-api/v1/cubesql` and parses the newline-delimited JSON (NDJSON) stream.
* The first line provides the schema definition (`schema` frame).
* Subsequent lines stream individual record batches (`data` frame).
* The final line contains execution metadata (`stats` frame), detailing pre-aggregation matches.

---

### 2.4 `explain_sql_query`

Generates the compiled BigQuery SQL query and cache routing plan without executing the query against the warehouse.

#### Arguments
| Parameter | Type | Required | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| `measures` | `list[str]` | Yes | - | Measures to inspect. |
| `dimensions` | `list[str]` | No | `None` | Dimensions to inspect. |
| `filters` | `list[dict]` | No | `None` | Filter conditions. |

#### Output Format
```markdown
### Query Routing Plan
* **Cache Target:** `L2 Columnar Pre-Aggregation` (Hit: `orders_status_summary`)
* **Underlying Warehouse Engine:** `Google BigQuery (Standard SQL)`

```sql
SELECT
  `orders`.order_status `orders__order_status`,
  sum(`orders`.total_amount) `orders__total_revenue`,
  count(`orders`.order_id) `orders__count`
FROM
  `analytics`.fct_orders AS `orders`
GROUP BY
  1
```
```

---

## 3. Security & RFC 6750 Google OAuth 2.0

When `GOOGLE_AUTH_ENABLED = true`, FastMCP automatically configures `GoogleProvider`:

1. **Discovery Endpoint:**
   Clients query `GET /.well-known/oauth-protected-resource/mcp`. FastMCP returns:
   ```json
   {
     "resource": "https://<service-url>/mcp",
     "authorization_servers": ["https://<service-url>/"],
     "scopes_supported": ["openid"],
     "bearer_methods_supported": ["header"]
   }
   ```
2. **Challenge Header:**
   Unauthenticated requests receive:
   `HTTP/1.1 401 Unauthorized`
   `WWW-Authenticate: Bearer realm="Cube Semantic Layer MCP", as_uri="https://<service-url>/"`
3. **Token Verification:**
   FastMCP verifies the Bearer JWT against Google's public key endpoint (`https://www.googleapis.com/oauth2/v3/certs`) and checks expiration and audience.
