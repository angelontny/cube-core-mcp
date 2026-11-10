# Terraform Modularization & State Migration Runbook

This document details the refactoring of our Terraform codebase from a flat root configuration into an encapsulated, multi-tier child module architecture (`terraform/modules/`), along with the zero-downtime state migration executed to prevent cloud resource destruction.

---

## 1. Context & Architectural Rationale

### The Problem: Flat Root Module Sprawl
Initially, all infrastructure definitions resided directly in `terraform/*.tf`:
- Base setup: `versions.tf`, `providers.tf`, `backend.tf`, `variables.tf`, `outputs.tf`
- Foundational resources: `services.tf`, `state_bucket.tf`
- BigQuery datasets, DTS configurations, and IAM bindings: `bigquery.tf`

As we prepared to provision Cube Store cache storage, private VPC networking, Compute Engine Spot VMs, Cloud Run services, and FastMCP, maintaining a flat structure would have resulted in **14+ loosely coupled files** sharing a single global scope. This creates:
1. **Scope Bleed:** Variables and local values leak across unrelated infrastructure components.
2. **Blast Radius Risk:** Changes to serverless compute or IAM could inadvertently trigger recreation or modification of data warehouse datasets.
3. **Lack of Reusability:** Individual domains (e.g., networking, analytical storage) cannot be tested or re-instantiated independently.

### The Decision: Modular Architecture
We adopted a modular domain architecture:
* **Root Module (`terraform/`)**: Retains foundational dependencies (`services.tf`, `state_bucket.tf`, providers, variables, and backend) and acts as the orchestrator (`main.tf`).
* **Child Modules (`terraform/modules/<domain>/`)**: Encapsulates specific domain resources with isolated inputs (`variables.tf`), resources (`main.tf`), and outputs (`outputs.tf`).

---

## 2. Directory Structure Before & After

### Before Refactoring (Flat Root)
```text
terraform/
├── backend.tf
├── bigquery.tf                # Monolithic BigQuery + DTS + IAM
├── outputs.tf                 # Pointed directly to root resources
├── providers.tf
├── services.tf
├── state_bucket.tf
├── terraform.tfvars
├── variables.tf
└── versions.tf
```

### After Refactoring (Modular Architecture)
```text
terraform/
├── backend.tf
├── main.tf                    # Module orchestrator (calls modules/bigquery, etc.)
├── outputs.tf                 # Exports module outputs
├── providers.tf
├── services.tf                # Foundational API enablement & 90s propagation gate
├── state_bucket.tf            # Remote state storage bucket
├── terraform.tfvars
├── variables.tf
├── versions.tf
└── modules/
    └── bigquery/              # Dedicated BigQuery & Data Transfer Module
        ├── main.tf            # Datasets, DTS transfer config, dedicated SA, IAM
        ├── outputs.tf         # Exported dataset IDs and SA email
        └── variables.tf       # Isolated module input parameters
```

---

## 3. The State Identity Problem: Why Code Moves Threaten Infrastructure

Terraform tracks live cloud infrastructure using an internal state file stored in GCS (`gs://cube-core-mcp-tfstate/terraform/state/default.tfstate`). In this file, every resource is indexed by its unique HCL address:

* **Old Address:** `google_bigquery_dataset.thelook_ecommerce`
* **New Address:** `module.bigquery.google_bigquery_dataset.thelook_ecommerce`

If you simply move code into `modules/bigquery/` and run `terraform apply`, Terraform compares the code against the state file and plans a destructive replacement:
1. It sees `google_bigquery_dataset.thelook_ecommerce` is missing from the root $\rightarrow$ **Plans deletion of your BigQuery dataset and all replicated tables**.
2. It sees `module.bigquery.google_bigquery_dataset.thelook_ecommerce` as a new resource $\rightarrow$ **Plans creation of a brand new, empty dataset**.

### The Solution: Zero-Downtime State Pointer Migration (`terraform state mv`)
The `terraform state mv` command modifies the internal metadata pointers within the remote state file without touching the actual Google Cloud infrastructure. It informs Terraform: *"The cloud resource existing at the old address is now managed by the new module address."*

---

## 4. Execution Log & Migration Commands

### Step 1: Child Module Creation
1. Created directory: `terraform/modules/bigquery/`.
2. Created `terraform/modules/bigquery/variables.tf` declaring `project_id`, `region`, `environment`, and `services_dependency`.
3. Created `terraform/modules/bigquery/main.tf` housing the datasets, service account `bq-transfer-sa`, token creator IAM bindings, propagation sleep buffer, and Data Transfer configuration.
4. Created `terraform/modules/bigquery/outputs.tf` exporting dataset IDs and service account emails.
5. Deleted the monolithic `terraform/bigquery.tf`.
6. Created `terraform/main.tf` instantiating `module "bigquery"`.
7. Updated `terraform/outputs.tf` to reference outputs from `module.bigquery`.

### Step 2: Module Discovery
Ran `terraform init` to allow Terraform to discover the new local child module:
```bash
cd terraform
terraform init
```
*Output confirmed module discovery:*
```text
Initializing modules...
- bigquery in modules/bigquery
```

### Step 3: Atomic State Address Migration
Executed the combined state address migration across all 7 managed resources:

```bash
cd terraform && \
terraform state mv google_bigquery_dataset.thelook_ecommerce module.bigquery.google_bigquery_dataset.thelook_ecommerce && \
terraform state mv google_bigquery_dataset.analytics module.bigquery.google_bigquery_dataset.analytics && \
terraform state mv google_service_account.bq_transfer module.bigquery.google_service_account.bq_transfer && \
terraform state mv google_project_iam_member.bq_transfer_admin module.bigquery.google_project_iam_member.bq_transfer_admin && \
terraform state mv google_service_account_iam_member.transfer_agent_token_creator module.bigquery.google_service_account_iam_member.transfer_agent_token_creator && \
terraform state mv time_sleep.wait_for_transfer_iam module.bigquery.time_sleep.wait_for_transfer_iam && \
terraform state mv google_bigquery_data_transfer_config.thelook_cross_region_copy module.bigquery.google_bigquery_data_transfer_config.thelook_cross_region_copy
```

### Step 4: Verification
Ran a dry-run plan against remote state:
```bash
terraform plan -var-file=terraform.tfvars
```
*Result:*
```text
No changes. Your infrastructure matches the configuration.
```

---

## 5. Architectural Pattern for Subsequent Modules

All subsequent infrastructure modules (`storage`, `networking`, `compute`, `services`) will follow this established pattern:

1. **Module Directory**: Created under `terraform/modules/<domain>/` with `main.tf`, `variables.tf`, and `outputs.tf`.
2. **Root Invocation**: Declared cleanly in `terraform/main.tf`.
3. **Explicit Dependency Chains**: Downstream modules receive outputs or dependency tokens from upstream modules (e.g., `services_dependency = time_sleep.wait_for_services`).
4. **Isolated Blast Radius**: Changes to compute or serverless instances do not risk altering storage or data warehouse datasets.
