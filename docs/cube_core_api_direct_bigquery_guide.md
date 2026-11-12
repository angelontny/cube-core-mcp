# Tier 4: Cube Core API Direct BigQuery Implementation Plan

This document outlines the step-by-step engineering plan to scaffold, package, deploy, and verify **Cube Core API** on **Google Cloud Run** in Direct BigQuery Mode before integrating the Cube Store OLAP caching engine.

---

## 1. Architectural Strategy: Why Direct Mode First?

Deploying Cube Core in a decoupled, two-stage sequence ensures high reliability, clear failure domain isolation, and cost control:

```
Stage 1 (Current Target): Direct BigQuery Querying
[ Client / Dev ] ──> [ Cloud Run: Cube Core API ] ──> [ BigQuery: analytics dataset ]
                        (Direct VPC Egress pre-wired)     (Direct SQL execution)
                        *Cube Store Spot VM disabled ($0.00 compute)*

Stage 2 (Subsequent Target): Pre-Aggregation Acceleration
[ Client / FastMCP ] ──> [ Cloud Run: Cube Core API ]
                                  │
                                  ├── (Cache Hit: sub-second) ──> [ Cube Store Spot VM (10.10.0.10:3030) ]
                                  │                                         │
                                  │                                         └── (Parquet) ──> [ GCS Cache Bucket ]
                                  │
                                  └── (Cache Miss / Build) ────> [ BigQuery EXPORT DATA ]
```

### Strategic Benefits:
1. **Decoupled Debugging**: Validates that Cube semantic data models, measures, dimensions, and BigQuery IAM permissions function cleanly before adding distributed caching or network socket routing.
2. **Zero Inactive Compute Cost**: Keeping Cube Store disabled (`enable_cube_store = false`) drops Compute Engine Spot VM billing to **$0.00** while developing semantic schemas and testing queries. Cloud Run scales to zero instances when idle.
3. **Isolating Direct VPC Egress**: Proves Cloud Run can reach Google APIs and private VPC subnets without network conflicts.

---

## 2. Directory Layout & Deliverables

```text
cube-core-mcp/
├── src/
│   └── cube/                                 # Cube Core application directory
│       ├── .dockerignore                     # Build context exclusions
│       ├── Dockerfile                        # Lean production container definition
│       ├── cube.js                           # Cube Core server configuration
│       └── model/                            # Semantic data models
│           └── cubes/
│               ├── orders.yml                # Native fct_orders metrics, dimensions, joins
│               ├── order_items.yml           # Native fct_order_items metrics, dimensions, joins
│               ├── products.yml              # Native dim_products attributes and catalog metrics
│               └── users.yml                 # Native dim_users customer demographics
├── terraform/
│   ├── modules/
│   │   ├── cloud_run/                        # Cloud Run Terraform module
│   │   │   ├── main.tf                       # Cloud Run v2 service, Artifact Registry, IAM
│   │   │   ├── variables.tf                  # Sizing, VPC subnet, env vars
│   │   │   └── outputs.tf                    # Service URL, SA email, service name
│   └── main.tf                               # Top-level orchestrator calling cloud_run
└── docs/
    ├── adr_separation_of_dbt_transformations_and_cube_semantic_layer.md
    └── cube_core_api_direct_bigquery_guide.md # This guide
```

---

## 3. Concrete Implementation Steps

### Step 1: Scaffold Native Cube Semantic Models (`src/cube/`)

Deploy declarative, first-class semantic models directly targeting the `analytics` dataset in BigQuery:

#### A. Server Configuration (`src/cube/cube.js`)
Configures query cache options and telemetry; database connection and developer mode are controlled cleanly via environment variables (`CUBEJS_DB_TYPE`, `CUBEJS_DEV_MODE`, `CUBEJS_DB_BQ_PROJECT_ID`):
```javascript
module.exports = {
  telemetry: false,
  orchestratorOptions: {
    queryCacheOptions: {
      refreshKeyRenewalThreshold: 300,
    },
  },
};
```

#### B. Declarative Cube Definitions (`src/cube/model/cubes/`)
1. **`orders.yml`** (Mapping `analytics.fct_orders`):
   - **Joins**: `many_to_one` join to `users`.
   - **Dimensions**: `order_id` (primary key), `user_id`, `order_status`, `gender`, `created_at`, `shipped_at`, `delivered_at`, `returned_at`, `is_returned`.
   - **Measures**: `count`, `total_revenue`, `total_profit`, `total_cost_sum`, `completed_orders_count`, `returned_orders_count`, `return_rate`, `profit_margin_rate`.
2. **`order_items.yml`** (Mapping `analytics.fct_order_items`):
   - **Joins**: `many_to_one` joins to `orders`, `products`, and `users`.
   - **Dimensions**: `order_item_id` (primary key), `order_id`, `user_id`, `product_id`, `item_status`, `ordered_at`, `sale_price`, `cost`, `gross_margin`, `is_returned`, `is_delivered`.
   - **Measures**: `count`, `total_sales`, `total_gross_margin`, `average_sale_price`, `returned_items_count`, `delivered_items_count`.
3. **`products.yml`** (Mapping `analytics.dim_products`):
   - **Dimensions**: `product_id` (primary key), `product_name`, `category`, `brand`, `department`, `cost`, `retail_price`, `profit_margin`, `profit_margin_percent`.
   - **Measures**: `count`, `average_retail_price`, `average_cost`, `average_margin`.
4. **`users.yml`** (Mapping `analytics.dim_users`):
   - **Dimensions**: `user_id` (primary key), `full_name`, `email`, `age`, `age_bracket`, `gender`, `city`, `state`, `country`, `traffic_source`, `registered_at`.
   - **Measures**: `count`.

#### C. Production Container Image (`src/cube/Dockerfile`)
A lean production container extending the official `cubejs/cube:latest` image:
```dockerfile
FROM cubejs/cube:latest

WORKDIR /cube/conf

# Copy semantic models and configuration
COPY cube.js ./
COPY model/ ./model/

EXPOSE 4000

CMD ["cubejs", "server"]
```
COPY model/ ./model/

EXPOSE 4000

CMD ["cubejs", "server"]
```

---

### Step 2: Provision Cloud Run & Artifact Registry in Terraform

Create `terraform/modules/cloud_run/` to manage container registry and serverless deployment:

#### A. Artifact Registry Repository
```hcl
resource "google_artifact_registry_repository" "cube_repo" {
  provider      = google
  location      = var.region
  repository_id = "cube-repo"
  description   = "Docker repository for Cube Core and FastMCP services"
  format        = "DOCKER"
}
```

#### B. Workload Identity & Runtime Service Account
Provision `cloud-run-cube-sa@cube-core-mcp.iam.gserviceaccount.com` with:
* `roles/bigquery.jobUser`: Permits running queries and export jobs in the project.
* `roles/bigquery.dataViewer`: Permits reading tables in the `analytics` and `thelook_ecommerce` datasets.
* `roles/logging.logWriter`: Streams stdout and structured container logs to Google Cloud Logging.

#### C. Cloud Run v2 Service (`cube-api`)
```hcl
resource "google_cloud_run_v2_service" "cube_api" {
  name     = "cube-api"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  # Zero-trust: Unauthenticated invocations (allUsers) are strictly disabled.
  # Requests must provide an Authorization: Bearer $(gcloud auth print-identity-token) header.

  template {
    service_account = google_service_account.cloud_run_cube.email

    scaling {
      min_instance_count = 0  # Scales to zero when inactive ($0.00 cost)
      max_instance_count = 3
    }

    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/cube-repo/cube-api:latest"

      ports {
        container_port = 4000
      }

      resources {
        limits = {
          cpu    = "1000m"  # 1 vCPU
          memory = "1Gi"    # 1 GB RAM
        }
      }

      env {
        name  = "CUBEJS_DB_TYPE"
        value = "bigquery"
      }
      env {
        name  = "CUBEJS_DB_BQ_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "CUBEJS_DB_BQ_LOCATION"
        value = var.region
      }
      env {
        name  = "CUBEJS_DEV_MODE"
        value = "true"  # Enables developer introspections & playground during POC
      }
    }

    # Pre-wired Direct VPC Egress for future Cube Store access
    vpc_access {
      network_interfaces {
        network    = var.vpc_id
        subnetwork = var.subnet_id
      }
      egress = "PRIVATE_RANGES_ONLY"
    }
  }
}
```

---

### Step 3: Container Build & Deployment Execution

Because local Docker is not installed in the agent container, container packaging is executed directly in Google Cloud using **Google Cloud Build**:

```bash
# 1. Enable Artifact Registry API and Cloud Build API if not yet enabled
gcloud services enable artifactregistry.googleapis.com cloudbuild.googleapis.com

# 2. Build and push container directly to Artifact Registry
gcloud builds submit \
  --tag asia-south1-docker.pkg.dev/cube-core-mcp/cube-repo/cube-api:latest \
  src/cube/

# 3. Apply Terraform configuration to deploy the Cloud Run service
cd terraform
terraform apply -var-file=terraform.tfvars
```

---

### Step 4: Verification Runbook (Direct BigQuery Mode)

Once deployed, test Cube Core directly via REST API:

```bash
# 1. Retrieve the Cloud Run public HTTPS endpoint
CUBE_URL=$(gcloud run services describe cube-api --region=asia-south1 --format="value(status.url)")

# 2. Check health status
curl -i "${CUBE_URL}/readyz"

# 3. Execute a semantic query against BigQuery (Count of Orders and Total Sales Amount)
curl -X POST "${CUBE_URL}/cubejs-api/v1/load" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "measures": ["orders.count", "orders.total_amount"]
    }
  }'
```

#### Expected Result:
Cube Core receives the request, constructs a GoogleSQL statement:
```sql
SELECT count(order_id) orders__count, sum(total_amount) orders__total_amount 
FROM `cube-core-mcp.analytics.fct_orders` AS orders
```
executes it against BigQuery via `cloud-run-cube-sa`, and returns the aggregate metric JSON payload within 1-2 seconds.

---

### Step 5: Transition to Stage 2 (Enabling Cube Store Pre-Aggregations)

Once direct BigQuery queries are verified:
1. Re-enable Cube Store in `terraform/terraform.tfvars`:
   ```hcl
   enable_cube_store = true
   ```
2. In `src/cube/model/cubes/orders.yml`, add pre-aggregation definitions:
   ```yaml
   pre_aggregations:
     main:
       measures:
         - count
         - total_amount
       time_dimension: created_at
       granularity: month
   ```
3. Inject Cube Store environment variables in Cloud Run:
   - `CUBEJS_CUBESTORE_HOST = "10.10.0.10"`
   - `CUBEJS_CUBESTORE_PORT = "3030"`
   - `CUBEJS_DB_EXPORT_BUCKET = "cube-core-mcp-cube-store-cache"`
4. Run `terraform apply`. Cube Core will route through Direct VPC Egress to `10.10.0.10:3030`, trigger BigQuery Parquet export into GCS, build the cache, and accelerate future queries from seconds to milliseconds.