# Cube Core Official Deployment Guide Review & Configuration Blueprint

This document details the analysis of the [official Cube Core Deployment Documentation](https://docs.cube.dev/cube-core/deployment) (including Docker Compose patterns, BigQuery warehouse integrations, and production checklists) and maps every official requirement to our GCP architecture.

---

## 1. Official Architecture Review & Alignment Check

The official deployment guide establishes that a scalable, production-grade Cube Core deployment consists of three independent container tiers:

```
[ Cube API Instances ] (cubejs/cube)          <── Serves REST, GraphQL, SQL queries
           │
           ├── (MySQL protocol port 3030) ──> [ Cube Store Cluster ] (cubejs/cubestore)
           │                                            │
           │                                            ├── (Streams Parquet) ──> [ Cloud Storage ]
           │                                            │
[ Cube Refresh Worker ] (cubejs/cube)        ───────────┘
           │
           └── (BigQuery EXPORT DATA SQL) ──> [ BigQuery Data Warehouse ]
```

### Verification Against Our Project State

| Official Requirement | Official Docker Compose Pattern | Our Project Implementation | Alignment Status |
| :--- | :--- | :--- | :--- |
| **Decoupled OLAP Engine** | Standalone container `cubejs/cubestore` | Dedicated Compute Engine Spot VM running `cubejs/cubestore:latest` | **Aligned** |
| **Separated Background Worker** | Separate service with `CUBEJS_REFRESH_WORKER=true` | Dedicated Cloud Run service / worker container | **Planned (Phase 2)** |
| **Durable Pre-aggregations** | Cloud blob storage (S3 / GCS / MinIO) | Google Cloud Storage (`cube-core-mcp-cube-store-cache`) | **Aligned (Tier 1 applied)** |
| **Private Network Routing** | Docker internal bridge (`cubestore_router`) | Custom VPC + Direct VPC Egress to static IP `10.10.0.10` | **Aligned (Tier 2 applied)** |
| **Security & Authentication** | JWT verification via `CUBEJS_API_SECRET` | Google Cloud IAM (`roles/run.invoker`) + `CUBEJS_API_SECRET` | **Planned (Phase 2)** |

---

## 2. Key Findings: BigQuery-Specific Requirements

In Cube Core's official BigQuery Docker Compose template, two specific architectural mechanisms are mandated when using Google BigQuery with Cube Store pre-aggregations:

### A. The Parquet Export Mechanism (`CUBEJS_DB_EXPORT_BUCKET`)
* **The Problem:** When Cube builds pre-aggregations from standard relational databases (PostgreSQL, MySQL), it queries the database and streams rows into Cube Store over a database connection. However, Google BigQuery is an asynchronous, columnar, petabyte-scale data warehouse. Streaming millions of rows over a standard HTTP response socket causes severe performance bottlenecks, network timeouts, and out-of-memory errors on both Cube and BigQuery.
* **The Official Solution:** Cube leverages BigQuery's native `EXPORT DATA OPTIONS` statement:
  ```sql
  EXPORT DATA OPTIONS(
    uri='gs://my-bucket/cube-export/*.parquet',
    format='PARQUET'
  ) AS SELECT ...
  ```
  BigQuery directly writes partitioned Parquet files straight into Google Cloud Storage at line-rate speed. Cube Store then ingests these Parquet files directly from the bucket.
* **Configuration Variable:** `CUBEJS_DB_EXPORT_BUCKET`.
* **Our Project Mapping:**
  - Value: `CUBEJS_DB_EXPORT_BUCKET="cube-core-mcp-cube-store-cache"`.
  - IAM Requirement: The Cloud Run service account (`cloud-run-cube-sa`) must have `roles/storage.objectAdmin` on the cache bucket so that BigQuery can export Parquet tables into it on Cube's behalf.

### B. Security & API Token Secret (`CUBEJS_API_SECRET`)
* **The Official Requirement:** When `CUBEJS_DEV_MODE=false`, Cube Core enforces JSON Web Token (JWT) authorization on all incoming REST, GraphQL, and SQL requests. The signature is validated using `CUBEJS_API_SECRET`.
* **Our Project Mapping:**
  - In our architecture, the public does not call Cube Core directly; only the **FastMCP Python service** calls Cube Core internally over Google's private network.
  - We will generate a cryptographic 32-byte secret in Terraform using the `random_password` resource.
  - The secret will be shared between `cube-api` (for token verification) and `fastmcp` (for token generation), creating an identity perimeter inside our private Cloud Run network.

---

## 3. Complete Cloud Run Environment Blueprint for Phase 2

Based on the official documentation, here is the exact parameter blueprint to be injected into the Cloud Run services in `terraform/modules/cloud_run/`:

### 1. Cube API Service (`cube-api`)

```hcl
environment_variables = {
  # Database / Warehouse Configuration
  CUBEJS_DB_TYPE             = "bigquery"
  CUBEJS_DB_BQ_PROJECT_ID    = var.project_id
  CUBEJS_DB_EXPORT_BUCKET    = module.storage.bucket_name

  # Cube Store Cache Connectivity
  CUBEJS_CUBESTORE_HOST      = module.networking.cube_store_internal_ip # 10.10.0.10
  CUBEJS_CUBESTORE_PORT      = "3030"

  # Production Hardening
  CUBEJS_DEV_MODE            = "false"
  CUBEJS_API_SECRET          = random_password.cube_api_secret.result
  NODE_ENV                   = "production"

  # dbt Semantic Schema Metadata
  CUBEJS_DBT_MANIFEST_PATH   = "/cube/conf/manifest.json"
}
```

### 2. Cube Refresh Worker Service (`cube-refresh-worker`)

```hcl
environment_variables = {
  # Database & Cache Configuration (Identical to API)
  CUBEJS_DB_TYPE             = "bigquery"
  CUBEJS_DB_BQ_PROJECT_ID    = var.project_id
  CUBEJS_DB_EXPORT_BUCKET    = module.storage.bucket_name
  CUBEJS_CUBESTORE_HOST      = module.networking.cube_store_internal_ip
  CUBEJS_CUBESTORE_PORT      = "3030"
  CUBEJS_API_SECRET          = random_password.cube_api_secret.result
  NODE_ENV                   = "production"

  # Worker Mode Flag (Designates container exclusively as background builder)
  CUBEJS_REFRESH_WORKER      = "true"
}
```

---

## 4. Workload Identity & IAM Matrix

To ensure keyless, least-privilege operation, the service accounts are assigned the following minimal Google Cloud IAM roles:

| Service Account | Consumer Resource | IAM Role | Scope / Target | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| `cube-store-sa` | Compute Engine Spot VM | `roles/storage.objectAdmin` | Cache GCS Bucket | Streaming and indexing Parquet pre-aggregations. |
| `cube-store-sa` | Compute Engine Spot VM | `roles/logging.logWriter` | Project level | Writing container runtime logs to Cloud Logging. |
| `cloud-run-cube-sa` | Cloud Run (API & Worker) | `roles/bigquery.jobUser` | Project level | Executing GoogleSQL analytical queries and export jobs. |
| `cloud-run-cube-sa` | Cloud Run (API & Worker) | `roles/bigquery.dataViewer` | BigQuery Datasets | Reading source tables and dbt mart models. |
| `cloud-run-cube-sa` | Cloud Run (API & Worker) | `roles/storage.objectAdmin` | Cache GCS Bucket | Writing BigQuery `EXPORT DATA` Parquet files. |
| `fastmcp-sa` | Cloud Run (FastMCP) | `roles/run.invoker` | `cube-api` Service | Calling private Cube REST API via Google OIDC tokens. |

---

## 5. Next Steps for Implementation

1. **Hydrate dbt Manifest into Cube**:
   - The compiled `src/dbt/target/manifest.json` exists locally.
   - Build `src/cube/cube.js` to parse models, dimensions, and measures dynamically from the manifest.
2. **Terraform Cloud Run Module (`terraform/modules/cloud_run/`)**:
   - Declare `google_cloud_run_v2_service.cube_api` (with Direct VPC Egress to `cube-subnet`).
   - Declare `google_cloud_run_v2_service.cube_refresh_worker`.
   - Wire `CUBEJS_DB_EXPORT_BUCKET` and `CUBEJS_API_SECRET`.
