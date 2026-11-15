# System Documentation Catalog

Welcome to the technical documentation for the **Cube Core + FastMCP Semantic Layer on Google Cloud Platform (GCP)**.

The documentation follows the **Diátaxis Documentation Framework**, organizing technical content into four distinct user needs:

```
┌──────────────────────────────────────────────────────────────┐
│                    Diátaxis Documentation Framework           │
├──────────────────────────────┬───────────────────────────────┤
│ Learning-Oriented            │ Problem-Oriented              │
│ 1. Tutorials & Guides        │ 2. How-To & Runbooks          │
├──────────────────────────────┼───────────────────────────────┤
│ Understanding-Oriented       │ Information-Oriented          │
│ 3. Architecture & ADRs (C4)  │ 4. Technical Reference        │
└──────────────────────────────┴───────────────────────────────┘
```

---

## 1. Tutorials & Getting Started (Learning-Oriented)

Step-by-step onboarding walkthroughs for developers and operators:

* [End-to-End Plug-and-Play Installation Guide](file:///home/angelo/projects/cube-core-mcp/docs/guides/plug_and_play_installation_guide.md) — Comprehensive guide covering project bootstrap, container mirroring, OAuth setup, Terraform deployment, and Claude/Cursor client connection.
* [Terraform Setup & Authentication Guide](file:///home/angelo/projects/cube-core-mcp/docs/guides/terraform_setup_and_authentication.md) — Workstation tooling installation, Application Default Credentials (ADC) setup, and remote GCS state migration.
* [BigQuery Architecture & Sample Data Guide](file:///home/angelo/projects/cube-core-mcp/docs/guides/bigquery_setup_and_sample_data.md) — Public eCommerce sample data ingestion via BigQuery Data Transfer Service (DTS) and production transition steps.

---

## 2. Operational How-To Guides & Runbooks (Task-Oriented)

Practical runbooks for day-to-day administration, health verification, and debugging:

* [Cloud Run Troubleshooting & Error Runbook](file:///home/angelo/projects/cube-core-mcp/docs/operations/cloud_run_troubleshooting_and_error_runbook.md) — Detailed diagnoses and solutions for container startup failures, Jinja escapes, IAM permissions, and probe timeouts.
* [gcloud Health Check Runbook](file:///home/angelo/projects/cube-core-mcp/docs/operations/gcloud_health_check_runbook.md) — Copy-pasteable CLI commands to verify BigQuery, GCS, VPC subnets, Spot VM IAP access, and Cloud Run status.
* [FastMCP Local Testing & Verification Guide](file:///home/angelo/projects/cube-core-mcp/docs/guides/fastmcp_local_testing_and_verification.md) — Local inspection, mock unit testing, CLI tool invocation, and interactive Dev UI.
* [Tier 0 Automated Bootstrap Script](file:///home/angelo/projects/cube-core-mcp/docs/operations/bootstrap_terraform_sa.sh) — Shell script automating project API enablement, provisioning service account creation, and keyless ADC grants.

---

## 3. Architecture, C4 Models & Decision Records (Understanding-Oriented)

Technical foundations explaining *why* the system is designed this way—including trade-offs, alternatives, dependencies, and temporary workarounds:

* [C4 Architecture & Design Context](file:///home/angelo/projects/cube-core-mcp/docs/architecture/c4_architecture_and_design_context.md) — System Context (Level 1), Container Diagram (Level 2), Component Breakdown (Level 3), and Query Lifecycle (Level 4), supported by the Architectural Trade-offs Matrix and Known Workarounds.
* [Production Readiness Audit & Hardening Roadmap](file:///home/angelo/projects/cube-core-mcp/docs/architecture/production_readiness_audit.md) — Comprehensive technical review identifying security vulnerabilities, reliability single-points-of-failure, and the 3-phase remediation plan.
* [Architecture Decision Records (ADRs) Index](file:///home/angelo/projects/cube-core-mcp/docs/architecture/adrs/README.md):
  * [ADR-0001: Why Cube Store Cannot Run on Cloud Run](file:///home/angelo/projects/cube-core-mcp/docs/architecture/adrs/0001_why_cube_store_cannot_run_on_cloud_run.md)
  * [ADR-0002: Why systemd Supervises Cube Store on Container-Optimized OS](file:///home/angelo/projects/cube-core-mcp/docs/architecture/adrs/0002_why_systemd_supervises_cube_store_on_cos.md)
  * [ADR-0003: Separation of dbt Transformations and Cube Semantic Layer](file:///home/angelo/projects/cube-core-mcp/docs/architecture/adrs/0003_separation_of_dbt_transformations_and_cube_semantic_layer.md)
  * [ADR-0004: Multi-Container Cloud Run Pod vs. Separate Services](file:///home/angelo/projects/cube-core-mcp/docs/architecture/adrs/0004_multi_container_pod_vs_separate_services.md)
  * [ADR-0005: Artifact Registry Image Mirroring vs. Cloud NAT Gateway](file:///home/angelo/projects/cube-core-mcp/docs/architecture/adrs/0005_artifact_registry_mirroring_vs_cloud_nat.md)
  * [ADR-0006: Dynamic Jinja `| safe` Table Prefixing for Cross-Project Federation](file:///home/angelo/projects/cube-core-mcp/docs/architecture/adrs/0006_jinja_safe_cross_project_bigquery_federation.md)
  * [ADR-0007: FastMCP Streamable HTTP / SSE Transport and RFC 6750 Google OAuth](file:///home/angelo/projects/cube-core-mcp/docs/architecture/adrs/0007_fastmcp_streamable_http_oauth_rfc6750.md)

---

## 4. Technical Reference (Information-Oriented)

Exhaustive API schemas, configurations, and environment parameters:

* [Terraform Infrastructure Modules Reference](file:///home/angelo/projects/cube-core-mcp/docs/reference/terraform_modules.md) — Consolidated inputs, outputs, and dependencies for BigQuery, Storage, Networking, Compute, and Cloud Run modules.
* [FastMCP Analytical Tools & API Reference](file:///home/angelo/projects/cube-core-mcp/docs/reference/fastmcp_api_and_tools.md) — Specifications for `get_metadata`, `run_semantic_query`, `run_sql_query`, and `explain_sql_query`, including arguments, response formats, and error handling.
* [Cube Core Modeling & Configuration Reference](file:///home/angelo/projects/cube-core-mcp/docs/reference/cube_core_modeling_and_config.md) — Declarative YAML schema syntax, join semantics, calculated measures, pre-aggregations, and runtime environment variables.

---

## 5. Project Roadmap & Technical Debt (Backlog)

Roadmaps and backlogs guiding future iterations:

* [Semantic Layer Five-Phase Execution Plan](file:///home/angelo/projects/cube-core-mcp/docs/backlog/execution_plan.md) — Milestone delivery tracking across infrastructure, semantic engine, FastMCP, and local client bridge.
* [Project-Wide Technical Debt & Improvement Plan](file:///home/angelo/projects/cube-core-mcp/docs/backlog/project_wide_debt.md) — Engineering debt tracking (GCS lifecycle policy, Makefile automation, pre-commit hooks, CI/CD).
* [Engineering Task Backlog](file:///home/angelo/projects/cube-core-mcp/docs/backlog/todo_list.md) — Prioritized operational task list.
