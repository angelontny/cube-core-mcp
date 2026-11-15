# Cube Core Modeling & Configuration Reference

This document provides a comprehensive technical reference for semantic data modeling in **Cube Core** ([src/cube/](file:///home/angelo/projects/cube-core-mcp/src/cube/)), including YAML syntax conventions, dynamic table prefixing, join semantics, calculated measures, and environment variables.

---

## 1. Directory Structure

```text
src/cube/
├── Dockerfile                  # Production container packaging (cubejs/cube:latest)
├── cube.js                     # Core server configuration & cache options
└── model/
    └── cubes/                  # Declarative semantic models
        ├── orders.yml          # Order-level facts & revenue rollups
        ├── order_items.yml     # Line-item grain sales facts
        ├── products.yml        # Catalog dimension table
        └── users.yml           # Customer demographic dimension
```

---

## 2. Dynamic Table Prefixing (`| safe`)

All cubes must reference physical BigQuery tables dynamically via Jinja:

```yaml
cubes:
  - name: orders
    sql_table: "{{ env_var('CUBEJS_REPORTING_TABLE_PREFIX', 'analytics') | safe }}.fct_orders"
```

### Critical Rules
1. **The `| safe` Filter is Mandatory:** Without `| safe`, Cube's Jinja parser escapes quotation marks and brackets, producing invalid tokens such as `""analytics".fct_orders"`.
2. **Environment Evaluation:**
   * **Single-Project Mode:** `CUBEJS_REPORTING_TABLE_PREFIX` evaluates to `analytics`.
   * **Cross-Project Mode:** `CUBEJS_REPORTING_TABLE_PREFIX` evaluates to `` `external-project-id`.analytics ``.

---

## 3. Semantic Schema Definition Patterns

### 3.1 Entity Joins
Declare relationships explicitly with directional cardinality:

```yaml
joins:
  - name: users
    relationship: many_to_one
    sql: "{CUBE}.user_id = {users.user_id}"

  - name: products
    relationship: many_to_one
    sql: "{CUBE}.product_id = {products.product_id}"
```

### 3.2 Dimensions
```yaml
dimensions:
  - name: order_id
    sql: order_id
    type: number
    primary_key: true
    description: "Primary key of the order."

  - name: order_status
    sql: order_status
    type: string
    description: "Status: Complete, Shipped, Processing, Cancelled, Returned."

  - name: created_at
    sql: created_at
    type: time
    description: "Timestamp when the order was placed."
```

### 3.3 Governed Measures
```yaml
measures:
  - name: count
    type: count
    description: "Total number of orders."

  - name: total_revenue
    type: sum
    sql: total_amount
    description: "Gross merchandise value across all orders."

  - name: completed_orders_count
    type: count
    filters:
      - sql: "{CUBE}.order_status = 'Complete'"
    description: "Number of completed orders."

  # Calculated ratio measure with divide-by-zero protection
  - name: profit_margin_rate
    type: number
    sql: "ROUND(SAFE_DIVIDE({total_profit}, {total_revenue}) * 100, 2)"
    description: "Gross profit margin percentage across all orders."
```

### 3.4 Pre-aggregations (L2 Cube Store Cache)
```yaml
pre_aggregations:
  - name: orders_status_summary
    type: rollup
    measures:
      - count
      - total_revenue
      - total_profit
    dimensions:
      - order_status
```

---

## 4. Runtime Environment Variables

| Variable Name | Required | Default | Purpose |
| :--- | :--- | :--- | :--- |
| `CUBEJS_DB_TYPE` | Yes | `bigquery` | Database driver selection. |
| `CUBEJS_DB_BQ_PROJECT_ID` | Yes | - | GCP Project ID under which BigQuery jobs run. |
| `CUBEJS_REPORTING_TABLE_PREFIX`| Yes | `analytics` | Dynamically computed table prefix (`dataset` or `` `proj`.dataset ``). |
| `CUBEJS_DB_BQ_LOCATION` | Yes | `asia-south1` | Regional location of BigQuery datasets. |
| `CUBEJS_DEV_MODE` | No | `false` | Disables hot-reloading and web UI in production. |
| `CUBEJS_API_SECRET` | Yes | - | Secret key used to sign and verify Cube JWT tokens. |
| `CUBEJS_PORT` | No | `4000` | Port on which Cube Core listens. |
| `CUBEJS_CUBESTORE_HOST` | No | `10.10.0.10` | Private IP of the Cube Store cache node. |
| `CUBEJS_CUBESTORE_PORT` | No | `3030` | MySQL wire port for Cube Store. |
| `CUBEJS_DB_EXPORT_BUCKET` | No | - | GCS bucket for BigQuery `EXPORT DATA` Parquet staging. |
| `CUBEJS_TELEMETRY` | No | `false` | Disables anonymous telemetry reporting. |
