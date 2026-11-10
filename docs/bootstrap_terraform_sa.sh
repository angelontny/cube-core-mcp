#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# Terraform Deployment Service Account Bootstrap Script
# ------------------------------------------------------------------------------
# Description:
#   Provisions the Tier 0 Terraform Service Account, assigns administrative
#   deployment IAM roles, and sets up keyless user impersonation for local
#   workstation development.
#
# Usage:
#   ./bootstrap_terraform_sa.sh [PROJECT_ID]
#   OR:
#   PROJECT_ID="your-project-id" ./bootstrap_terraform_sa.sh
# ------------------------------------------------------------------------------

# Resolve GCP Project ID: Argument -> Environment Variable -> Active gcloud config
PROJECT_ID="${1:-${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}}"

if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  echo "Error: GCP Project ID is required."
  echo "Usage: $0 <PROJECT_ID>"
  echo "   or: export PROJECT_ID=\"your-project-id\" && $0"
  exit 1
fi

SA_NAME="terraform"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "=================================================================="
echo "==> Target GCP Project: ${PROJECT_ID}"
echo "==> Service Account:    ${SA_EMAIL}"
echo "=================================================================="

# Set active project
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

echo "==> [3/5] Verifying Service Account existence..."
if ! gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "    Creating Service Account: ${SA_NAME}"
  gcloud iam service-accounts create "${SA_NAME}" \
    --description="Terraform deployment service account for Cube Core MCP" \
    --display-name="Terraform Admin SA" \
    --project="${PROJECT_ID}"
else
  echo "    Service Account already exists. Proceeding with role bindings."
fi

echo "==> [4/5] Assigning baseline deployment IAM roles..."
ROLES=(
  "roles/serviceusage.serviceUsageAdmin"        # Allows Terraform to enable APIs declaratively
  "roles/storage.admin"                       # Remote state bucket and Cube Store storage
  "roles/bigquery.admin"                      # Managing BigQuery datasets, tables, and transfer configs
  "roles/compute.instanceAdmin.v1"            # Spot VM and Managed Instance Groups
  "roles/run.admin"                           # Cloud Run deployment
  "roles/compute.networkAdmin"                # VPC networking and Direct Egress
  "roles/compute.securityAdmin"               # Managing VPC firewall rules (compute.firewalls.create)
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

echo "==> [5/5] Configuring Keyless User Impersonation..."
CURRENT_USER=$(gcloud config get-value account 2>/dev/null || true)

if [[ -n "${CURRENT_USER}" && "${CURRENT_USER}" != "(unset)" ]]; then
  echo "    -> Granting Service Account Token Creator to ${CURRENT_USER}..."
  gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
    --member="user:${CURRENT_USER}" \
    --role="roles/iam.serviceAccountTokenCreator" \
    --project="${PROJECT_ID}" \
    --quiet >/dev/null
else
  echo "    Warning: Could not detect active gcloud user account. Skipping impersonation binding."
  echo "    Run manually: gcloud iam service-accounts add-iam-policy-binding ${SA_EMAIL} --member=\"user:<YOUR_EMAIL>\" --role=\"roles/iam.serviceAccountTokenCreator\""
fi

echo "=================================================================="
echo "==> Bootstrap successfully completed!"
echo "=================================================================="
echo "Next step: Authenticate your local workstation ADC:"
echo "gcloud auth application-default login --impersonate-service-account=\"${SA_EMAIL}\""
echo "gcloud auth application-default set-quota-project ${PROJECT_ID}"
