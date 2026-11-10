# System Instructions for AI Coding Agents

## 1. Mission
`cube-core-mcp` is a serverless, cross-cloud semantic layer designed to bridge enterprise data warehouses (Google BigQuery) with LLM client interfaces (Claude Code, Claude Desktop) via the Model Context Protocol (MCP). The architecture couples a containerized Cube Core semantic engine (hydrated with dbt `manifest.json` metadata) and a custom FastMCP Python translation service on Google Cloud Run, supported by an out-of-process Cube Store cache node running on Compute Engine Spot VMs backed by Cloud Storage Parquet persistence.

## 2. Tech Stack
* **Infrastructure as Code:** HashiCorp Terraform (`>= 1.5.0`), Google Provider (`~> 5.30`), Time Provider (`~> 0.11`)
* **Cloud Platform:** Google Cloud Platform (Cloud Run v2, Compute Engine Spot MIG, Google Cloud Storage, Serverless VPC Direct Egress, Cloud Logging, IAM)
* **Application & Semantic Engine:** Cube Core (Docker/Node runtime), Cube Store Standalone (Rust-based storage engine)
* **MCP Service Layer:** Python (`>= 3.11`), FastMCP SDK, `uv` package manager
* **Upstream Data Layer:** dbt Core/Cloud (`manifest.json` semantic schema), Google BigQuery
* **Security & Protocols:** OAuth 2.1 (Google Workspace Bearer tokens), Server-Sent Events (SSE), stdio local bridge

## 3. Architecture & Directory Structure
The repository strictly isolates infrastructure automation, application services, and documentation:

```text
cube-core-mcp/
├── docs/                                  # Architectural specifications and runbooks
│   ├── bootstrap_terraform_sa.sh          # Automated Tier 0 SA bootstrap script
│   ├── cube_core_architecture_and_gcp_mapping.md # Cube Core architecture, GCP mappings, & query lifecycle
│   ├── cube_core_implementation_plan.md   # Step-by-step 5-tier infrastructure & service delivery plan
│   ├── terraform_modularization_and_state_migration.md # Modularization rationale & state migration runbook
│   ├── semantic_layer_execution_plan.md   # Five-phase project roadmap and delivery milestones
│   ├── terraform_setup_and_authentication.md # 8-step workstation setup, ADC, and state migration runbook
│   ├── terraform_service_account_bootstrap.md # Two-tier IAM architecture and rationale
│   └── bigquery_setup_and_sample_data.md  # BigQuery architecture, DTS sample ingestion, & prod guide
├── terraform/                             # Declarative cloud infrastructure
│   ├── versions.tf                        # Engine, Terraform, and provider version pins
│   ├── backend.tf                         # Partial GCS remote state configuration (prefix only)
│   ├── providers.tf                       # GCP provider definition with common labels
│   ├── variables.tf                       # Strongly typed input variables and workload API definitions
│   ├── terraform.tfvars.example           # Committed template for environment variables
│   ├── services.tf                        # Declarative workload API enablement and propagation timers
│   ├── state_bucket.tf                    # GCS remote state bucket definition
│   ├── bigquery.tf                        # BigQuery datasets and cross-region Data Transfer config
│   ├── outputs.tf                         # Exported infrastructure attributes and endpoints
│   └── (Phase 1 planned modules)          # networking.tf, storage.tf, compute.tf, cloud_run.tf
├── src/                                   # Application code (Phases 2-4)
│   ├── dbt/                               # Native dbt project (thelook transformations & manifest generator)
│   ├── cube/                              # Cube Core Dockerfile, schema definitions, dbt parsers
│   ├── fastmcp/                           # Python FastMCP service, OAuth middleware, formatters
│   └── bridge/                            # Local stdio-to-SSE proxy bridge with OS keychain integration
├── README.md                              # Repository overview and quickstart guide
└── AGENT.md                               # AI agent system prompt and operating parameters
```

## 4. Toolchain & Execution
All commands must be executed from their respective root directories without bypass flags.

### dbt Project Lifecycle (`cd src/dbt`)
* **Debug Connection:** `export DBT_PROFILES_DIR=. && dbt debug`
* **Run / Build Models:** `export DBT_PROFILES_DIR=. && dbt build`
* **Compile Manifest for Cube Core:** `export DBT_PROFILES_DIR=. && dbt compile`

### Terraform Lifecycle (`cd terraform`)
* **Format:** `terraform fmt -check` (inspect) or `terraform fmt` (apply format)
* **Validate:** `terraform validate`
* **Initialize:** `terraform init` (local state) or `terraform init -backend-config="bucket=<PROJECT_ID>-tfstate"` (partial GCS backend)
* **Migrate State:** `terraform init -backend-config="bucket=<PROJECT_ID>-tfstate" -migrate-state`
* **Plan:** `terraform plan -var-file=terraform.tfvars`
* **Apply:** `terraform apply -var-file=terraform.tfvars`

### FastMCP Python Service (`cd src/fastmcp` once initialized)
* **Dependency Sync:** `uv sync`
* **Local Development Server:** `uv run python -m fastmcp.server --dev`
* **Linting & Formatting:** `uv run ruff check .` and `uv run ruff format --check .`
* **Type Checking:** `uv run mypy .`
* **Unit & Integration Tests:** `uv run pytest tests/`

### Cube Core Container (`cd src/cube` once initialized)
* **Build Image:** `docker build -t cube-core:latest .`
* **Run Local Verification:** `docker run --rm -p 4000:4000 --env-file .env cube-core:latest`

## 5. Coding Conventions
1. **Style and Tone (Strict Emoji Ban):** Never include emojis in documentation, code comments, commit messages, or terminal outputs. Maintain an objective, professional, and concise technical tone at all times.
2. **Infrastructure Idempotency:** In Terraform, always set `disable_on_destroy = false` on `google_project_service`. Never manage the Terraform deployment Service Account's own foundational IAM roles within Terraform code.
3. **API Propagation Guards:** All infrastructure resources that depend on newly activated GCP services must declare an explicit dependency on `time_sleep.wait_for_services` to prevent Google Cloud control-plane race conditions.
4. **Type Strictness:** All Python code must use strict type hints validated by `mypy`. All Terraform variables must declare explicit `type`, `description`, and appropriate default or validation rules.
5. **Payload Optimization:** FastMCP query responses delivered to LLM callers must compress verbose JSON payloads into token-efficient Markdown tables or dense CSV strings. Never pipe raw tabular payloads without contextual reduction.
6. **Partial Backend Configuration:** Never interpolate variables or hardcode project-specific bucket names into `backend "gcs"` blocks (Terraform strictly prohibits variable interpolation in backend blocks). Declare only `prefix = "terraform/state"` in `backend.tf` and pass `-backend-config="bucket=..."` dynamically during initialization.
7. **Tier 0 vs Tier 1 API Separation:** Foundational APIs (`serviceusage`, `cloudresourcemanager`, `iam`) are managed strictly by the Tier 0 bootstrap script. Terraform exclusively manages workload APIs (`compute`, `run`, `storage`, `vpcaccess`, `logging`) in `services.tf`.

## 6. Judgment Boundaries

* **ALWAYS:**
  * Use Application Default Credentials (ADC) and Service Account impersonation (`--impersonate-service-account`); never generate or accept static Service Account JSON keys.
  * Run `terraform fmt` and `terraform validate` before proposing infrastructure changes.
  * Preserve existing comments, docstrings, and documentation integrity when modifying files.
  * Keep `.gitignore` updated to guarantee zero accidental leakage of `.tfstate`, `*.tfvars`, or credentials.

* **ASK:**
  * Ask before executing any command that provisions billable cloud infrastructure (`terraform apply`).
  * Ask before running any destructive command (`terraform destroy`, deleting storage buckets, tearing down VPCs).
  * Ask before altering IAM role bindings on external projects (e.g., cross-project BigQuery access).
  * Ask before upgrading major provider or runtime engine versions.

* **NEVER:**
  * Never commit secrets, OAuth client secrets, API tokens, service account keys, or internal network IPs to version control.
  * Never execute `git commit` or `git push` unless explicitly ordered by the user.
  * Never use emojis anywhere in markdown documentation or codebases.
  * Never hardcode GCP credentials paths or static tokens inside Terraform provider blocks.
  * Never use authoritative IAM resources (`google_project_iam_binding`) that can overwrite project-level permissions; use additive resources (`google_project_iam_member`) exclusively.
