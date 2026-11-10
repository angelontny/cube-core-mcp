# Terraform Service Account Bootstrap & IAM Strategy

This document explains the foundation-level bootstrapping of the Terraform deployment Service Account in Google Cloud, why it is separated from the application's Terraform code, and provides an automated, reproducible bootstrap procedure.

Related Documents:
* [semantic_layer_execution_plan.md](file:///home/angelo/projects/cube-core-mcp/docs/semantic_layer_execution_plan.md) — Overall project roadmap.
* [terraform_setup_and_authentication.md](file:///home/angelo/projects/cube-core-mcp/docs/terraform_setup_and_authentication.md) — Local workstation setup, provider configuration, and API enablement.

---

## 1. Architectural Model: Two-Tier IAM

In Google Cloud enterprise architectures, IAM management is divided into two distinct lifecycle tiers:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        TIER 0: FOUNDATION / BOOTSTRAP                  │
│                                                                        │
│   • Managed by: Human Cloud Admin via gcloud / bootstrap script        │
│   • Lifetime: Project lifespan (created once, rarely touched)          │
│   • Purpose: Provisions Terraform Service Account & grants baseline   │
│              administrative deployment permissions                     │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Impersonated by Developer or CI/CD
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                        TIER 1: WORKLOAD / APPLICATION                  │
│                                                                        │
│   • Managed by: Terraform (in this repository)                         │
│   • Lifetime: Dynamic lifecycle (created, modified, destroyed)         │
│   • Purpose: Provisions runtime identities and least-privilege roles   │
│              - Cube Store Spot VM Service Account                      │
│              - Cube Core Cloud Run Service Account                     │
│              - FastMCP Wrapper Service Account                         │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Why Terraform Shouldn't Manage Its Own Service Account

While Terraform *can* declare `google_project_iam_member` resources, using Terraform to manage the credentials and roles of its **own executing identity** introduces critical anti-patterns:

### A. The Chicken-and-Egg Paradox
For Terraform to manage IAM policies on a project, the executing Service Account must already possess `roles/resourcemanager.projectIamAdmin`. If the identity requires administrative IAM rights simply to authenticate the plan/apply cycle, managing its own base roles inside that same plan is circular and redundant.

### B. The `terraform destroy` Deadlock
When destroying an environment, Terraform determines the destruction order via dependency graphs. If Terraform manages its own executing identity's IAM roles, it may revoke those roles **before** deleting downstream infrastructure (such as Cloud Run services, Spot VMs, or VPC networks). Once the permissions are revoked mid-run, all subsequent delete operations crash with `403 Forbidden`, leaving orphaned, undeletable resources.

### C. Accidental Lockout Risk
If a developer accidentally misconfigures an IAM block or replaces `google_project_iam_member` (additive) with `google_project_iam_binding` (authoritative), Terraform will overwrite all other roles on the project. This can permanently lock the Service Account and your CI/CD pipeline out of the GCP project.

### D. The Service Usage API Dependency (API Bootstrap Paradox)
Terraform manages GCP APIs declaratively via the `google_project_service` resource. However, under the hood, the Google provider queries Google Cloud's Service Usage API (`serviceusage.googleapis.com`) to inspect and activate APIs. On newly provisioned projects, `serviceusage.googleapis.com` is disabled by default. If Terraform attempts to read or declare services before the Service Usage API is activated, GCP rejects the request with HTTP `403 Service Usage API has not been used in project ... before or it is disabled`. Terraform cannot enable the very API it requires to enable APIs; therefore, core bootstrap APIs must be enabled via `gcloud` during Tier 0 bootstrap.

---

## 3. Automated 1-Minute Bootstrap Script

Instead of manually clicking through multiple screens in the Google Cloud Console, execute the standalone bootstrap script located at [bootstrap_terraform_sa.sh](file:///home/angelo/projects/cube-core-mcp/docs/bootstrap_terraform_sa.sh).

### Quick Execution via Google Cloud Shell / Terminal
You can run the script file directly by passing your GCP Project ID:
```bash
# Direct execution (passes project ID as an argument)
bash docs/bootstrap_terraform_sa.sh <YOUR_GCP_PROJECT_ID>

# Or in Google Cloud Shell (auto-detects the currently active project)
bash docs/bootstrap_terraform_sa.sh
```

### Script Source Reference
If you prefer to copy and paste the script directly into your terminal or Cloud Console CLI, use the block below:

```bash
#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="your-gcp-project-id" # <-- Replace with your GCP Project ID
SA_NAME="terraform"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "==> Setting active project to: ${PROJECT_ID}"
gcloud config set project "${PROJECT_ID}" --quiet

echo "==> [1/5] Verifying Project Billing status..."
BILLING_ENABLED=$(gcloud billing projects describe "${PROJECT_ID}" --format="value(billingEnabled)" 2>/dev/null || echo "unknown")
if [[ "${BILLING_ENABLED}" == "False" ]]; then
  echo "Error: Cloud Billing is NOT enabled on project '${PROJECT_ID}'."
  echo "GCP APIs and resources cannot be activated without an active linked billing account."
  echo "To link a billing account, run:"
  echo "  gcloud billing accounts list"
  echo "  gcloud billing projects link ${PROJECT_ID} --billing-account=<BILLING_ACCOUNT_ID>"
  echo "  or visit: https://console.cloud.google.com/billing/linkedaccount?project=${PROJECT_ID}"
  exit 1
elif [[ "${BILLING_ENABLED}" == "True" ]]; then
  echo "    Billing is active on project '${PROJECT_ID}'."
else
  echo "    Notice: Unable to verify billing status (may require billing viewer permissions). Proceeding..."
fi

echo "==> [2/5] Activating foundational GCP APIs..."
# Service Usage API is required for Terraform to query or enable any services.
# Cloud Resource Manager and IAM APIs are required for role and SA management.
gcloud services enable \
  serviceusage.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  --project="${PROJECT_ID}" \
  --quiet

echo "==> [3/5] Checking if Service Account exists..."
if ! gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "==> Creating Service Account: ${SA_NAME}"
  gcloud iam service-accounts create "${SA_NAME}" \
    --description="Terraform deployment service account for Cube Core MCP" \
    --display-name="Terraform Admin SA" \
    --project="${PROJECT_ID}"
else
  echo "==> Service Account ${SA_EMAIL} already exists. Skipping creation."
fi

echo "==> [4/5] Assigning baseline deployment roles to ${SA_EMAIL}..."
ROLES=(
  "roles/serviceusage.serviceUsageAdmin"        # Allows Terraform to enable APIs declaratively
  "roles/storage.admin"                       # Remote state bucket & Cube Store storage
  "roles/compute.instanceAdmin.v1"            # Spot VM & Managed Instance Groups
  "roles/run.admin"                           # Cloud Run deployment
  "roles/compute.networkAdmin"                # VPC networking & Direct Egress
  "roles/compute.securityAdmin"               # Managing VPC firewall rules (compute.firewalls.create)
  "roles/bigquery.admin"                      # Managing BigQuery datasets, tables, and transfer configs
  "roles/iam.serviceAccountAdmin"             # Creating & managing workload Service Accounts
  "roles/iam.serviceAccountUser"              # Attaching runtime SAs to Compute/Cloud Run
  "roles/resourcemanager.projectIamAdmin"     # Managing runtime SA role bindings
)

for role in "${ROLES[@]}"; do
  echo "    -> Granting ${role}..."
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="${role}" \
    --condition=None \
    --quiet >/dev/null
done

echo "==> [5/5] Configuring User Impersonation (Keyless Local Auth)..."
CURRENT_USER=$(gcloud config get-value account)
echo "    -> Granting Service Account Token Creator to ${CURRENT_USER}..."
gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
  --member="user:${CURRENT_USER}" \
  --role="roles/iam.serviceAccountTokenCreator" \
  --project="${PROJECT_ID}" \
  --quiet >/dev/null

echo "==> Bootstrap complete!"
echo "    You can now authenticate your local workstation using:"
echo "    gcloud auth application-default login --impersonate-service-account=\"${SA_EMAIL}\""
```

---

## 4. What Terraform *Will* Manage in This Repository (Tier 1)

Once the foundation bootstrap is complete, all infrastructure and runtime identities are managed exclusively through Terraform in the `terraform/` directory:

1. **Spot VM Service Account (`cube-store-sa`):**
   * Needs read/write access to the dedicated Cube Store GCS bucket.
2. **Cube Core Service Account (`cloud-run-cube-sa`):**
   * Needs BigQuery query permissions (`roles/bigquery.jobUser`, `roles/bigquery.dataViewer`).
   * Needs network reachability to the Spot VM private IP via Direct VPC Egress.
3. **FastMCP Wrapper Service Account (`fastmcp-sa`):**
   * Needs permission to invoke the Cube Core Cloud Run service (`roles/run.invoker`).
