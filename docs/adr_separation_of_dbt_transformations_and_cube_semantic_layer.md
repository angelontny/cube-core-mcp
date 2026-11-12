# Architectural Decision Record: Clean Separation of dbt Transformation Layer and Cube Semantic Layer

This document details the architectural decision to decouple the **dbt data transformation pipeline** from the **Cube Core semantic and metrics layer**, establishing a clean boundary where dbt governs warehouse modeling in Google BigQuery and Cube natively governs metrics, joins, caching, and pre-aggregations.

---

## 1. Context & Problem Statement

In modern data platform engineering, defining semantic metrics (e.g., Gross Merchandise Value, gross profit margins, return rates) can be approached in two contrasting ways:

1. **Manifest-Driven Monolithic Coupling**: Defining all schema, relationships, metrics, and caching metadata inside dbt (or attempting to dynamically interpolate Cube data models from dbt's `target/manifest.json` at runtime via `cube_dbt` and Jinja templates).
2. **Decoupled Layered Architecture**: Strictly delineating responsibilities:
   * **dbt** acts as the transformation and modeling engine (the "T" in ELT), producing clean, tested, documented physical relations in BigQuery.
   * **Cube Core** acts as the semantic, metrics, and caching engine, consuming BigQuery relations directly and defining dimensional graphs, joins, calculated measures, and OLAP pre-aggregations.

We evaluated both approaches to determine the most maintainable, reliable, and production-grade architecture for `cube-core-mcp`.

---

## 2. Evaluation of Approach A: Manifest-Driven Dynamic Reflection (`cube_dbt`)

In this pattern, dbt compiles its project metadata into `manifest.json`. A Python helper library (`cube_dbt`) is packaged inside the Cube Core Docker container, and Cube relies on Jinja templates (`model/cubes/*.yml.jinja` or `model/cubes.yml.jinja`) to dynamically generate cubes and dimensions from `manifest.json` when the server boots.

### Limitations & Failure Modes:

#### A. Leaky Abstraction and Asymmetric Feature Support
* **dbt is not an OLAP engine**: dbt is designed to transform and validate relational tables. It does not natively model OLAP pre-aggregations, partitioning strategies, cache invalidation refresh keys, or multi-hop query graphs.
* **The Open-Source `cube_dbt` Boundary**: While Cube Cloud (commercial SaaS) features a proprietary "dbt pull" engine that infers joins from dbt tests, the open-source `cube_dbt` Python library only provides basic structural mapping (`as_cube()`, `as_dimensions()`). It does **not** generate joins, complex measures, or pre-aggregations. Attempting to force these definitions into dbt requires writing custom `meta:` tags and brittle in-house Python parser logic in `globals.py`.

#### B. Runtime Coupling and Failure Domain Expansion
* **Bloated Container Footprint**: Extending the official Node.js `cubejs/cube:latest` container to include Python, `pip`, virtual environments, and external packages (`cube_dbt`) increases container image size, build time, and vulnerability surface area.
* **Cold Boot Latency**: Evaluating Jinja templates and parsing a multi-megabyte `manifest.json` on container boot introduces parsing overhead during Cloud Run cold starts.
* **Deployment Fragility**: Any schema sync error or syntax difference between dbt versions and `cube_dbt` will crash the Cube API during startup, coupling semantic layer availability to dbt pipeline artifacts.

---

## 3. Evaluation of Approach B: Clean Separation of Concerns (Selected Architecture)

In this pattern, dbt and Cube operate as independent, composable layers connected through standard Google BigQuery interfaces:

```
[ BigQuery: raw data ] ──> [ dbt: staging & marts ] ──> [ BigQuery: analytics dataset ]
                                                                   │
                                                (Direct SQL / EXPORT DATA)
                                                                   │
                                                                   ▼
[ Client / FastMCP ] <── [ Cloud Run: Cube Core API ] <── [ Declarative Cube YAML Models ]
                                   │                              (Measures, Joins, Pre-Aggs)
                                   └── (OLAP Cache) ──> [ Cube Store Spot VM + GCS ]
```

### Strategic Advantages:

#### A. First-Class Semantic Expressiveness
* **Native Joins & Graphs**: Entity relationships (`orders` to `users`, `order_items` to `products`) are declared explicitly with precise relationship semantics (`many_to_one`, `one_to_many`).
* **Rich Business Measures**: Complex calculations (e.g., `ROUND(SAFE_DIVIDE({total_profit}, {total_revenue}) * 100, 2)`) and filtered measures (e.g., `completed_orders_count` with SQL predicates) are defined natively where the query planner optimizes them.
* **First-Class Pre-Aggregations**: Rollup tables, partitioning rules, and refresh keys can be directly integrated into each cube to leverage Cube Store.

#### B. Lean, Deterministic Container Execution
* **Zero Python Overhead**: Cube Core runs on its standard Node.js runtime. No Python, pip, or external build dependencies are required in the production Docker image.
* **Instant Container Startup**: Cube loads native YAML schemas instantly into memory, eliminating `manifest.json` parsing delays on Cloud Run cold boots.
* **Independent Lifecycles**: Adding a metric, tuning a cache refresh interval, or adding an OLAP pre-aggregation in Cube requires zero changes to dbt, eliminating redundant dbt compiles or test runs.

---

## 4. Architectural Comparison Matrix

| Capability | Approach A: Manifest Reflection (`cube_dbt`) | Approach B: Clean Separation (Selected) |
| :--- | :--- | :--- |
| **Primary Responsibility** | Blended (dbt drives both tables and semantic layer) | Strict (dbt models data; Cube serves metrics) |
| **Container Runtime** | Node.js + Python + pip + `cube_dbt` dependency | Pure Node.js (Official `cubejs/cube:latest`) |
| **Startup Behavior** | Parses `manifest.json` and evaluates Jinja templates | Instant declarative YAML schema load |
| **Join Definition** | Requires custom parser or explicit template code | Native declarative `joins:` block in Cube YAML |
| **Pre-Aggregations Support** | Clunky (cannot be cleanly represented in dbt) | First-class native `pre_aggregations:` block |
| **Failure Isolation** | High coupling (dbt compile failure breaks Cube) | Zero coupling (Cube queries standard BigQuery views/tables) |
| **CI/CD Pipeline** | Complex (must inject `manifest.json` into Cube builds) | Decoupled (dbt CI pushes to BQ; Cube CI deploys API) |

---

## 5. Implementation Standard for `cube-core-mcp`

1. **dbt Transformation Layer**:
   * Governs `src/dbt/models/staging/` and `src/dbt/models/marts/`.
   * Materializes physical fact and dimension tables into the `analytics` dataset in Google BigQuery (`fct_orders`, `fct_order_items`, `dim_products`, `dim_users`).
   * Validates schema, primary keys, and uniqueness through standard dbt tests.

2. **Cube Core Semantic Layer**:
   * Governs declarative YAML models under `src/cube/model/cubes/`:
     * `orders.yml`: Points to `analytics.fct_orders`, joins to `users`, defines order-level revenue and margin metrics.
     * `order_items.yml`: Points to `analytics.fct_order_items`, joins to `orders`, `products`, and `users`, defines line-item sales metrics.
     * `products.yml`: Points to `analytics.dim_products`, defines catalog metrics and price aggregations.
     * `users.yml`: Points to `analytics.dim_users`, defines customer demographics and user counts.
   * Runs natively on Cloud Run using the standard `cubejs/cube:latest` Docker image.
   * Directly queries BigQuery via Google Cloud Application Default Credentials (ADC).
   * Connects to the Cube Store Spot VM (`10.10.0.10:3030`) via Direct VPC Egress for pre-aggregation caching.
