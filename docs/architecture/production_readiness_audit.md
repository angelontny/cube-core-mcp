# Production Readiness Audit & Hardening Roadmap

* **Document Version:** 1.0.0
* **Date:** 2026-11-15
* **Target Environment:** Google Cloud Platform (GCP)
* **Status:** Actionable Backlog / In Review

---

## 1. Executive Summary & Audit Overview

A comprehensive engineering audit evaluated the maturity gap between the project's documentation and its underlying codebase. While the architectural foundation (modular Terraform tiering, API-propagation guards, multi-container Cloud Run v2 pod co-location, and FastMCP token-compression formatters) is sound, the codebase currently exhibits several vulnerabilities, single-points-of-failure, and anti-patterns that prevent safe enterprise production deployment.

This document formalizes the audit findings across three severity tiers, providing technical root-cause analyses, operational impact assessments, and step-by-step remediation blueprints.

```
┌────────────────────────────────────────────────────────────────────────┐
│                   Production Readiness Severity Tiers                  │
├────────────────────────────────────────────────────────────────────────┤
│ Tier 1: Critical Security Vulnerabilities (Must Fix)                   │
│   1. Hardcoded API Secret Committed & Deployed in Plaintext            │
│   2. Static Service Account Private Key Embedded in VM Metadata        │
│   3. Ungated `dev_mode: true` Default on Cloud Run Ingress             │
├────────────────────────────────────────────────────────────────────────┤
│ Tier 2: Reliability & Operational Fragility (Should Fix)               │
│   4. Spot VM Preemption without Auto-Recovery (Missing MIG)            │
│   5. Regional Split-Brain (`us-central1` vs `asia-south1`)             │
│   6. Mutable Image Tagging Anti-Pattern (`:latest` everywhere)         │
│   7. Pre-Aggregations Dataset Schema Unwired in Cube Core              │
│   8. Over-Privileged Project-Wide BigQuery IAM Grants                  │
│   9. Undeclared `pyjwt` Runtime Dependency                             │
├────────────────────────────────────────────────────────────────────────┤
│ Tier 3: Code Hygiene & Performance Optimization (Smaller Things)       │
│  10. Markdown Pipe Table Injection in FastMCP Formatters               │
│  11. Event Loop Blocking & Missing HTTP Connection Pooling             │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Tier 1: Critical Security Vulnerabilities (Must Fix)

### Issue 1: Hardcoded API Secret Committed & Deployed in Plaintext
* **Locations:**
  * [`terraform/modules/cloud_run/variables.tf:128`](file:///home/angelo/projects/cube-core-mcp/terraform/modules/cloud_run/variables.tf#L128)
  * [`terraform/modules/cloud_run/main.tf:234`](file:///home/angelo/projects/cube-core-mcp/terraform/modules/cloud_run/main.tf#L234)
  * [`docs/guides/fastmcp_local_testing_and_verification.md`](file:///home/angelo/projects/cube-core-mcp/docs/guides/fastmcp_local_testing_and_verification.md)
* **Root Cause:** The variable `cubejs_api_secret` defaults to `"cube-core-mcp-secure-api-secret-key-2026"`. The root module never overrides it, and passes it as a plaintext environment variable (`CUBEJS_API_SECRET` and `CUBE_API_SECRET`) to both containers.
* **Risk & Impact:**
  1. Anyone with repository access can mint valid HS256 JWT tokens and bypass Cube Core query authentication.
  2. The secret is permanently exposed in unencrypted `.tfstate` files and visible in plaintext inside the Google Cloud Console revision YAML.
  3. Violates [AGENT.md](file:///home/angelo/projects/cube-core-mcp/AGENT.md#L90) ("Never commit secrets. OAuth client secrets, API tokens").
* **Remediation Blueprint:**
  1. Remove the default value from `cubejs_api_secret` in `cloud_run/variables.tf`.
  2. In `terraform/modules/cloud_run/main.tf`, provision a dedicated Google Secret Manager secret with an auto-generated high-entropy password:
     ```hcl
     resource "random_password" "cube_api_secret" {
       length  = 48
       special = true
     }

     resource "google_secret_manager_secret" "cube_api_secret" {
       secret_id = "cube-api-secret"
       replication { auto {} }
       depends_on = [var.services_dependency]
     }

     resource "google_secret_manager_secret_version" "cube_api_secret" {
       secret      = google_secret_manager_secret.cube_api_secret.id
       secret_data = var.cubejs_api_secret != "" ? var.cubejs_api_secret : random_password.cube_api_secret.result
     }
     ```
  3. Inject the secret into both the `cube-core` and `fastmcp` containers using `value_source.secret_key_ref`, removing all plaintext environment variables.
  4. Sanitize documentation to eliminate hardcoded secret values.

---

### Issue 2: Static Service Account Key in VM Metadata
* **Locations:**
  * [`terraform/modules/compute/main.tf:8-11`](file:///home/angelo/projects/cube-core-mcp/terraform/modules/compute/main.tf#L8-L11)
  * [`terraform/modules/compute/main.tf:65`](file:///home/angelo/projects/cube-core-mcp/terraform/modules/compute/main.tf#L65)
* **Root Cause:** A `google_service_account_key` is created in Terraform, and its base64 private key is directly interpolated into the VM's `metadata { user-data = ... }`.
* **Risk & Impact:**
  1. Violates [AGENT.md](file:///home/angelo/projects/cube-core-mcp/AGENT.md#L91) ("never generate or accept static Service Account JSON keys").
  2. Instance metadata is readable by any principal with `compute.instances.get`.
  3. The static key never rotates and lives permanently in the Terraform state file.
* **Underlying Constraint:** The Rust `cloud-storage-rs` crate used inside Cube Store requires a local filesystem key file pointed to by `GOOGLE_APPLICATION_CREDENTIALS` or `CUBESTORE_GCP_KEY_FILE`.
* **Remediation Blueprint:**
  1. Eliminate the `google_service_account_key` resource from Terraform.
  2. Give the VM's attached identity (`cube-store-sa@`) `roles/secretmanager.secretAccessor` (or use GCS/Workload Identity).
  3. When an explicit key file is strictly required by the Rust driver, store the key in Secret Manager and have cloud-init fetch it dynamically at boot into an ephemeral in-memory tmpfs mount (`/run/cube-store/sa-key.json`) using the VM's attached Application Default Credentials:
     ```bash
     # cloud-init runcmd
     mkdir -p /run/cube-store
     chmod 0700 /run/cube-store
     gcloud secrets versions access latest --secret="cube-store-gcs-sa-key" > /run/cube-store/sa-key.json
     chmod 0600 /run/cube-store/sa-key.json
     ```
  4. This eliminates private keys from Git, Terraform state, and GCE instance metadata.

---

### Issue 3: `dev_mode` Defaults to `true`
* **Locations:**
  * [`terraform/modules/cloud_run/variables.tf:122`](file:///home/angelo/projects/cube-core-mcp/terraform/modules/cloud_run/variables.tf#L122)
  * [`terraform/modules/cloud_run/main.tf:230-233`](file:///home/angelo/projects/cube-core-mcp/terraform/modules/cloud_run/main.tf#L230-L233)
* **Root Cause:** `var.dev_mode` defaults to `true`.
* **Risk & Impact:**
  1. Cube Core in developer mode relaxes authentication, enables live model file watchers (consuming continuous CPU cycles on serverless containers), and exposes the developer Playground.
  2. In conjunction with public ingress (`INGRESS_TRAFFIC_ALL`), any unauthenticated caller who bypasses Cloud Run IAM can access schema internals.
* **Remediation Blueprint:**
  1. Change default in `variables.tf` to `false`.
  2. Strictly gate the container environment variable in `main.tf`:
     ```hcl
     env {
       name  = "CUBEJS_DEV_MODE"
       value = (var.environment == "dev" && var.dev_mode) ? "true" : "false"
     }
     ```

---

## 3. Tier 2: Reliability & Operational Fragility (Should Fix)

### Issue 4: Spot VM Preemption without Auto-Recovery (Missing MIG)
* **Locations:**
  * [`terraform/modules/compute/main.tf:16-32`](file:///home/angelo/projects/cube-core-mcp/terraform/modules/compute/main.tf#L16-L32)
* **Root Cause:** Cube Store runs as a standalone `google_compute_instance` with `scheduling { provisioning_model = "SPOT", automatic_restart = false, instance_termination_action = "STOP" }`.
* **Risk & Impact:**
  1. Spot VMs are preemptible by Google Cloud at any time. When preempted, this instance transitions to `TERMINATED` and never reboots.
  2. When Cube Store is offline, the L2 cache dies silently. All analytical queries degrade into direct BigQuery table scans, increasing warehouse query execution costs by 10x-50x and spiking latency.
* **Remediation Blueprint:**
  1. Convert [terraform/modules/compute/](file:///home/angelo/projects/cube-core-mcp/terraform/modules/compute/) to use:
     * `google_compute_instance_template.cube_store`: Captures the COS boot image, cloud-init systemd service, and Spot scheduling.
     * `google_compute_instance_group_manager.cube_store_mig`: Zonal Managed Instance Group with `target_size = 1`.
     * `google_compute_region_health_check.cube_store_tcp`: TCP health check on port 3030 with autohealing policies.
  2. When GCP preempts the Spot VM, the MIG recreation policy immediately boots a replacement instance, acquires the static private IP `10.10.0.10`, and restores the RocksDB metastore from GCS in < 2 seconds.

---

### Issue 5: Regional Split-Brain Configuration
* **Locations:**
  * [`terraform/variables.tf:10`](file:///home/angelo/projects/cube-core-mcp/terraform/variables.tf#L10) (`us-central1`)
  * [`src/cube_store/cloudbuild.yaml:5`](file:///home/angelo/projects/cube-core-mcp/src/cube_store/cloudbuild.yaml#L5) (hardcoded `asia-south1`)
  * [`src/dbt/profiles.yml:8`](file:///home/angelo/projects/cube-core-mcp/src/dbt/profiles.yml#L8) (`location: asia-south1`)
* **Root Cause:** Terraform variables default to `us-central1`, while Cloud Build, dbt profiles, `terraform.tfvars`, and documentation reference `asia-south1`.
* **Risk & Impact:** If an operator initializes Terraform without specifying `terraform.tfvars`, resources are provisioned in `us-central1`. The Compute Engine VM attempts to pull container images from `us-central1-docker.pkg.dev`, which does not exist, causing container pull crash loops.
* **Remediation Blueprint:**
  1. Standardize default `region = "asia-south1"` and `zone = "asia-south1-c"` in `terraform/variables.tf`.
  2. Parameterize `src/cube_store/cloudbuild.yaml` with substitutions:
     ```yaml
     substitutions:
       _REGION: 'asia-south1'
     steps:
       - name: 'gcr.io/cloud-builders/docker'
         args: ['tag', 'cubejs/cubestore:latest', '${_REGION}-docker.pkg.dev/$PROJECT_ID/cube-repo/cube-store:latest']
     ```

---

### Issue 6: Mutable Image Tagging Anti-Pattern (`:latest`)
* **Locations:**
  * [`src/cube/Dockerfile:1`](file:///home/angelo/projects/cube-core-mcp/src/cube/Dockerfile#L1) (`cubejs/cube:latest`)
  * [`src/cube_store/cloudbuild.yaml:3`](file:///home/angelo/projects/cube-core-mcp/src/cube_store/cloudbuild.yaml#L3) (`cubejs/cubestore:latest`)
  * [`terraform/modules/cloud_run/main.tf:162-163`](file:///home/angelo/projects/cube-core-mcp/terraform/modules/cloud_run/main.tf#L162-L163) (`:latest`)
* **Root Cause:** Container images and base images rely entirely on the mutable `:latest` tag.
* **Risk & Impact:**
  1. When developers build and push updated images under `:latest`, `terraform plan` reports "No changes" because the image URI string is identical.
  2. Deployments cannot be audited, pinned, or rolled back declaratively.
  3. Builds are non-reproducible.
* **Remediation Blueprint:**
  1. Pin base images: `cubejs/cube:v0.36.0` and `cubejs/cubestore:v0.36.0`.
  2. Add Terraform variables `cube_image_tag` and `fastmcp_image_tag` defaulting to immutable semantic version numbers or git commit SHAs (e.g. `${var.cube_image_tag}`).

---

### Issue 7: Pre-Aggregations Dataset Schema Not Wired to Cube
* **Locations:**
  * [`terraform/modules/bigquery/main.tf:106-118`](file:///home/angelo/projects/cube-core-mcp/terraform/modules/bigquery/main.tf#L106-L118)
  * [`terraform/modules/cloud_run/main.tf:205-245`](file:///home/angelo/projects/cube-core-mcp/terraform/modules/cloud_run/main.tf#L205-L245)
* **Root Cause:** The `bigquery` module provisions `${var.environment}_pre_aggregations` (e.g. `dev_pre_aggregations`). However, the `cube-core` container is never configured with `CUBEJS_PRE_AGGREGATIONS_SCHEMA`.
* **Risk & Impact:** In `dev`, Cube defaults to `dev_pre_aggregations`, which matches by coincidence. In `prod`, Cube defaults to `prod_pre_aggregations` or attempts to create tables in the source dataset, resulting in query failures or permission denials.
* **Remediation Blueprint:**
  Add the explicit configuration to `terraform/modules/cloud_run/main.tf`:
  ```hcl
  env {
    name  = "CUBEJS_PRE_AGGREGATIONS_SCHEMA"
    value = "${var.environment}_pre_aggregations"
  }
  ```

---

### Issue 8: Over-Privileged Project-Wide BigQuery IAM Grants
* **Locations:**
  * [`terraform/modules/cloud_run/main.tf:69-74`](file:///home/angelo/projects/cube-core-mcp/terraform/modules/cloud_run/main.tf#L69-L74) (`roles/bigquery.dataEditor` at project level)
  * [`terraform/modules/bigquery/main.tf:12-16`](file:///home/angelo/projects/cube-core-mcp/terraform/modules/bigquery/main.tf#L12-L16) (`roles/bigquery.admin` at project level)
* **Root Cause:** Broad IAM roles granted at the project level (`google_project_iam_member`) instead of scoping down to specific datasets.
* **Risk & Impact:**
  1. `cloud-run-cube-sa` can edit, truncate, or drop any dataset in the project.
  2. `bq-transfer-sa` has full administrative rights across BigQuery project resources.
* **Remediation Blueprint:**
  1. Scope `roles/bigquery.dataEditor` strictly to `${var.environment}_pre_aggregations` via `google_bigquery_dataset_iam_member`.
  2. Scope `roles/bigquery.dataViewer` strictly to the `analytics` reporting dataset.
  3. Retain `roles/bigquery.jobUser` at the project level (required by BigQuery to execute jobs and allocate query execution slots).
  4. Scope `bq-transfer-sa` to dataset-level admin on `thelook_ecommerce`.

---

### Issue 9: Undeclared Runtime Dependencies
* **Locations:**
  * [`src/fastmcp/pyproject.toml:10-18`](file:///home/angelo/projects/cube-core-mcp/src/fastmcp/pyproject.toml#L10-L18)
  * [`src/fastmcp/src/cube_fastmcp/cube_client.py:13`](file:///home/angelo/projects/cube-core-mcp/src/fastmcp/src/cube_fastmcp/cube_client.py#L13)
* **Root Cause:** `cube_client.py` imports `jwt`, but `pyjwt` is not declared in `pyproject.toml` (it resolves only transitively via upstream libraries). Conversely, `requests` is declared in `dependencies` but never directly imported.
* **Risk & Impact:** If an upstream library drops its transitive dependency on `pyjwt`, production builds will fail with `ModuleNotFoundError: No module named 'jwt'`.
* **Remediation Blueprint:**
  1. Explicitly add `"pyjwt>=2.8.0"` to `dependencies` in `src/fastmcp/pyproject.toml`.
  2. Remove unused direct dependencies.
  3. Run `uv lock` to update the lockfile.

---

## 4. Tier 3: Code Hygiene & Performance Gaps (Smaller Things)

### Issue 10: Markdown Table Pipe Injection in Formatters
* **Locations:**
  * [`src/fastmcp/src/cube_fastmcp/formatters.py:91-100`](file:///home/angelo/projects/cube-core-mcp/src/fastmcp/src/cube_fastmcp/formatters.py#L91-L100)
* **Root Cause:** Table cell values are interpolated directly into GFM pipe tables:
  ```python
  row_values = [str(row.get(h, "")) if row.get(h) is not None else "NULL" for h in headers]
  lines.append("| " + " | ".join(row_values) + " |")
  ```
* **Risk & Impact:** If a database string contains pipe characters (`|`) or newline characters (`\n`), the Markdown table structure breaks. The LLM receives corrupted tabular output and hallucinates column alignments.
* **Remediation Blueprint:**
  Sanitize cell values before table rendering:
  ```python
  def _sanitize_cell(val: Any) -> str:
      if val is None:
          return "NULL"
      text = str(val).replace("\r\n", " ").replace("\n", " ")
      return text.replace("|", "\\|")
  ```

---

### Issue 11: Event Loop Blocking & Missing HTTP Connection Pooling
* **Locations:**
  * [`src/fastmcp/src/cube_fastmcp/cube_client.py:53-76`](file:///home/angelo/projects/cube-core-mcp/src/fastmcp/src/cube_fastmcp/cube_client.py#L53-L76)
  * [`src/fastmcp/src/cube_fastmcp/cube_client.py:100-200`](file:///home/angelo/projects/cube-core-mcp/src/fastmcp/src/cube_fastmcp/cube_client.py#L100-L200)
* **Root Cause:**
  1. `_get_cloud_run_id_token()` invokes synchronous `id_token.fetch_id_token()`, blocking Python's single-threaded event loop and stalling concurrent tool calls.
  2. Each API call constructs a new `httpx.AsyncClient()` instance, preventing TCP connection reuse and forcing TLS re-negotiation on every request.
* **Risk & Impact:** Under concurrent load, tool execution latency increases significantly, and event loop starvation occurs.
* **Remediation Blueprint:**
  1. Initialize a long-lived, pooled `httpx.AsyncClient` with explicit `httpx.Limits(max_keepalive_connections=20, max_connections=50)`.
  2. Delegate synchronous token fetching to an execution worker pool using `asyncio.to_thread(_fetch_id_token)`.

---

## 5. Remediation Roadmap & Execution Matrix

| Phase | Focus Area | Specific Actions | Target Components |
| :--- | :--- | :--- | :--- |
| **Phase 1** | **Critical Security Hardening** | 1. Secret Manager + `random_password` for `CUBEJS_API_SECRET`<br/>2. VM cloud-init ADC secret fetch for Cube Store key<br/>3. Flip `dev_mode` default to `false` and gate on `dev` | `terraform/modules/cloud_run`<br/>`terraform/modules/compute` |
| **Phase 2** | **Infrastructure & Reliability** | 1. Compute Engine Spot VM to zonal MIG refactor<br/>2. Region unification (`asia-south1`) in variables & Cloud Build<br/>3. Parameterize container tags (`image_tag`)<br/>4. Wire `CUBEJS_PRE_AGGREGATIONS_SCHEMA`<br/>5. Scope BigQuery IAM to dataset levels | `terraform/modules/compute`<br/>`terraform/modules/bigquery`<br/>`src/cube_store/cloudbuild.yaml` |
| **Phase 3** | **Application & Performance** | 1. Add `pyjwt>=2.8.0` to `pyproject.toml`<br/>2. Sanitize Markdown pipes in `formatters.py`<br/>3. Pooled `httpx.AsyncClient` & `asyncio.to_thread` token calls | `src/fastmcp/` |
