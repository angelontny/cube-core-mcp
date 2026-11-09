# BigQuery Architecture, Sample Data Ingestion, and Production Transition Guide

This document records the architectural decisions, troubleshooting steps, and implementation details for provisioning the BigQuery data layer in `cube-core-mcp`. It explains how the sample dataset (`thelook_ecommerce`) was ingested via BigQuery Data Transfer Service (DTS), the IAM challenges resolved, and how this sample harness differs from a real-world production deployment.

Related Documents:
* [semantic_layer_execution_plan.md](file:///home/angelo/projects/cube-core-mcp/docs/semantic_layer_execution_plan.md) — End-to-end technical roadmap.
* [terraform_setup_and_authentication.md](file:///home/angelo/projects/cube-core-mcp/docs/terraform_setup_and_authentication.md) — Infrastructure setup and runbook.
* [terraform_service_account_bootstrap.md](file:///home/angelo/projects/cube-core-mcp/docs/terraform_service_account_bootstrap.md) — Two-tier IAM foundation.
* [AGENT.md](file:///home/angelo/projects/cube-core-mcp/AGENT.md) — System operating guidelines and rules.

---

## 1. Context and Motivation

To develop and validate Phases 2 through 4 of `cube-core-mcp` (dbt transformation compilation, Cube Core semantic modeling, FastMCP query translation, and Claude client integration), the system requires a realistic relational data warehouse on Google BigQuery.

### Selection of `thelook_ecommerce`
Rather than generating synthetic dummy data or using trivial schemas (such as `jaffle_shop`), we selected Google's public dataset: `bigquery-public-data.thelook_ecommerce`.

* **Rich Schema:** Contains 7 interconnected eCommerce tables (`orders`, `order_items`, `products`, `users`, `inventory_items`, `distribution_centers`, `events`).
* **Realistic Semantic Metrics:** Allows testing real-world business queries via LLM clients (e.g., Gross Revenue, Return Rate, Customer Lifetime Value, Delivery Lag).
* **Compact Footprint:** Total dataset size is ~400 MB, fitting comfortably inside BigQuery's **10 GB Always Free tier** ($0.00 storage cost).

---

## 2. Chronological Decisions and Technical Journey

### Decision 1: Local Dataset Replication vs. Cross-Project Federation
* **Initial Proposal:** Query `bigquery-public-data.thelook_ecommerce` directly via cross-project SQL in dbt.
* **The Constraint:** The public dataset is hosted in the **`US` multi-region**. BigQuery strictly prohibits cross-region joins (e.g., joining a `US` public table with an `asia-south1` local table).
* **Decision:** Replicate the 7 tables into our project's home deployment region (`asia-south1`). This ensures complete colocation with our Cloud Run services and Cube Store Spot VM, eliminating cross-region latency and isolating our project from external upstream schema modifications.

### Decision 2: Cross-Region Transfer via BigQuery Data Transfer Service
* **The Constraint:** Standard BigQuery copy jobs (`google_bigquery_job` with `copy`) are strictly **intra-region** and reject cross-region table copies.
* **Decision:** Utilize Google's **BigQuery Data Transfer Service (DTS)** with the `data_source_id = "cross_region_copy"` connector. DTS natively replicates datasets across geographic regions (`US` &rarr; `asia-south1`) with zero compute fees and only a one-time network egress fee (~$0.05 for 400 MB).

### Decision 3: One-Time On-Demand Sync vs. Recurring Cron
* **The Constraint:** Standard DTS configurations require a recurring schedule (e.g., `every 24 hours`), which would trigger continuous cross-region syncs and recurring egress charges for a static demo dataset.
* **Decision:** Configure `schedule_options { disable_auto_scheduling = true }` in [`terraform/bigquery.tf`](file:///home/angelo/projects/cube-core-mcp/terraform/bigquery.tf). This permanently disables the background cron engine, creating an on-demand configuration that runs strictly as a one-time seed copy.

### Decision 4: Diagnosing and Resolving the Headless Terraform Hang
During the initial deployment of `google_bigquery_data_transfer_config`, Terraform hung indefinitely at `Still creating... [06m00s elapsed]`.

#### Root Cause Analysis
1. **Interactive OAuth Legacy:** BigQuery DTS was originally designed for the Google Cloud Web Console, which pops up an interactive browser window requesting end-user OAuth consent.
2. **Headless Execution:** Because Terraform executes headlessly under Service Account impersonation (`--impersonate-service-account`), no browser session exists to accept the consent prompt. Google's API placed the transfer configuration into a `PENDING_USER_AUTH` queue. Terraform polled Google's Long Running Operation (LRO) waiting for the status to become `ACTIVE`, hitting an impasse.
3. **Internal Service Agent Boundary:** To authorize transfers via machine-to-machine authentication, Google's internal BigQuery Data Transfer Service Agent (`service-<PROJECT_NUMBER>@gcp-sa-bigquerydatatransfer.iam.gserviceaccount.com`) requires permission to impersonate the executing identity via `roles/iam.serviceAccountTokenCreator`.

### Decision 5: Preserving Two-Tier IAM Isolation
Rather than using manual console clicks or granting project-wide token minting privileges in the shell bootstrap script:
1. **Deployment SA Foundation (Tier 0):** Added `roles/bigquery.admin` and `roles/iam.serviceAccountAdmin` to the foundational Terraform deployment service account (`terraform@...`) via [`docs/bootstrap_terraform_sa.sh`](file:///home/angelo/projects/cube-core-mcp/docs/bootstrap_terraform_sa.sh). This allows Terraform to provision BigQuery resources and workload service accounts.
2. **Workload SA Isolation (Tier 1):** Declared a dedicated, least-privilege transfer identity (`google_service_account.bq_transfer`) 100% inside [`terraform/bigquery.tf`](file:///home/angelo/projects/cube-core-mcp/terraform/bigquery.tf).
3. **Explicit Agent Delegation:** Granted `roles/iam.serviceAccountTokenCreator` to the Google DTS Service Agent specifically on `bq-transfer-sa` via `google_service_account_iam_member`.
4. **IAM Propagation Guard:** Inserted a 30-second `time_sleep.wait_for_transfer_iam` buffer to allow Google's internal OAuth token generator cache to propagate before the transfer configuration validates delegation.
5. **Explicit Dependency:** Added `service_account_name = google_service_account.bq_transfer.email` to `google_bigquery_data_transfer_config` with an explicit `depends_on = [time_sleep.wait_for_transfer_iam]`.

**Result:** The entire BigQuery data layer, identity delegation, and transfer configuration deployed successfully in seconds without human console intervention.

---

## 3. Current Infrastructure Architecture (Sample Harness)

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ GOOGLE CLOUD: bigquery-public-data (Region: US)                                        │
│   └── Dataset: thelook_ecommerce (7 Raw eCommerce Tables, ~400 MB)                     │
└───────────────────────────────────────────┬────────────────────────────────────────────┘
                                            │ One-time Cross-Region Transfer
                                            │ (bq-transfer-sa via DTS Service Agent)
                                            ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ GCP PROJECT: cube-core-mcp (Region: var.region / asia-south1)                          │
│                                                                                        │
│   ┌────────────────────────────────────────────────────────────────────────────────┐   │
│   │ Raw Dataset: cube-core-mcp.thelook_ecommerce                                   │   │
│   │   • orders, order_items, products, users, inventory_items, events...           │   │
│   └───────────────────────────────────────┬────────────────────────────────────────┘   │
│                                           │ dbt Run (Transforms, Cleans, Joins)        │
│                                           ▼                                            │
│   ┌────────────────────────────────────────────────────────────────────────────────┐   │
│   │ Analytics Marts Dataset: cube-core-mcp.analytics                               │   │
│   │   • fct_orders, dim_products, dim_users (Curated facts & dimensions)           │   │
│   └───────────────────────────────────────┬────────────────────────────────────────┘   │
│                                           │ Query Execution & Metadata Ingestion       │
│                                           ▼                                            │
│   ┌────────────────────────────────────────────────────────────────────────────────┐   │
│   │ Semantic Engine: Cube Core (Cloud Run v2 + Cube Store Cache)                   │   │
│   │   • Reads dbt manifest.json                                                    │   │
│   │   • Serves metrics via FastMCP over SSE to Claude Code / Claude Desktop        │   │
│   └────────────────────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Production Transition Guide: Moving to Real Enterprise Data

`thelook_ecommerce` and the BigQuery Data Transfer Service configuration in [`terraform/bigquery.tf`](file:///home/angelo/projects/cube-core-mcp/terraform/bigquery.tf) represent a **development and demonstration harness**.

In an enterprise production deployment, your data pipeline architecture will differ:

### Differences Between Demo and Production

| Feature | Development Harness (This Repo) | Enterprise Production Environment |
|---|---|---|
| **Data Source** | Public Google sample dataset (`thelook_ecommerce`) | Internal enterprise sources (PostgreSQL, Salesforce, Stripe, Kafka) |
| **Ingestion Mechanism** | BigQuery Data Transfer Service (`cross_region_copy`) | Enterprise ETL/ELT pipelines (Fivetran, Airbyte, Datastream, Cloud Dataflow) |
| **Dataset Location** | Replicated from `US` into `var.region` | Native enterprise BigQuery datasets already provisioned in the target region |
| **Transfer Config Required?** | **Yes** (one-time seed replication) | **No** (data is already continuously synced by upstream ETL) |
| **dbt Target Models** | Built from `thelook_ecommerce` source tables | Built from existing raw enterprise staging schemas |

---

### Step-by-Step Transition to Production Data

When deploying `cube-core-mcp` to a real production environment with existing enterprise BigQuery data, follow these steps:

#### Step 1: Remove or Disable Sample Transfer Infrastructure
You do **not** need the BigQuery Data Transfer Service or the `bq-transfer-sa` service account. In your production Terraform root module:
* Remove `google_bigquery_data_transfer_config.thelook_cross_region_copy`.
* Remove `google_service_account.bq_transfer` and its associated token creator IAM binding.
* Remove `google_bigquery_dataset.thelook_ecommerce` (the raw sample replica).
* Remove `bigquerydatatransfer.googleapis.com` from `var.gcp_services` in [`terraform/variables.tf`](file:///home/angelo/projects/cube-core-mcp/terraform/variables.tf).

#### Step 2: Keep the Analytics Marts Dataset
Retain the curated analytics marts dataset definition in [`terraform/bigquery.tf`](file:///home/angelo/projects/cube-core-mcp/terraform/bigquery.tf):
```hcl
resource "google_bigquery_dataset" "analytics" {
  dataset_id                  = "analytics" # Or your production mart name (e.g. "marts_core")
  friendly_name               = "Enterprise Analytics Marts"
  description                 = "Target dataset for dbt models and Cube Core semantic queries"
  location                    = var.region
  default_table_expiration_ms = null

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }

  delete_contents_on_destroy = false # Protect production data

  depends_on = [time_sleep.wait_for_services]
}
```

#### Step 3: Grant Least-Privilege IAM to the Cube Core Runtime Identity
In production, Cube Core runs on Cloud Run under a dedicated workload Service Account (`cloud-run-cube-sa`). It only requires read and query execution access to your production marts:

```hcl
# 1. Permission to execute queries in the BigQuery project
resource "google_project_iam_member" "cube_bigquery_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.cube_core_sa.email}"
}

# 2. Permission to read tables within the curated analytics dataset
resource "google_bigquery_dataset_iam_member" "cube_dataset_viewer" {
  dataset_id = google_bigquery_dataset.analytics.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.cube_core_sa.email}"
}
```

#### Step 4: Update dbt Sources
In your dbt repository:
* Replace `thelook_ecommerce` in `sources.yml` with your enterprise source databases and tables.
* Run `dbt build` to compile the production `manifest.json`.
* Point Cube Core to the compiled production `manifest.json`.

---

## 5. Summary Checklist

- [x] Target datasets (`thelook_ecommerce` and `analytics`) created in deployment region `asia-south1`.
- [x] BigQuery Data Transfer Service configured with `disable_auto_scheduling = true` (one-time on-demand replication).
- [x] Dedicated transfer service account (`bq-transfer-sa`) provisioned with least-privilege `TokenCreator` delegation.
- [x] Foundational Terraform deployment Service Account granted `bigquery.admin` and `iam.serviceAccountAdmin`.
- [x] Production migration path documented to decouple sample harness from enterprise workloads.
