# Architecture Decision Records (ADRs)

This directory documents the key architectural decisions for the `cube-core-mcp` platform. Each record follows the Michael Nygard template, documenting context, evaluated options, trade-offs, and consequences.

## Index of Records

| ADR | Title | Status | Date | Primary Focus |
| :--- | :--- | :--- | :--- | :--- |
| [ADR-0001](file:///home/angelo/projects/cube-core-mcp/docs/architecture/adrs/0001_why_cube_store_cannot_run_on_cloud_run.md) | Why Cube Store Cannot Run on Google Cloud Run | Accepted | 2026-11-11 | Storage & Compute Layer |
| [ADR-0002](file:///home/angelo/projects/cube-core-mcp/docs/architecture/adrs/0002_why_systemd_supervises_cube_store_on_cos.md) | Why systemd Supervises Cube Store on Container-Optimized OS | Accepted | 2026-11-11 | Reliability & Lifecycle |
| [ADR-0003](file:///home/angelo/projects/cube-core-mcp/docs/architecture/adrs/0003_separation_of_dbt_transformations_and_cube_semantic_layer.md) | Separation of dbt Transformations and Cube Semantic Layer | Accepted | 2026-11-11 | Modeling & Modularity |
| [ADR-0004](file:///home/angelo/projects/cube-core-mcp/docs/architecture/adrs/0004_multi_container_pod_vs_separate_services.md) | Multi-Container Cloud Run Pod vs. Separate Services | Accepted | 2026-11-14 | Serving Architecture & Latency |
| [ADR-0005](file:///home/angelo/projects/cube-core-mcp/docs/architecture/adrs/0005_artifact_registry_mirroring_vs_cloud_nat.md) | Artifact Registry Image Mirroring vs. Cloud NAT Gateway | Accepted | 2026-11-14 | Networking & FinOps |
| [ADR-0006](file:///home/angelo/projects/cube-core-mcp/docs/architecture/adrs/0006_jinja_safe_cross_project_bigquery_federation.md) | Dynamic Jinja `\| safe` Table Prefixing for Cross-Project Federation | Accepted | 2026-11-14 | Multi-Tenant Warehouse Federation |
| [ADR-0007](file:///home/angelo/projects/cube-core-mcp/docs/architecture/adrs/0007_fastmcp_streamable_http_oauth_rfc6750.md) | FastMCP Streamable HTTP / SSE Transport and RFC 6750 OAuth | Accepted | 2026-11-14 | AI Protocol & Token Efficiency |
