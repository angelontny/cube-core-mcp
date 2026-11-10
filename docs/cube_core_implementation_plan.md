# Cube Core & FastMCP: End-to-End GCP Implementation Plan

This runbook outlines the step-by-step engineering plan to provision and deploy **Cube Core** and **FastMCP** on **Google Cloud Platform (GCP)**, connecting **Google BigQuery** (transformed via dbt) to downstream AI agent interfaces.

---

## Architecture Flow Review

```
[ Tier 1: Storage Layer (GCS Parquet Bucket & Workload IAM) ]
                           │
                           ▼
[ Tier 2: Private Networking (Custom VPC, Regional Subnet, Firewall, Cloud NAT) ]
                           │
                           ▼
[ Tier 3: OLAP Cache Compute (Compute Engine Spot VM / MIG - Cube Store Standalone) ]
                           │
                           ▼
[ Tier 4: Semantic Engine & Worker (Cloud Run v2 - Cube Core API & Refresh Worker) ]
                           │
                           ▼
[ Tier 5: Model Context Protocol Layer (Cloud Run v2 - FastMCP Python Service) ]
```

---

## Detailed Step-by-Step Implementation

### Step 1: Storage Layer (`terraform/storage.tf`)
* **Objective:** Durable, decoupled persistence for Cube Store pre-aggregated Parquet data.
* **Resources & Configurations:**
  1. `google_storage_bucket.cube_store_cache`:
     - Name: `${var.project_id}-cube-store-cache`
     - Location: Regional (`asia-south1`)
     - Storage class: `STANDARD`
     - Security: Uniform bucket-level access enabled (`uniform_bucket_level_access = true`), public access prevention enforced (`public_access_prevention = "enforced"`).
  2. `google_service_account.cube_store`:
     - Account ID: `cube-store-sa`
     - Display name: `Cube Store Cache Engine Service Account`
  3. `google_storage_bucket_iam_member.cube_store_object_admin`:
     - Role: `roles/storage.objectAdmin` on the cache bucket.
  4. `google_project_iam_member.cube_store_logging`:
     - Role: `roles/logging.logWriter` to stream container logs to Cloud Logging.
* **Verification:** Run `terraform plan` and `terraform apply`. Verify the bucket exists in `asia-south1` and service account has object-level read/write permissions.

---

### Step 2: Private Networking Layer (`terraform/networking.tf`)
* **Objective:** Secure, private communication between serverless Cloud Run instances and the private Spot VM cache node without exposing ports to the public internet.
* **Resources & Configurations:**
  1. `google_compute_network.main`:
     - Name: `cube-network`
     - Auto-create subnetworks: `false` (custom mode VPC).
  2. `google_compute_subnetwork.cube_subnet`:
     - Name: `cube-subnet`
     - Region: `asia-south1`
     - CIDR: `10.10.0.0/24`
     - Private Google Access: `true` (enables VMs without external IPs to reach Google APIs like Cloud Storage and Cloud Logging).
  3. `google_compute_router.nat_router` & `google_compute_router_nat.nat_gateway`:
     - Regional Cloud Router and Cloud NAT on `cube-subnet`.
     - Required for private Spot VM instances to pull public container images (`cubedev/cube-store:latest`) from Docker Hub during boot.
  4. `google_compute_firewall.allow_internal_cubestore`:
     - Ingress rule allowing TCP port `3030` (MySQL wire protocol) and `9999` (internal cluster) restricted strictly to source range `10.10.0.0/24` or Cloud Run Direct VPC Egress.
* **Verification:** Run `terraform plan` and `terraform apply`. Verify VPC, subnet, NAT gateway, and firewall rules exist.

---

### Step 3: OLAP Cache Compute (`terraform/compute.tf`)
* **Objective:** Ephemeral, high-performance columnar caching node running Cube Store in Standalone mode with automated self-healing.
* **Resources & Configurations:**
  1. `google_compute_address.cube_store_internal_ip`:
     - Static private IP address reserved in `cube-subnet` (e.g., `10.10.0.10`) so that Cloud Run services have a deterministic target endpoint.
  2. `google_compute_instance_template.cube_store`:
     - Machine type: `e2-medium` (2 vCPU, 4 GiB RAM).
     - Operating System: Container-Optimized OS (COS).
     - Scheduling: `preemptible = true`, `provisioning_model = "SPOT"` (60-91% cost savings).
     - Service Account: `cube-store-sa@...` with scopes `["cloud-platform"]`.
     - Metadata container startup script launching `cubedev/cube-store:v0.36.0`:
       - `CUBESTORE_SERVER_NAME=localhost:9999`
       - `CUBESTORE_GCS_BUCKET=${google_storage_bucket.cube_store_cache.name}`
       - Port binding: `3030:3030`.
  3. `google_compute_instance_group_manager.cube_store_mig`:
     - Zonal Managed Instance Group in `asia-south1-c`.
     - Target size: `1`.
     - Autohealing & recreation policy ensuring automatic reboot if preempted.
* **Verification:** Verify the instance starts, acquires internal IP `10.10.0.10`, connects to the GCS cache bucket, and logs show Cube Store listening on port `3030`.

---

### Step 4: Semantic Engine & Refresh Worker (`src/cube/` & `terraform/cloud_run.tf`)
* **Objective:** Hydrate Cube Core data models from dbt `target/manifest.json` and deploy stateless API & Refresh Worker services.
* **Tasks & Configurations:**
  1. **Application Packaging (`src/cube/`)**:
     - `cube.js` configuration file reading `manifest.json`.
     - Environment configuration:
       - `CUBEJS_DB_TYPE=bigquery`
       - `CUBEJS_DB_BQ_PROJECT_ID=${var.project_id}`
       - `CUBESTORE_HOST=10.10.0.10`
       - `CUBESTORE_PORT=3030`
       - `CUBEJS_DEV_MODE=false`
  2. `google_service_account.cloud_run_cube`:
     - Account ID: `cloud-run-cube-sa`
     - IAM roles: `roles/bigquery.jobUser`, `roles/bigquery.dataViewer` on `thelook_ecommerce` and `analytics` datasets.
  3. `google_cloud_run_v2_service.cube_api`:
     - Service name: `cube-api`
     - Ingress: `INGRESS_TRAFFIC_INTERNAL_ONLY` (not exposed to internet).
     - Direct VPC Egress enabled pointing to `cube-subnet` (`egress = "PRIVATE_RANGES_ONLY"`).
     - Sizing: 1 vCPU, 2 GiB memory, `min_instance_count = 0`, `max_instance_count = 5`.
  4. `google_cloud_run_v2_service.cube_refresh_worker`:
     - Service name: `cube-refresh-worker`
     - Environment variable: `CUBEJS_REFRESH_WORKER=true`.
     - Runs background pre-aggregation builds independently from API traffic.
* **Verification:** Verify Cube API boots in Cloud Run, compiles dbt metrics from `manifest.json`, queries `cube-store` on `10.10.0.10:3030`, and falls back to BigQuery when cache is cold.

---

### Step 5: FastMCP Interface Layer (`src/fastmcp/` & `terraform/fastmcp.tf`)
* **Objective:** Expose Cube semantic metrics to LLMs (Claude Code, Cursor) using Model Context Protocol tools over Server-Sent Events (SSE).
* **Tasks & Configurations:**
  1. **Python FastMCP Service (`src/fastmcp/`)**:
     - Uses Python 3.11+ and FastMCP SDK.
     - Implements tools: `list_cubes()`, `get_cube_metadata()`, `query_metrics(metrics, dimensions, filters)`.
     - Mints Google OIDC ID tokens via Google Auth to query private `cube-api` Cloud Run endpoint.
  2. `google_service_account.fastmcp`:
     - Account ID: `fastmcp-sa`.
  3. `google_cloud_run_v2_service_iam_member.fastmcp_invokes_cube`:
     - Role: `roles/run.invoker` on `cube-api` granted to `fastmcp-sa`.
  4. `google_cloud_run_v2_service.fastmcp`:
     - Public ingress with OAuth 2.1 authentication.
* **Verification:** Test MCP tools end-to-end using Claude Desktop or local test runner; verify query execution flows from MCP $\rightarrow$ Cube API $\rightarrow$ Cube Store $\rightarrow$ BigQuery.
