# ADR-0006: Dynamic Jinja `| safe` Table Prefixing for Zero-Downtime Cross-Project Warehouse Federation

* **Status:** Accepted
* **Date:** 2026-11-14 (Updated 2026-11-15)
* **Deciders:** Semantic Engineering & Data Architecture Team
* **Consulted:** BigQuery Admin, Security
* **Informed:** Analytics Engineers

---

## 1. Context and Problem Statement

In enterprise data architectures, raw and modeled warehouse tables frequently reside in a centralized, locked-down data warehouse Google Cloud project (e.g., `prod-analytics-dw`), while application compute services (such as Cube Core and FastMCP) run in a separate serving or consumer project (e.g., `cube-serving-platform`).

In Google BigQuery:
* Local queries can address tables simply as `dataset.table_name`.
* Cross-project queries **must** fully qualify the target table using backticks: `` `target-project-id`.dataset.table_name ``.

If Cube Core semantic models hardcode table paths, schemas become tightly coupled to a single environment. Moving between local development, staging, single-project sandboxes, and cross-project enterprise warehouses requires modifying every YAML file in the semantic layer.

Furthermore, when attempting to inject environment variables via Cube's embedded Jinja engine (`{{ env_var('CUBEJS_REPORTING_TABLE_PREFIX') }}`), Cube's parser automatically JSON-escapes the variable string by default, generating fatal malformed YAML tokens (e.g., `""analytics".fct_orders"`), crashing the container during startup.

---

## 2. Decision Drivers

* **Plug-and-Play Portability:** A single set of Cube models must run unmodified across single-project mode (serving project == warehouse project) and cross-project mode (serving project != warehouse project).
* **Zero Container Mutation:** Deploying across environments must be driven exclusively through environment variables and Terraform variables (`reporting_project_id`, `reporting_dataset_id`).
* **Parser Stability:** Preventing YAML syntax errors caused by Jinja escaping.

---

## 3. Considered Options

* **Option 1: Separate Git Branches or Schema Directories per Environment**
* **Option 2: BigQuery Authorized Views in the Serving Project pointing to the Warehouse Project**
* **Option 3: Dynamic Jinja `| safe` Interpolation with Terraform-Computed Prefix (Selected)**

---

## 4. Evaluation and Decision Outcome

**Chosen Option:** **Option 3: Dynamic Jinja `| safe` Interpolation with Terraform-Computed Prefix**.

### Technical Mechanics

#### 1. Semantic Model Syntax in Cube YAML
Every data model in [src/cube/model/cubes/](file:///home/angelo/projects/cube-core-mcp/src/cube/model/cubes/) resolves its `sql_table` with the `| safe` Jinja filter:

```yaml
cubes:
  - name: orders
    sql_table: "{{ env_var('CUBEJS_REPORTING_TABLE_PREFIX', 'analytics') | safe }}.fct_orders"
```

The `| safe` filter explicitly signals to the Jinja compiler that the string is trusted raw SQL, suppressing string quotation and escaping.

#### 2. Declarative Terraform Variable Resolution
In [terraform/modules/cloud_run/main.tf](file:///home/angelo/projects/cube-core-mcp/terraform/modules/cloud_run/main.tf):

```hcl
locals {
  reporting_project_id   = var.reporting_project_id != "" ? var.reporting_project_id : var.project_id
  reporting_table_prefix = var.reporting_project_id != "" && var.reporting_project_id != var.project_id ? "`${var.reporting_project_id}`.${var.reporting_dataset_id}" : var.reporting_dataset_id
}
```

* **Single-Project Mode:** When `reporting_project_id` is empty `""`, `reporting_table_prefix` resolves to `analytics`. Cube generates:
  `FROM analytics.fct_orders`
* **Cross-Project Mode:** When `reporting_project_id` is `"enterprise-data-prod"`, `reporting_table_prefix` resolves to `` `enterprise-data-prod`.analytics ``. Cube generates:
  `` FROM `enterprise-data-prod`.analytics.fct_orders ``

#### 3. Automated Cross-Project IAM Binding
When operating in cross-project mode, Terraform automatically provisions read permissions on the external dataset:

```hcl
resource "google_bigquery_dataset_iam_member" "cross_project_reporting_reader" {
  count      = (var.reporting_project_id != "" && var.reporting_project_id != var.project_id) ? 1 : 0
  project    = var.reporting_project_id
  dataset_id = var.reporting_dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.cloud_run_cube.email}"
}
```

---

## 5. Consequences

### Positive Consequences
* **100% Zero-Touch Semantic Portability:** Not a single line of Cube YAML changes between environments or target warehouse configurations.
* **Hermetic IAM Security:** Cross-project dataset reader rights are provisioned strictly when cross-project mode is enabled, following least privilege.
* **Elimination of Container Crash Loops:** The `| safe` filter prevents `YAMLException` syntax crashes on boot.

### Negative Consequences / Risks
* Analytics engineers writing new cubes must adhere to the `{{ env_var(...) | safe }}` convention (enforced via documentation and code reviews).

---

## 6. Related Documents
* [ADR-0003: Separation of dbt Transformations and Cube Semantic Layer](file:///home/angelo/projects/cube-core-mcp/docs/architecture/adrs/0003_separation_of_dbt_transformations_and_cube_semantic_layer.md)
* [ADR-0004: Multi-Container Cloud Run Pod vs. Separate Services](file:///home/angelo/projects/cube-core-mcp/docs/architecture/adrs/0004_multi_container_pod_vs_separate_services.md)
* [docs/guides/plug_and_play_installation_guide.md](file:///home/angelo/projects/cube-core-mcp/docs/guides/plug_and_play_installation_guide.md)
