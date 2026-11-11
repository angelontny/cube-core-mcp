# BigQuery Terraform Module Documentation

The `bigquery` module encapsulates the upstream analytical storage tier. It provisions the local regional replica dataset (`thelook_ecommerce`), the curated dbt marts dataset (`analytics`), the dedicated Data Transfer Service Account, and the cross-region replication configuration.

---

## 1. Architectural Purpose

* **Source Replica (`thelook_ecommerce`)**: Creates a regional BigQuery dataset in `asia-south1` to host raw eCommerce tables replicated from Google's US multi-region public dataset (`bigquery-public-data.thelook_ecommerce`).
* **Curated Analytics Marts (`analytics`)**: Houses dbt dimensional and fact models (`fct_orders`, `fct_order_items`, `dim_users`, `dim_products`).
* **Headless Replication Harness**: Employs BigQuery Data Transfer Service (DTS) using a dedicated service account (`bq-transfer-sa`) to eliminate manual OAuth browser popups.

---

## 2. Directory Layout

```text
terraform/modules/bigquery/
├── main.tf          # Datasets, DTS transfer config, service account, and IAM bindings
├── variables.tf     # Input variables (project_id, region, environment, dependencies)
└── outputs.tf       # Exported attributes (dataset IDs, service account email, transfer ID)
```

---

## 3. Resources Provisioned

| Resource Type | Resource Identifier | Purpose & Configuration |
| :--- | :--- | :--- |
| `google_service_account` | `bq_transfer` (`bq-transfer-sa`) | Dedicated identity executing the dataset copy job. |
| `google_project_iam_member` | `bq_transfer_admin` | Grants `roles/bigquery.admin` to `bq-transfer-sa`. |
| `google_service_account_iam_member` | `transfer_agent_token_creator` | Grants `roles/iam.serviceAccountTokenCreator` to Google's internal DTS service agent (`service-${project_number}@gcp-sa-bigquerydatatransfer.iam.gserviceaccount.com`). |
| `time_sleep` | `wait_for_transfer_iam` | 30-second buffer ensuring IAM token minting rights propagate before transfer execution. |
| `google_bigquery_dataset` | `thelook_ecommerce` | Raw eCommerce dataset in `asia-south1`. |
| `google_bigquery_dataset` | `analytics` | Curated analytics marts dataset in `asia-south1`. |
| `google_bigquery_data_transfer_config` | `thelook_cross_region_copy` | One-time `cross_region_copy` transfer (`disable_auto_scheduling = true`). |

---

## 4. Input Variables

| Variable Name | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `project_id` | `string` | *required* | The GCP Project ID where BigQuery resources will be provisioned. |
| `region` | `string` | *required* | The primary GCP region for BigQuery datasets (`asia-south1`). |
| `environment` | `string` | `"dev"` | Deployment environment name (`dev`, `staging`, `prod`). Governs `delete_contents_on_destroy`. |
| `services_dependency` | `any` | `null` | Explicit dependency on API enablement timers (`time_sleep.wait_for_services`). |

---

## 5. Outputs Exported

| Output Name | Type | Description |
| :--- | :--- | :--- |
| `thelook_ecommerce_dataset_id` | `string` | Dataset ID of the replicated raw eCommerce data. |
| `analytics_dataset_id` | `string` | Dataset ID of the curated analytics marts. |
| `bq_transfer_service_account_email` | `string` | Email of the dedicated BigQuery Data Transfer service account. |
| `transfer_config_id` | `string` | Resource name of the cross-region dataset transfer configuration. |
