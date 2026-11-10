# Project-Wide Technical Debt and Improvement Plan

This document tracks system enhancements, developer tooling improvements, and infrastructure hygiene tasks identified during the Phase 1 foundation review to advance the project toward production maturity.

Related Documents:
* [semantic_layer_execution_plan.md](file:///home/angelo/projects/cube-core-mcp/docs/semantic_layer_execution_plan.md) — Five-phase technical delivery roadmap.
* [terraform_setup_and_authentication.md](file:///home/angelo/projects/cube-core-mcp/docs/terraform_setup_and_authentication.md) — Workstation setup and state lifecycle runbook.
* [AGENT.md](file:///home/angelo/projects/cube-core-mcp/AGENT.md) — AI agent system rules and coding standards.

---

## 1. Cloud Storage Lifecycle Policy for State Bucket

* **Priority:** Medium
* **Target File:** [`terraform/state_bucket.tf`](file:///home/angelo/projects/cube-core-mcp/terraform/state_bucket.tf)
* **Status:** Backlog

### Problem Statement
The Terraform state bucket (`google_storage_bucket.terraform_state`) has versioning enabled without a corresponding object lifecycle policy. Over time, each `terraform apply` writes a new `.tfstate` generation. Without automatic cleanup, obsolete generations accumulate indefinitely.

### Proposed Implementation
Add a `lifecycle_rule` to retain a safe window of historical versions (e.g., 5 newer generations) and delete noncurrent versions older than 30 or 60 days:

```hcl
resource "google_storage_bucket" "terraform_state" {
  name     = "${var.project_id}-tfstate"
  location = var.region

  force_destroy               = false
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      num_newer_versions         = 5
      days_since_noncurrent_time = 30
    }
  }

  depends_on = [time_sleep.wait_for_services]
}
```

### Acceptance Criteria
- [ ] Noncurrent state file generations older than 30 days are automatically deleted.
- [ ] At least 5 noncurrent versions are retained for state rollback capability.
- [ ] `terraform validate` and `terraform fmt -check` pass cleanly.

---

## 2. Developer Ergonomics and Task Automation (`Makefile`)

* **Priority:** Medium
* **Target File:** `Makefile` (root directory)
* **Status:** Backlog

### Problem Statement
Day-to-day Terraform management requires passing runtime parameters (such as `-backend-config="bucket=..."` and `-var-file=terraform.tfvars`) and multi-command authentication steps. Manual command construction introduces typographical errors and workflow friction.

### Proposed Implementation
Create a lightweight `Makefile` in the repository root that extracts `project_id` dynamically or reads `terraform/terraform.tfvars`:

```makefile
SHELL := /bin/bash
PROJECT_ID ?= $(shell gcloud config get-value project 2>/dev/null)
BUCKET ?= $(PROJECT_ID)-tfstate

.PHONY: help auth init plan apply fmt validate clean

help:
	@echo "Available commands:"
	@echo "  make auth      Authenticate workstation ADC via SA impersonation"
	@echo "  make init      Initialize Terraform with remote GCS partial backend"
	@echo "  make plan      Generate and inspect Terraform execution plan"
	@echo "  make apply     Apply Terraform execution plan"
	@echo "  make fmt       Check and format Terraform configurations"
	@echo "  make validate  Validate Terraform syntax and provider schemas"

auth:
	gcloud auth application-default login \
	  --impersonate-service-account="terraform@$(PROJECT_ID).iam.gserviceaccount.com"
	gcloud auth application-default set-quota-project $(PROJECT_ID)

init:
	cd terraform && terraform init -backend-config="bucket=$(BUCKET)"

plan:
	cd terraform && terraform plan -var-file=terraform.tfvars

apply:
	cd terraform && terraform apply -var-file=terraform.tfvars

fmt:
	cd terraform && terraform fmt -recursive

validate:
	cd terraform && terraform validate
```

### Acceptance Criteria
- [ ] Common developer tasks (`auth`, `init`, `plan`, `apply`, `fmt`, `validate`) are executable with single-word targets.
- [ ] Targets fail gracefully if the active GCP project is unset.

---

## 3. Git Pre-Commit Hooks and Static Analysis

* **Priority:** High
* **Target Files:** `.pre-commit-config.yaml`, `.tflint.hcl`
* **Status:** Backlog

### Problem Statement
Formatting discrepancies, provider syntax deprecations, and accidental secret commits should be caught on local workstations before code reaches the Git index.

### Proposed Implementation
1. Add `.pre-commit-config.yaml` using official hooks:
   * `pre-commit-hooks`: Trailing whitespace, end-of-file fixer, YAML validator.
   * `terraform-fmt`: Enforces strict `terraform fmt` style.
   * `detect-secrets`: Scans for API keys, private tokens, and credentials.
2. Configure `.tflint.hcl` with the official Google ruleset plugin:
   ```hcl
   plugin "google" {
     enabled = true
     version = "0.29.0"
     source  = "github.com/terraform-linters/tflint-ruleset-google"
   }
   ```

### Acceptance Criteria
- [ ] Running `git commit` automatically validates Terraform formatting and scans for secrets.
- [ ] Deprecated Google provider arguments are caught by `tflint`.

---

## 4. Automated CI/CD Plan Verification via Workload Identity Federation

* **Priority:** Medium
* **Target File:** `.github/workflows/terraform-ci.yml`
* **Status:** Backlog

### Problem Statement
Pull requests currently lack automated plan verification. Reviewers cannot inspect proposed infrastructure diffs without executing commands locally.

### Proposed Implementation
Establish a GitHub Actions CI workflow using **Workload Identity Federation (WIF)**:
1. Configure a GCP Workload Identity Pool and Provider for GitHub Actions.
2. Grant the GitHub Actions service account `roles/viewer` and limited state bucket read access (`roles/storage.objectViewer`).
3. Build a pull-request pipeline executing:
   * `terraform fmt -check`
   * `terraform validate`
   * `tflint`
   * `terraform plan -var-file=terraform.tfvars -no-color` (posted as a PR comment)

### Acceptance Criteria
- [ ] Zero static service account keys in GitHub repository secrets (pure WIF OIDC federation).
- [ ] Pull requests automatically display infrastructure plan diffs before merging.
- [ ] Automated merge gating blocks unformatted or syntactically invalid Terraform code.

---

## 5. Security & Compliance Baseline Audit

* **Priority:** Low
* **Target Areas:** [`terraform/`](file:///home/angelo/projects/cube-core-mcp/terraform/), GCP Project Settings
* **Status:** Backlog

### Items for Investigation
1. **Cloud KMS (CMEK) vs. Google-Managed Encryption:**
   Determine whether enterprise compliance mandates Customer-Managed Encryption Keys (CMEK) for the Cube Store cache GCS bucket and state bucket, or if Google-managed encryption is sufficient.
2. **VPC Service Controls (VPC-SC):**
   Evaluate whether BigQuery and Cloud Storage access from Cloud Run should be enclosed within a VPC Service Controls perimeter to protect against data exfiltration.
3. **Cloud Logging Retention:**
   Verify that audit logs (Admin Activity and Data Access) are directed to a centralized Cloud Logging sink with appropriate log exclusion filters to control cost.
