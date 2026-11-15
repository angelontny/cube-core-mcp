# ADR-0003: Separation of dbt Transformations and Cube Semantic Layer

* **Status:** Accepted
* **Date:** 2026-11-11 (Updated 2026-11-15)
* **Deciders:** Data Engineering & Analytics Architecture Team
* **Consulted:** Semantic Modeling Leads, Cloud Platform Engineering
* **Informed:** Core Engineering Team

---

## 1. Context and Problem Statement

When building an enterprise semantic layer above Google BigQuery, two competing design patterns emerge for defining dimensions, calculated metrics, joins, and caching rules:

1. **Monolithic Manifest Reflection (`cube_dbt`):** Defining models and metrics strictly within dbt files, compiling them into a `target/manifest.json`, and using an in-container Python translation script (`cube_dbt`) to dynamically generate Cube cubes upon server boot.
2. **Decoupled Composable Architecture:** Delineating responsibilities strictly:
   * **dbt** acts as the batch transformation engine (the "T" in ELT), producing tested, documented, physical tables in Google BigQuery.
   * **Cube Core** acts as the semantic serving and caching engine, consuming BigQuery relations directly and governing multidimensional graphs, calculated measures, joins, and OLAP pre-aggregations.

---

## 2. Decision Drivers

* **Expressiveness:** First-class support for complex joins, multi-hop dimensions, calculated measures, and pre-aggregation rollups.
* **Container Health and Cold-Start Latency:** The Cloud Run serving container must boot rapidly without parsing multi-megabyte JSON manifests on every cold start.
* **Failure Domain Isolation:** A schema modification or compile error in dbt should not prevent the Cube semantic layer from serving existing metrics.
* **Dependency Footprint:** Avoiding bloated multi-runtime Docker images (Node.js + Python + pip + `cube_dbt`).

---

## 3. Considered Options

* **Option 1: In-Container Manifest-Driven Reflection (`cube_dbt`)**
* **Option 2: Pure dbt Semantic Layer (MetricFlow)**
* **Option 3: Decoupled Architecture with Native Declarative Cube YAML (Selected)**

---

## 4. Evaluation and Decision Outcome

**Chosen Option:** **Option 3: Decoupled Architecture with Native Declarative Cube YAML**.

### Technical Analysis of Rejected Alternatives
* **Option 1 (`cube_dbt`):** Open-source `cube_dbt` only generates basic single-table dimensions. It does not generate entity joins, complex business measures (e.g. margin ratios with divide-by-zero guards), or pre-aggregations. Supporting them requires fragile Python parser logic in `globals.py` and expands the Docker image to include both Node.js and Python.
* **Option 2 (MetricFlow):** dbt Semantic Layer lacks sub-second query caching, out-of-process columnar storage (Cube Store), and native Model Context Protocol (MCP) tool integrations.

### Architecture Division
```
[ BigQuery: Raw Tables ] 
       │
       ▼ (dbt compile & run)
[ BigQuery: Curated Dataset (fct_orders, dim_users) ]
       │
       ▼ (BigQuery API & Storage Read)
[ Cloud Run: Cube Core ] ──> [ Declarative YAML Models in src/cube/model/cubes/ ]
       │
       ▼ (L2 Columnar Pre-Aggregations)
[ Compute Engine: Cube Store Spot VM + GCS ]
```

---

## 5. Consequences

### Positive Consequences
* **Instant Container Cold Starts:** Cube loads native declarative YAML models in `< 100ms`, with zero `manifest.json` parse overhead.
* **Zero Multi-Language Runtime Debt:** Cube Core runs on the standard, minimal `cubejs/cube:latest` Node.js base image.
* **First-Class Pre-Aggregations:** Pre-aggregation rollups, partitions, and scheduled refresh keys are explicitly modeled directly in YAML.
* **Independent Deployment Lifecycles:** Metrics or cache updates can be shipped to Cube Core without triggering a dbt build or warehouse compile run.

### Negative Consequences / Risks
* Dimensions and table schema names must be declared in both dbt and Cube YAML, requiring discipline to ensure naming parity. (Can be automated via a generator skill).

---

## 6. Related Documents
* [ADR-0004: Multi-Container Cloud Run Pod vs. Separate Services](file:///home/angelo/projects/cube-core-mcp/docs/architecture/adrs/0004_multi_container_pod_vs_separate_services.md)
* [ADR-0006: Dynamic Jinja `| safe` Table Prefixing](file:///home/angelo/projects/cube-core-mcp/docs/architecture/adrs/0006_jinja_safe_cross_project_bigquery_federation.md)
* [C4 Architecture & Design Context](file:///home/angelo/projects/cube-core-mcp/docs/architecture/c4_architecture_and_design_context.md)
