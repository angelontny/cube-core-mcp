# Terraform Installation and GCP Authentication Guide

This guide details the official, Google-recommended procedure for installing Terraform, installing the Google Cloud CLI (`gcloud`), and configuring authentication for infrastructure deployment as outlined in [semantic_layer_execution_plan.md](file:///home/angelo/projects/cube-core-mcp/docs/semantic_layer_execution_plan.md).

---

## 1. Prerequisites & Installation

### A. Terraform Installation
According to HashiCorp and Google Cloud documentation, Terraform should be installed via official binary releases or platform package managers.

* **Arch Linux (Current Host):**
  ```bash
  sudo pacman -S terraform
  ```
* **Debian / Ubuntu:**
  ```bash
  sudo apt-get update && sudo apt-get install -y gnupg software-properties-common curl
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt-get update && sudo apt-get install terraform
  ```
* **macOS (Homebrew):**
  ```bash
  brew tap hashicorp/tap
  brew install hashicorp/tap/terraform
  ```

**Verify Installation:**
```bash
terraform -version
```

---

### B. Google Cloud CLI (`gcloud`) Installation
The Google Cloud CLI manages authentication tokens and credentials required by Terraform.

* **Linux Standalone Archive (Any Distro):**
  ```bash
  curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz
  tar -xf google-cloud-cli-linux-x86_64.tar.gz
  ./google-cloud-sdk/install.sh
  ./google-cloud-sdk/bin/gcloud init
  ```
* **Arch Linux (AUR):**
  ```bash
  yay -S google-cloud-cli
  ```
* **Debian / Ubuntu:**
  ```bash
  sudo apt-get install apt-transport-https ca-certificates gnupg curl
  curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
  sudo apt-get update && sudo apt-get install google-cloud-cli
  ```

**Verify Installation:**
```bash
gcloud version
```

---

## 2. Google Cloud Authentication via Application Default Credentials (ADC)

Google Cloud officially recommends using **Application Default Credentials (ADC)** for authenticating Terraform during local development.

> [!IMPORTANT]
> `gcloud auth login` authenticates the `gcloud` CLI tool itself, but **does not** generate Application Default Credentials for client libraries and Terraform. You must run `gcloud auth application-default login`.

### Step 1: Initialize User ADC
Run the following command to authenticate your user account:
```bash
gcloud auth application-default login
```
* This command launches a browser window requesting Google account authorization.
* Upon completion, credentials are saved locally at:
  - Linux/macOS: `~/.config/gcloud/application_default_credentials.json`
  - Windows: `%APPDATA%\gcloud\application_default_credentials.json`

### Step 2: Set Quota Project (Crucial)
Many Google Cloud APIs (such as Compute Engine, Cloud Run, and IAM) require a quota project when authenticating with end-user credentials. Failing to set this will lead to `PERMISSION_DENIED` errors on API requests.

```bash
gcloud auth application-default set-quota-project <YOUR_GCP_PROJECT_ID>
```

### Step 3: (Recommended Enterprise Pattern) Service Account Impersonation
Google Cloud strongly discourages exporting static Service Account JSON keys to local workstations. Instead, developers can impersonate a dedicated Terraform service account using their user identity:

1. Grant your user account the role `roles/iam.serviceAccountTokenCreator` on the target Terraform Service Account.
2. Authenticate ADC via impersonation:
   ```bash
   gcloud auth application-default login --impersonate-service-account="terraform-sa@<YOUR_GCP_PROJECT_ID>.iam.gserviceaccount.com"
   ```

---

## 3. Required GCP APIs and Permissions (Phase 1 Baseline)

You do **not** need to manually enable all GCP APIs via the console or CLI. Terraform can declare and enable them automatically using the `google_project_service` resource through your Terraform Service Account.

### A. The Minimum Prerequisites (One-Time Setup)
For Terraform to manage and enable other APIs on the project, the authenticating identity (the Terraform Service Account) must have:
1. **IAM Role:** `roles/serviceusage.serviceUsageAdmin` (enables and disables APIs).
2. **Base API Enabled:** `serviceusage.googleapis.com` (enabled by default on all standard GCP projects; enables Terraform to communicate with GCP's Service Usage API).

### B. Required IAM Roles for the Terraform Service Account
Grant these roles to `terraform-sa@<YOUR_GCP_PROJECT_ID>.iam.gserviceaccount.com`:
* `roles/serviceusage.serviceUsageAdmin` (to enable the APIs listed below automatically)
* `roles/storage.admin` (for GCS backend state and Cube Store storage)
* `roles/compute.instanceAdmin.v1` (for Spot VM & Managed Instance Groups)
* `roles/run.admin` (for Cloud Run service deployments)
* `roles/vpcaccess.admin` or `roles/compute.networkAdmin` (for Direct VPC Egress / VPC setup)
* `roles/iam.serviceAccountUser` (to attach runtime service accounts to Cloud Run & VMs)

### C. Enabling APIs Declaratively in Terraform (`google_project_service`)
You can define the required APIs directly in Terraform. By setting `disable_on_destroy = false`, you prevent Terraform from accidentally disabling critical APIs if the resource configuration is modified or destroyed:

```hcl
locals {
  required_services = [
    "compute.googleapis.com",              # Spot VM / Compute Engine
    "run.googleapis.com",                  # Cloud Run (Cube Core API & FastMCP)
    "storage.googleapis.com",              # GCS Bucket for Cube Store
    "vpcaccess.googleapis.com",            # Serverless VPC Access / Direct VPC Egress
    "iam.googleapis.com",                  # IAM & Service Account management
    "cloudresourcemanager.googleapis.com", # Project resource metadata
    "logging.googleapis.com",              # Cloud Logging sinks
  ]
}

resource "google_project_service" "enabled_services" {
  for_each = toset(local.required_services)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}
```

> [!TIP]
> If you prefer running a quick CLI command before your first `terraform apply` instead of declaring `google_project_service`, you can optionally run:
> ```bash
> gcloud services enable \
>   compute.googleapis.com \
>   run.googleapis.com \
>   storage.googleapis.com \
>   vpcaccess.googleapis.com \
>   iam.googleapis.com \
>   cloudresourcemanager.googleapis.com \
>   logging.googleapis.com \
>   --project=<YOUR_GCP_PROJECT_ID>
> ```

---

## 4. Standard Terraform Project Structure & Configuration

In production environments and Google Cloud enterprise architectures, Terraform code is structured into modular, single-responsibility files rather than a single monolithic script.

### A. Recommended Directory Layout
For this repository, place your Terraform configurations in a dedicated `terraform/` directory:

```text
cube-core-mcp/
├── docs/
│   ├── semantic_layer_execution_plan.md
│   └── terraform_setup_and_authentication.md
└── terraform/
    ├── .gitignore
    ├── versions.tf          # Terraform engine & provider version constraints
    ├── backend.tf           # Remote state storage configuration (GCS)
    ├── providers.tf         # Google & helper provider definitions
    ├── variables.tf         # Input variable declarations, types, and descriptions
    ├── terraform.tfvars     # Local environment variable values (ignored by git)
    ├── terraform.tfvars.example # Template variable values committed to git
    ├── services.tf          # Declarative GCP API enablement & propagation timers
    ├── outputs.tf           # Exported values (project ID, enabled APIs, etc.)
    └── (Phase 1 files)
        ├── networking.tf    # VPC & Direct Egress
        ├── storage.tf       # GCS bucket for Cube Store
        ├── compute.tf       # Spot VM & Managed Instance Group
        └── cloud_run.tf     # Cloud Run services (Cube Core API & FastMCP)
```

---

### B. Standard File Specifications

#### 1. `terraform/.gitignore`
Ensures local state, sensitive secrets, and plugin caches are never committed to version control:
```gitignore
# Local state files
*.tfstate
*.tfstate.*
crash.log
crash.*.log

# Terraform plugin directory & lock file overrides
.terraform/
.terraform.lock.hcl.bak

# Variable definitions containing project-specific or sensitive values
terraform.tfvars
*.auto.tfvars
*.auto.tfvars.json

# Exclude secrets
*.json
!application_default_credentials.json.example
```

---

#### 2. `terraform/versions.tf`
Specifies required Terraform core version and provider plugins:
```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.30"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
}
```

---

#### 3. `terraform/backend.tf` (Two-Step Remote State Setup)
Terraform state tracks your managed infrastructure. In Google Cloud, state should be stored remotely in a versioned Cloud Storage (GCS) bucket rather than locally.

> [!NOTE]
> **The Chicken-and-Egg Bootstrap**:
> You cannot store Terraform's state in a GCS bucket before that GCS bucket exists.
> 1. **Initial Run:** Leave the `backend "gcs"` block commented out. Terraform will use a local `terraform.tfstate`.
> 2. **After GCS Bucket Creation:** Uncomment the backend block and run `terraform init -migrate-state` to safely transfer the local state to the newly created bucket.

```hcl
# Uncomment after creating the state bucket in Phase 1:
# terraform {
#   backend "gcs" {
#     bucket = "cube-core-mcp-tfstate-<YOUR_PROJECT_ID>"
#     prefix = "terraform/state"
#   }
# }
```

---

#### 4. `terraform/providers.tf`
Configures the Google Cloud provider. Do **not** hardcode credentials paths or credentials files; Terraform discovers your local ADC automatically.

```hcl
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Optional default labels applied to all GCP resources supporting labels
  default_labels = {
    environment = var.environment
    managed_by  = "terraform"
    project     = "cube-core-mcp"
  }
}
```

---

#### 5. `terraform/variables.tf`
Defines all input variables with explicit types, validations, and descriptive documentation:

```hcl
variable "project_id" {
  type        = string
  description = "The GCP Project ID where resources will be provisioned."
}

variable "region" {
  type        = string
  description = "The primary GCP region for regional resources (Cloud Run, GCS)."
  default     = "us-central1"
}

variable "zone" {
  type        = string
  description = "The GCP zone for zonal resources (Spot VM)."
  default     = "us-central1-a"
}

variable "environment" {
  type        = string
  description = "Deployment environment name (dev, staging, prod)."
  default     = "dev"
}

variable "gcp_services" {
  type        = list(string)
  description = "List of GCP APIs to enable for Phase 1 infrastructure."
  default = [
    "compute.googleapis.com",              # Spot VM & MIG
    "run.googleapis.com",                  # Cloud Run Services
    "storage.googleapis.com",              # GCS Buckets (Cube Store & State)
    "vpcaccess.googleapis.com",            # Direct VPC Egress / Serverless Connector
    "iam.googleapis.com",                  # IAM Roles & Service Accounts
    "cloudresourcemanager.googleapis.com", # Project metadata & IAM policy bindings
    "logging.googleapis.com",              # Cloud Logging sinks
  ]
}
```

---

#### 6. `terraform/terraform.tfvars.example` and `terraform.tfvars`
Create a template file `terraform.tfvars.example` to commit to Git:
```hcl
project_id  = "your-gcp-project-id"
region      = "us-central1"
zone        = "us-central1-a"
environment = "dev"
```
Copy it locally to `terraform.tfvars` and substitute your actual GCP Project ID:
```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

---

## 5. Declarative Service Enablement (`services.tf`)

Enabling GCP APIs via Terraform requires understanding **Google Cloud API propagation delays**:

### The API Propagation Race Condition
When Google Cloud enables an API via the Service Usage API, it immediately returns `200 OK`. However, internal IAM propagation and control plane activation across Google data centers can take anywhere from **30 to 90 seconds**.

If dependent resources (e.g., creating a VPC or a Spot VM) execute immediately after the API call returns, they can fail with:
```text
Error 403: Compute Engine API has not been used in project ... before or it is disabled.
```

### The Solution: `services.tf` with `time_sleep`
To eliminate race conditions, standard practice utilizes the `hashicorp/time` provider to create an explicit 45-second sleep window after services are enabled before downstream resources start creating.

```hcl
# Enable the required APIs declaratively
resource "google_project_service" "enabled_services" {
  for_each = toset(var.gcp_services)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# Explicit wait buffer to allow Google's control plane to propagate
resource "time_sleep" "wait_for_services" {
  depends_on = [google_project_service.enabled_services]

  create_duration = "45s"
}
```

### How Subsequent Phase 1 Files Consume This Dependency
Whenever you create resources in later files (`networking.tf`, `compute.tf`, `storage.tf`, `cloud_run.tf`), ensure they explicitly depend on `time_sleep.wait_for_services`:

```hcl
# Example in storage.tf
resource "google_storage_bucket" "cube_store" {
  name     = "${var.project_id}-cube-store-data"
  location = var.region

  # Guarantees the storage API is enabled and fully active before bucket creation starts
  depends_on = [time_sleep.wait_for_services]
}
```

---

#### 7. `terraform/outputs.tf`
Outputs confirm the active environment configuration:

```hcl
output "project_id" {
  description = "The GCP Project ID."
  value       = var.project_id
}

output "enabled_services" {
  description = "List of services enabled by Terraform."
  value       = keys(google_project_service.enabled_services)
}
```

---

## 6. Execution Workflow & Step-by-Step Initialization

Follow this standard lifecycle workflow to initialize and apply the configuration:

### Step 1: Format and Validate
Always format and validate syntax before planning:
```bash
cd terraform/
terraform fmt
terraform validate
```

### Step 2: Initialize
Downloads provider plugins (`google`, `time`) and sets up local working state:
```bash
terraform init
```

### Step 3: Run Execution Plan
Inspect the exact changes Terraform intends to make without applying them:
```bash
terraform plan
```
Verify that the output shows `7 to add, 0 to change, 0 to destroy` (corresponding to the enabled services and the `time_sleep` resource).

### Step 4: Apply API Services
Apply the changes:
```bash
terraform apply
```
Type `yes` when prompted. Terraform will enable the APIs, pause for 45 seconds for propagation, and confirm success.

### Step 5: Verification
You can inspect the newly enabled services using `gcloud`:
```bash
gcloud services list --enabled --project=<YOUR_GCP_PROJECT_ID>
```
At this point, the baseline environment and authentication are fully operational, and you are ready to write Phase 1 infrastructure resources (Storage, Spot VM, Cloud Run, Networking).
