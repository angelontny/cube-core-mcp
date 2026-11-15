# Terraform Setup, Authentication, and State Migration Runbook

This runbook provides the definitive, step-by-step procedure to initialize the Google Cloud infrastructure for `cube-core-mcp`. It covers project creation, billing configuration, service account bootstrapping with keyless Application Default Credentials (ADC) impersonation, initial local Terraform execution, GCS state bucket provisioning, and state migration.

---

## Official Documentation References

* **Google Cloud:**
  * [Creating and Managing Projects](https://cloud.google.com/resource-manager/docs/creating-managing-projects)
  * [Modifying Project Billing Settings](https://cloud.google.com/billing/docs/how-to/modify-project)
  * [Service Account Impersonation Guide](https://cloud.google.com/docs/authentication/use-service-account-impersonation)
  * [Application Default Credentials (ADC)](https://cloud.google.com/docs/authentication/provide-credentials-adc)
  * [Service Usage API Overview](https://cloud.google.com/service-usage/docs/overview)
* **HashiCorp Terraform:**
  * [Terraform Google Provider Reference](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
  * [GCS Backend Configuration](https://developer.hashicorp.com/terraform/language/settings/backends/gcs)
  * [Partial Backend Configuration](https://developer.hashicorp.com/terraform/language/backend#partial-configuration)
  * [Backend State Migration](https://developer.hashicorp.com/terraform/language/backend#migrating-backends)
* **Internal Documentation:**
  * [semantic_layer_execution_plan.md](file:///home/angelo/projects/cube-core-mcp/docs/semantic_layer_execution_plan.md) — Architectural phases and milestone tracker.
  * [terraform_service_account_bootstrap.md](file:///home/angelo/projects/cube-core-mcp/docs/terraform_service_account_bootstrap.md) — Two-tier IAM design and security rationale.
  * [bootstrap_terraform_sa.sh](file:///home/angelo/projects/cube-core-mcp/docs/bootstrap_terraform_sa.sh) — Shell bootstrap script.

---

## Prerequisites: Tool Installation

Install the required CLI binaries on your local workstation:

### 1. HashiCorp Terraform (`>= 1.5.0`)
* **Arch Linux:**
  ```bash
  sudo pacman -S terraform
  ```
* **Debian / Ubuntu:**
  ```bash
  sudo apt-get update && sudo apt-get install -y gnupg software-properties-common curl
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt-get update && sudo apt-get install -y terraform
  ```
* **macOS:**
  ```bash
  brew tap hashicorp/tap
  brew install hashicorp/tap/terraform
  ```

### 2. Google Cloud CLI (`gcloud`)
* **Arch Linux (AUR):**
  ```bash
  yay -S google-cloud-cli
  ```
* **Debian / Ubuntu:**
  ```bash
  sudo apt-get install apt-transport-https ca-certificates gnupg curl
  curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
  sudo apt-get update && sudo apt-get install -y google-cloud-cli
  ```
* **macOS:**
  ```bash
  brew install --cask google-cloud-sdk
  ```

Verify installed versions:
```bash
terraform version
gcloud version
```

---

## Step-by-Step Initialization Runbook

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 1. Create GCP Project & Link Billing Account                                    │
└───────────────────────────────────────┬─────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 2. Clone Repository & Run Tier 0 SA Bootstrap Script                            │
└───────────────────────────────────────┬─────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 3. Authenticate Workstation ADC via SA Impersonation                            │
└───────────────────────────────────────┬─────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 4. Configure Local Environment Variables (terraform.tfvars)                    │
└───────────────────────────────────────┬─────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 5. Initialize Terraform Locally (backend.tf commented out)                      │
└───────────────────────────────────────┬─────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 6. Validate, Plan & Apply Initial Resources (Services + State Bucket)           │
└───────────────────────────────────────┬─────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 7. Enable Remote GCS Backend & Migrate State (terraform init -migrate-state)    │
└───────────────────────────────────────┬─────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 8. Verify State Synchronization (terraform plan -> "No changes")                │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

### Step 1: Create GCP Project & Link Active Billing Account

Every Google Cloud project requires an active Cloud Billing account linked before foundational APIs (`serviceusage.googleapis.com`, `compute.googleapis.com`) can be activated.

1. Create the GCP Project:
   ```bash
   gcloud projects create <YOUR_GCP_PROJECT_ID> --name="Cube Core MCP"
   ```

2. List your available billing accounts:
   ```bash
   gcloud billing accounts list
   ```

3. Link the billing account to the project:
   ```bash
   gcloud billing projects link <YOUR_GCP_PROJECT_ID> --billing-account=<BILLING_ACCOUNT_ID>
   ```

4. Verify billing status:
   ```bash
   gcloud billing projects describe <YOUR_GCP_PROJECT_ID> --format="value(billingEnabled)"
   ```
   *Expected output:* `True`

---

### Step 2: Clone Repository & Run Tier 0 SA Bootstrap Script

The repository includes an automated bootstrap script ([bootstrap_terraform_sa.sh](file:///home/angelo/projects/cube-core-mcp/docs/bootstrap_terraform_sa.sh)) that enables foundational APIs, provisions the deployment Service Account, assigns least-privilege administrative IAM roles, and enables keyless user impersonation.

1. Clone the repository to your local workstation:
   ```bash
   git clone <REPO_URL> cube-core-mcp
   cd cube-core-mcp
   ```

2. Authenticate your user account in the `gcloud` CLI:
   ```bash
   gcloud auth login
   ```

3. Execute the bootstrap script:
   ```bash
   bash docs/bootstrap_terraform_sa.sh <YOUR_GCP_PROJECT_ID>
   ```

   The script executes five automated stages:
   * **[1/5] Billing Verification:** Confirms billing is active on the project.
   * **[2/5] API Activation:** Activates `serviceusage.googleapis.com`, `cloudresourcemanager.googleapis.com`, and `iam.googleapis.com`.
   * **[3/5] Service Account Creation:** Provisions `terraform@<YOUR_GCP_PROJECT_ID>.iam.gserviceaccount.com`.
   * **[4/5] Role Assignment:** Assigns `serviceUsageAdmin`, `storage.admin`, `compute.instanceAdmin.v1`, `run.admin`, `compute.networkAdmin`, `iam.serviceAccountUser`, and `resourcemanager.projectIamAdmin`.
   * **[5/5] Impersonation Binding:** Grants `roles/iam.serviceAccountTokenCreator` to your user account.

---

### Step 3: Authenticate Workstation ADC via SA Impersonation

Configure your workstation to use Application Default Credentials (ADC) backed by temporary, short-lived tokens generated via Service Account impersonation. No static JSON service account keys are created or downloaded.

1. Login to ADC with impersonation:
   ```bash
   gcloud auth application-default login \
     --impersonate-service-account="terraform@<YOUR_GCP_PROJECT_ID>.iam.gserviceaccount.com"
   ```

2. Configure quota project:
   ```bash
   gcloud auth application-default set-quota-project <YOUR_GCP_PROJECT_ID>
   ```

---

### Step 4: Configure Local Environment Variables (`terraform.tfvars`)

Copy the committed template file and set your target project ID and deployment parameters:

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
project_id  = "<YOUR_GCP_PROJECT_ID>"
region      = "asia-south1"      # or "us-central1"
zone        = "asia-south1-c"    # or "us-central1-a"
environment = "dev"
```

> [!NOTE]
> `terraform.tfvars` contains deployment-specific identifiers and is explicitly ignored in [terraform/.gitignore](file:///home/angelo/projects/cube-core-mcp/terraform/.gitignore).

---

### Step 5: Initialize Terraform with Local Backend (Initial Bootstrap)

Because the Cloud Storage bucket for remote state does not yet exist, Terraform must perform its very first run using local state.

1. Ensure the `backend "gcs"` block in [`terraform/backend.tf`](file:///home/angelo/projects/cube-core-mcp/terraform/backend.tf) is **commented out**:
   ```hcl
   # terraform {
   #   backend "gcs" {
   #     prefix = "terraform/state"
   #   }
   # }
   ```

2. Initialize Terraform locally:
   ```bash
   terraform init
   ```
   *Expected output:* `Terraform has been successfully initialized!`

---

### Step 6: Validate, Plan, and Apply Initial Configuration

This step activates workload APIs declaratively and provisions the versioned Cloud Storage state bucket ([state_bucket.tf](file:///home/angelo/projects/cube-core-mcp/terraform/state_bucket.tf)).

1. Check code formatting:
   ```bash
   terraform fmt -check
   ```

2. Validate syntax and provider schemas:
   ```bash
   terraform validate
   ```

3. Review the execution plan:
   ```bash
   terraform plan -var-file=terraform.tfvars
   ```
   *Plan summary:* 7 resources to add (5 `google_project_service` APIs, 1 `time_sleep.wait_for_services`, 1 `google_storage_bucket.terraform_state`).

4. Provision the initial resources:
   ```bash
   terraform apply -var-file=terraform.tfvars
   ```
   Type `yes` when prompted. Terraform enables the APIs, pauses 45–90 seconds for propagation, and provisions the bucket `<YOUR_GCP_PROJECT_ID>-tfstate`.

---

### Step 7: Enable Remote GCS Backend & Migrate State

Once the bucket is provisioned in Google Cloud Storage, configure Terraform to store state remotely using **Partial Backend Configuration**.

1. Uncomment the backend block in [`terraform/backend.tf`](file:///home/angelo/projects/cube-core-mcp/terraform/backend.tf):
   ```hcl
   terraform {
     backend "gcs" {
       prefix = "terraform/state"
     }
   }
   ```

2. Migrate local state into GCS by passing the bucket dynamically:
   ```bash
   terraform init -backend-config="bucket=<YOUR_GCP_PROJECT_ID>-tfstate" -migrate-state
   ```

3. When prompted:
   ```text
   Do you want to copy existing state to the new backend?
     Pre-existing state was found while migrating the previous "local" backend to the
     newly configured "gcs" backend...
     Enter a value: yes
   ```
   Type `yes` and press Enter.

Terraform will upload the local `terraform.tfstate` into `gs://<YOUR_GCP_PROJECT_ID>-tfstate/terraform/state/default.tfstate`.

---

### Step 8: Verify Remote State Synchronization

Confirm that Terraform is reading from the remote backend and that the live infrastructure matches your configuration:

```bash
terraform plan -var-file=terraform.tfvars
```

*Expected output:*
```text
No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration and
found no differences, so no changes are needed.
```

The foundational infrastructure is now fully provisioned and secured with remote state locking. Subsequent Phase 1 modules ([networking.tf](file:///home/angelo/projects/cube-core-mcp/terraform/services.tf), `storage.tf`, `compute.tf`, `cloud_run.tf`) can now be implemented.

---

## Architectural Notes & FAQ

### Why Partial Backend Configuration?
Terraform initializes its backend before variable interpolation or `.tfvars` parsing takes place. Specifying `bucket = "${var.project_id}-tfstate"` inside `backend.tf` produces:
```text
Error: Variables not allowed on backend.tf line 3: Variables may not be used here.
```
By declaring only `prefix = "terraform/state"` in `backend.tf` and passing `-backend-config="bucket=..."` at `terraform init`, the repository stays 100% environment-agnostic without hardcoding sensitive or project-specific bucket names.

### Why Are Foundational APIs Separate From Workload APIs?
* `serviceusage.googleapis.com`, `cloudresourcemanager.googleapis.com`, and `iam.googleapis.com` are managed by the Tier 0 bootstrap script.
* Workload APIs (`compute`, `run`, `storage`, `vpcaccess`, `logging`) are managed declaratively in [`services.tf`](file:///home/angelo/projects/cube-core-mcp/terraform/services.tf).
* This protects the project from destructive deadlocks during `terraform destroy`, ensuring deployment credentials and API management capabilities remain intact across teardowns.
