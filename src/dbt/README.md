# dbt Project: `cube_thelook`

This directory houses the native dbt project transforming Google BigQuery's `thelook_ecommerce` raw tables into curated dimensional models and analytical facts in the `analytics` dataset.

The compiled metadata (`target/manifest.json`) from this project is mounted into the **Cube Core** semantic engine (`src/cube/`) to generate metrics and dimensions accessible via the Model Context Protocol (FastMCP).

---

## Architecture & Directory Layout

```text
src/dbt/
├── dbt_project.yml          # Project definition and model configurations
├── profiles.yml             # Connection profile targeting BigQuery via OAuth/ADC
├── README.md                # Execution runbook and commands
└── models/
    ├── sources.yml          # Source declarations for raw thelook_ecommerce tables
    ├── staging/             # Cleaned 1:1 views of raw tables
    │   ├── stg_orders.sql
    │   ├── stg_order_items.sql
    │   ├── stg_products.sql
    │   └── stg_users.sql
    └── marts/               # Dimensional models & fact tables materialized as BigQuery tables
        ├── schema.yml       # Column documentation & test definitions
        ├── dim_products.sql # Product catalog with category, brand, and margin metrics
        ├── dim_users.sql    # Customer demographics with age brackets & geography
        ├── fct_orders.sql   # Order-level aggregations (total amount, item count, margin)
        └── fct_order_items.sql # Line-item transactions with unit margins & delivery status
```

---

## Local Development & Execution

### 1. Prerequisites
Ensure you have authenticated your local workstation Application Default Credentials (ADC) as outlined in [terraform_setup_and_authentication.md](file:///home/angelo/projects/cube-core-mcp/docs/guides/terraform_setup_and_authentication.md):

```bash
gcloud auth application-default login
gcloud auth application-default set-quota-project <YOUR_GCP_PROJECT_ID>
```

### 2. Install Dependencies
Using `uv` (recommended) or standard `pip`:

```bash
# From repository root or src/dbt/
uv venv .venv
source .venv/bin/activate
uv pip install dbt-bigquery
```

### 3. Verify Connection (`dbt debug`)
Run from `src/dbt/`:

```bash
export DBT_PROFILES_DIR=.
dbt debug
```
*Confirms connection to your BigQuery dataset `cube-core-mcp.analytics`.*

### 4. Build Models (`dbt build`)
Materializes staging views and mart tables:

```bash
dbt build
```

### 5. Generate Manifest for Cube Core
Cube Core requires the compiled manifest to auto-generate semantic cubes:

```bash
dbt compile
```
The resulting artifact will be located at `src/dbt/target/manifest.json`.
