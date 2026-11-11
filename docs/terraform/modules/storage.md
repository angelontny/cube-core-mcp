# Storage Terraform Module Documentation

The `storage` module provisions the persistent, decoupled cache tier required by Cube Store. It manages the durable Google Cloud Storage (GCS) Parquet cache bucket and the dedicated workload identity for the cache compute node.

---

## 1. Architectural Purpose

* **Decoupled Columnar Persistence**: Cube Store relies on remote cloud object storage to persist pre-aggregated rollups as partitioned Parquet files. This allows the compute nodes to remain stateless and ephemeral.
* **Cost & Preemption Safety**: By offloading Parquet tables to GCS, unexpected Compute Engine Spot VM preemptions or manual shutdowns cause zero data loss. When the node reboots, it connects back to this bucket.
* **Least-Privilege Workload Identity**: Establishes `cube-store-sa` with fine-grained bucket-level access (`roles/storage.objectAdmin`), avoiding over-privileged project-wide storage permissions.

---

## 2. Directory Layout

```text
terraform/modules/storage/
├── main.tf          # GCS cache bucket, service account, and additive IAM bindings
├── variables.tf     # Input variables (project_id, region, environment, dependencies)
└── outputs.tf       # Exported attributes (bucket name, bucket URL, service account email/name)
```

---

## 3. Resources Provisioned

| Resource Type | Resource Identifier | Purpose & Configuration |
| :--- | :--- | :--- |
| `google_storage_bucket` | `cube_store_cache` (`${project_id}-cube-store-cache`) | Regional bucket in `asia-south1`. Storage class: `STANDARD`. Uniform bucket-level access and public access prevention enforced. `force_destroy = true` in dev. |
| `google_service_account` | `cube_store` (`cube-store-sa`) | Dedicated workload service account for the Cube Store cache engine. |
| `google_storage_bucket_iam_member` | `cube_store_object_admin` | Additive grant of `roles/storage.objectAdmin` scoped strictly to the cache bucket. |
| `google_project_iam_member` | `cube_store_logging` | Additive grant of `roles/logging.logWriter` allowing container logs to stream into Cloud Logging. |

---

## 4. Input Variables

| Variable Name | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `project_id` | `string` | *required* | The GCP Project ID where the storage bucket will be provisioned. |
| `region` | `string` | *required* | The primary GCP region for the Cube Store cache bucket (`asia-south1`). |
| `environment` | `string` | `"dev"` | Deployment environment name (`dev`, `staging`, `prod`). Governs `force_destroy`. |
| `services_dependency` | `any` | `null` | Explicit dependency on API enablement timers (`time_sleep.wait_for_services`). |

---

## 5. Outputs Exported

| Output Name | Type | Description |
| :--- | :--- | :--- |
| `bucket_name` | `string` | The name of the Cube Store Parquet cache bucket (`${project_id}-cube-store-cache`). |
| `bucket_url` | `string` | The `gs://` URI of the cache bucket. |
| `service_account_email` | `string` | Email address of the dedicated Cube Store service account. |
| `service_account_name` | `string` | Fully qualified resource name of the service account. |
