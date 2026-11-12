# Cloud Run Terraform Module Documentation

The `cloud_run` module provisions the serverless serving layer running the **Cube Core API** on **Google Cloud Run v2**, supported by **Google Artifact Registry** and **Direct VPC Egress**.

---

## 1. Architectural Purpose

* **Serverless Semantic API Serving**: Hosts `cubejs/cube:latest` packaged with declarative YAML data models ([src/cube/](file:///home/angelo/projects/cube-core-mcp/src/cube)), exposing REST and SQL endpoints for analytics queries.
* **Direct BigQuery Execution (Stage 1)**: In Phase 1, Cube connects directly to BigQuery using workload identity credentials, querying `analytics` dimensional fact and dimension tables with zero intermediate caching.
* **Pre-Wired Direct VPC Egress**: Configured with Cloud Run Direct VPC Egress (`PRIVATE_RANGES_ONLY`) mapped to `cube-subnet`. This pre-wires private IP connectivity to the Cube Store Spot VM (`10.10.0.10:3030`) without requiring a legacy Serverless VPC Access Connector.
* **Zero-Trust Identity Perimeter**: Unauthenticated invocations (`allUsers`) are disabled by default. Access requires IAM authorization via `roles/run.invoker` (`terraform@cube-core-mcp.iam.gserviceaccount.com`).
* **Scale-to-Zero Cost Optimization**: Sized with `min_instance_count = 0` and `max_instance_count = 3`. Idle compute costs are **$0.00**.
* **Automated Artifact Registry Cost Control**: Implements native `cleanup_policies` in `google_artifact_registry_repository.cube_repo` to automatically purge untagged layers and retain only the single latest container version, staying within Google Cloud's 0.5 GB free tier.

---

## 2. Directory Layout

```text
terraform/modules/cloud_run/
├── main.tf          # Artifact Registry, Workload SA, IAM roles, Cloud Run v2 service, and Invoker IAM
├── variables.tf     # Sizing, networking, environment variables, and operational toggles
└── outputs.tf       # Service URL, runtime SA email, repository ID, and service name
```

---

## 3. Resources Provisioned

| Resource Type | Resource Identifier | Purpose & Configuration |
| :--- | :--- | :--- |
| `google_artifact_registry_repository` | `cube_repo` | Docker repository in `asia-south1` hosting `cube-api` images. Governed by 3 automated cleanup policies. |
| `google_service_account` | `cloud_run_cube` | Dedicated runtime identity `cloud-run-cube-sa@cube-core-mcp.iam.gserviceaccount.com`. |
| `google_project_iam_member` | `cube_bq_job_user` | Grants `roles/bigquery.jobUser` to submit queries and export jobs. |
| `google_project_iam_member` | `cube_bq_data_viewer` | Grants `roles/bigquery.dataViewer` to read datasets (`thelook_ecommerce`, `analytics`). |
| `google_project_iam_member` | `cube_logging` | Grants `roles/logging.logWriter` for stdout and structured logging. |
| `google_storage_bucket_iam_member` | `cube_storage_access[0]` | Optional `roles/storage.objectAdmin` on `cube-store-cache` bucket for pre-aggregations. |
| `google_cloud_run_v2_service` | `cube_api[0]` | Serverless v2 service deployed conditionally (`count = var.enabled ? 1 : 0`). |
| `google_cloud_run_v2_service_iam_member` | `invoker_access[...]` | Authorizes specified IAM service accounts with `roles/run.invoker`. |

---

## 4. Input Variables

### Module-Level Variables (`terraform/modules/cloud_run/variables.tf`)

| Variable Name | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `project_id` | `string` | *required* | The GCP Project ID. |
| `region` | `string` | *required* | Primary deployment region (`asia-south1`). |
| `environment` | `string` | `"dev"` | Deployment environment name (`dev`, `staging`, `prod`). |
| `enabled` | `bool` | `false` | Master toggle to provision Cloud Run service. Keep `false` until image is pushed. |
| `service_name` | `string` | `"cube-api"` | Name of the Cloud Run v2 service. |
| `repository_id` | `string` | `"cube-repo"` | Artifact Registry Docker repository ID. |
| `service_account_id` | `string` | `"cloud-run-cube-sa"` | Dedicated runtime Service Account account ID. |
| `container_image` | `string` | `""` | Container image URL. Defaults to `${region}-docker.pkg.dev/${project_id}/${repository_id}/cube-api:latest`. |
| `container_port` | `number` | `4000` | Port Cube API listens on. |
| `cpu_limit` | `string` | `"1000m"` | Dedicated vCPU allocation (1 vCPU). |
| `memory_limit` | `string` | `"1Gi"` | RAM limit (1 GB). |
| `min_instances` | `number` | `0` | Minimum instances (0 enables scale-to-zero when idle). |
| `max_instances` | `number` | `3` | Maximum scaling ceiling. |
| `dev_mode` | `bool` | `true` | Enables Cube dev mode and introspection endpoints. |
| `cubejs_api_secret` | `string` | `"cube-core-mcp-secure-api-secret-key-2026"` | Shared secret for JWT token verification. |
| `cube_store_host` | `string` | `""` | Internal IP of Cube Store (`10.10.0.10`). Empty disables Cube Store integration. |
| `cube_store_port` | `string` | `"3030"` | Port for Cube Store MySQL wire protocol. |
| `cube_store_bucket_name` | `string` | `""` | GCS bucket for BigQuery Parquet export. |
| `network_id` | `string` | *required* | VPC network resource ID for Direct Egress. |
| `subnet_id` | `string` | *required* | Subnet resource ID for Direct Egress. |
| `allow_unauthenticated` | `bool` | `false` | When false, requires authenticated calls with `roles/run.invoker`. |
| `invoker_members` | `list(string)` | `[]` | List of IAM identities permitted to invoke the service. |
| `services_dependency` | `any` | `null` | Dependency on API enablement timer. |

---

## 5. Injected Environment Variables

The container is configured exclusively via environment variables in accordance with official Cube conventions:

| Variable Name | Injected Value | Purpose |
| :--- | :--- | :--- |
| `CUBEJS_DB_TYPE` | `"bigquery"` | Activates BigQuery driver. |
| `CUBEJS_DB_BQ_PROJECT_ID` | `var.project_id` | Project where queries and jobs execute. |
| `CUBEJS_DB_BQ_LOCATION` | `var.region` (`asia-south1`) | BigQuery dataset location (prevents default `US` error). |
| `CUBEJS_DEV_MODE` | `"true"` / `"false"` | Toggles developer mode and playground. |
| `CUBEJS_API_SECRET` | `var.cubejs_api_secret` | JWT verification secret key. |
| `CUBEJS_TELEMETRY` | `"false"` | Disables anonymous telemetry reporting. |
| `CUBEJS_CUBESTORE_HOST` | `10.10.0.10` *(conditional)* | Injected only when `cube_store_host != ""`. |
| `CUBEJS_CUBESTORE_PORT` | `"3030"` *(conditional)* | Injected only when `cube_store_host != ""`. |
| `CUBEJS_DB_EXPORT_BUCKET` | Bucket name *(conditional)* | Injected only when Cube Store is enabled. |
| `CUBEJS_DB_EXPORT_BUCKET_TYPE` | `"gcp"` *(conditional)* | Injected only when Cube Store is enabled. |

---

## 6. Automated Cleanup Policy Specification

To prevent storage bloat and billing in Artifact Registry, `google_artifact_registry_repository.cube_repo` enforces three automated rules:

```hcl
cleanup_policy_dry_run = false

# Rule 1: Always retain the single newest image version
cleanup_policies {
  id     = "keep-latest-version"
  action = "KEEP"
  most_recent_versions {
    keep_count = 1
  }
}

# Rule 2: Purge untagged layers older than 1 hour (cleans up multi-layer intermediate blobs)
cleanup_policies {
  id     = "delete-untagged"
  action = "DELETE"
  condition {
    tag_state  = "UNTAGGED"
    older_than = "3600s"
  }
}

# Rule 3: Purge any older tagged releases past 1 day
cleanup_policies {
  id     = "delete-older-than-1-day"
  action = "DELETE"
  condition {
    tag_state  = "ANY"
    older_than = "86400s"
  }
}
```

Because `KEEP` rules take precedence in Google Artifact Registry, the newest working version is never deleted, while all historical revisions and dangling layers are pruned automatically.

---

## 7. Outputs

| Output Identifier | Description |
| :--- | :--- |
| `service_uri` | Public HTTPS endpoint for the Cloud Run Cube Core API (`https://cube-api-h3ungosjsa-el.a.run.app`). |
| `service_name` | Cloud Run v2 service resource name (`cube-api`). |
| `service_account_email` | Dedicated runtime Service Account email (`cloud-run-cube-sa@...`). |
| `repository_id` | Artifact Registry repository ID (`cube-repo`). |
