# End-to-End Plug-and-Play Installation & Deployment Guide

This guide provides step-by-step instructions for deploying a production-ready, serverless semantic layer architecture on Google Cloud Platform (GCP). The architecture integrates **Cube Core** (semantic modeling, caching, and pre-aggregations) and **FastMCP** (Model Context Protocol wrapper with Google OAuth 2.0) on **Google Cloud Run v2**, backed by an optional **Cube Store** OLAP cache on an ephemeral Compute Engine Spot VM and persistent Parquet storage in Google Cloud Storage.

This deployment is **plug-and-play**: it can connect directly to any Google BigQuery reporting dataset, either hosted in the same GCP project (single-project mode) or across separate enterprise warehouse projects (cross-project mode).

---

## 1. Architecture & Plug-and-Play Model

```
[ AI Assistant Client (Claude Web / Claude Desktop / Cursor) ]
                          │
                          ▼ (HTTPS / Streamable HTTP or SSE + Google OAuth 2.0)
┌────────────────────────────────────────────────────────────────────────┐
│ Cloud Run v2 Multi-Container Pod (Serverless Ingress & Semantic Core)  │
│                                                                        │
│   ┌──────────────────────────────┐    ┌──────────────────────────────┐ │
│   │ FastMCP Ingress (Port 8080)   │───▶│ Cube Core Sidecar (Port 4000)│ │
│   │ - Google OAuth 2.0 Auth      │    │ - Semantic YAML Models       │ │
│   │ - 4 MCP Analytical Tools     │    │ - SQL API & Planner Engine   │ │
│   └──────────────────────────────┘    └──────────────────────────────┘ │
└───────────────────────────────────────────────────┬────────────────────┘
                          │ (Direct VPC Egress)     │ (BigQuery API / Jobs)
                          ▼                         ▼
┌───────────────────────────────────────┐ ┌──────────────────────────────┐
│ Private VPC Network (cube-network)    │ │ Target Data Warehouse (BQ)   │
│                                       │ │                              │
│   ┌─────────────────────────────────┐ │ │ Project:                     │
│   │ Cube Store Cache (Spot VM)      │ │ │   var.reporting_project_id   │
│   │ - MySQL Wire (Port 3030)        │ │ │ Dataset:                     │
│   │ - Metastore & RocksDB Engine    │ │ │   var.reporting_dataset_id   │
│   └────────────────┬────────────────┘ │ │                              │
└────────────────────┼──────────────────┘ └──────────────────────────────┘
                     ▼ (GCS API via Private Google Access)
┌───────────────────────────────────────┐
│ Google Cloud Storage (Bucket)         │
│   gs://<serving-project>-cube-store-cache │
│   - Checkpoints & Parquet Chunks      │
└───────────────────────────────────────┘
```

### 1.1 Single-Project vs. Cross-Project Modes

The configuration automatically adjusts its permissions and table identifiers based on two input variables in `terraform.tfvars`:

* **Single-Project Mode**: `reporting_project_id` is left empty `""` or matches `project_id`. The serving infrastructure and the BigQuery reporting dataset reside in the same project. All IAM roles (`roles/bigquery.dataEditor`, `roles/bigquery.jobUser`) are applied locally.
* **Cross-Project Mode**: `reporting_project_id` is set to an external Google Cloud project (e.g., `analytics-prod-data`). Cube Core compiles table targets with fully qualified project prefixes (`` `project_a`.reporting_dataset.table_name ``), and Terraform provisions cross-project dataset reader access for the runtime service account.

### 1.2 Zero-Cost Resting State Model

When idle, the infrastructure can be toggled into a resting state where no continuous hourly charges are incurred:
* **No Cloud NAT**: Worker instances pull images from Google Artifact Registry using Private Google Access.
* **Serverless Scale to Zero**: Cloud Run scales to zero instances when traffic drops.
* **Spot VM Toggle**: Compute Engine instances can be toggled on or off with `enable_cube_store = false`, yielding a baseline monthly cost of ~$0.00 to $0.03/month.

---

## 2. Prerequisites & Workstation Tooling

Before proceeding, ensure your local workstation has the required administrative tooling installed:

### 2.1 Official Tooling Installation Guides
* **HashiCorp Terraform** (v1.5.0 or later): Follow the [Official HashiCorp Terraform Installation Guide](https://developer.hashicorp.com/terraform/install).
* **Google Cloud SDK (`gcloud`)**: Follow the [Official Google Cloud SDK Installation Guide](https://cloud.google.com/sdk/docs/install).

### 2.2 Local Runtimes & Dependencies
Verify the following utilities are accessible in your system `PATH`:
```bash
terraform version
gcloud version
git --version
curl --version
python3 --version  # Python 3.11+ recommended
```

### 2.3 GCP Account & Access Requirements
Ensure you have:
1. An active Google Cloud billing account.
2. A dedicated GCP project to host the serving infrastructure (`project_id`).
3. Principal IAM access with `roles/owner` or `roles/resourcemanager.projectIamAdmin` + `roles/editor` on the serving project.
4. Read access to the target BigQuery reporting dataset (`roles/bigquery.dataViewer` or higher) if operating in cross-project mode.

---

## 3. Tier 0: GCP Project & IAM Bootstrap

To maintain strict security separation and reproducible infrastructure management, deploy using a dedicated Terraform provisioning service account rather than individual user credentials.

### 3.1 Authenticate and Select the Serving Project
```bash
# 1. Log in to your Google Cloud user account
gcloud auth login

# 2. Set the default serving project
export PROJECT_ID="your-serving-project-id"
export REGION="asia-south1"

gcloud config set project "$PROJECT_ID"
```

### 3.2 Execute the Automated Bootstrap Script
The repository provides an automated Tier 0 setup script: [docs/bootstrap_terraform_sa.sh](file:///home/angelo/projects/cube-core-mcp/docs/bootstrap_terraform_sa.sh).

This script performs the following steps:
1. Creates the provisioning service account: `terraform@<project_id>.iam.gserviceaccount.com`.
2. Provisions the encrypted remote GCS state bucket: `gs://<project_id>-tfstate`.
3. Grants essential least-privilege administrative roles:
   * `roles/resourcemanager.projectIamAdmin`
   * `roles/serviceusage.serviceUsageAdmin`
   * `roles/run.admin`
   * `roles/compute.admin`
   * `roles/storage.admin`
   * `roles/bigquery.admin`
   * `roles/artifactregistry.admin`
   * `roles/secretmanager.admin`
   * `roles/cloudbuild.builds.editor`
4. Grants your authenticated user `roles/iam.serviceAccountTokenCreator` on the Terraform service account to enable zero-key local impersonation.

Run the script:
```bash
chmod +x docs/bootstrap_terraform_sa.sh
./docs/bootstrap_terraform_sa.sh
```

### 3.3 Configure Workstation Service Account Impersonation
Verify impersonation without generating static JSON key files:
```bash
gcloud auth print-access-token \
  --impersonate-service-account="terraform@${PROJECT_ID}.iam.gserviceaccount.com"
```

---

## 4. Generic Semantic Data Modeling (Cube Core)

Cube Core models your BigQuery tables into dimensions, measures, and pre-aggregations.

### 4.1 Plug-and-Play Table Resolution (`| safe`)
To enable plug-and-play compatibility across single-project and cross-project BigQuery schemas, all data models in [src/cube/model/cubes/](file:///home/angelo/projects/cube-core-mcp/src/cube/model/cubes/) must reference tables dynamically via the `env_var` Jinja function appended with the `| safe` filter:

```yaml
cubes:
  - name: orders
    sql_table: "{{ env_var('CUBEJS_REPORTING_TABLE_PREFIX', 'analytics') | safe }}.fct_orders"
    description: "Order-level grain fact table containing total sale amounts, margins, and statuses."

    dimensions:
      - name: id
        sql: order_id
        type: number
        primary_key: true

      - name: status
        sql: order_status
        type: string

      - name: created_at
        sql: created_at
        type: time

    measures:
      - name: count
        type: count

      - name: total_revenue
        sql: sale_price
        type: sum
        format: currency

    pre_aggregations:
      - name: orders_status_summary
        type: rollup
        measures:
          - count
          - total_revenue
        dimensions:
          - status
```

> [!IMPORTANT]
> The `| safe` filter is mandatory when concatenating table names. Without `| safe`, Cube's Jinja compiler JSON-escapes the variable, producing `""analytics".fct_orders"`, which causes a fatal `YAMLException` upon container boot.

---

## 5. Container Builds & Artifact Registry Setup

### 5.1 Private Mirroring of Cube Store (Zero-NAT Cost Optimization)
Compute Engine Spot VMs pulling public images directly from Docker Hub require Cloud NAT gateways (~$32.40/month). To eliminate this cost, mirror the upstream Cube Store image into your private Google Artifact Registry.

#### Option A: Serverless Mirroring via Cloud Build (Recommended, No Local Docker Required)
You can mirror the image entirely in the cloud without needing a local Docker engine:
```bash
# 1. Enable Artifact Registry & Cloud Build APIs
gcloud services enable artifactregistry.googleapis.com cloudbuild.googleapis.com

# 2. Create the Artifact Registry repository if not already created
gcloud artifacts repositories create cube-repo \
  --repository-format=docker \
  --location="$REGION" \
  --description="Docker repository for Cube Core, FastMCP, and Cube Store"

# 3. Submit the build to pull, tag, and push into Artifact Registry
gcloud builds submit src/cube_store \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --impersonate-service-account="terraform@${PROJECT_ID}.iam.gserviceaccount.com" \
  --config=src/cube_store/cloudbuild.yaml
```

#### Option B: Local Docker Mirroring
If you have Docker installed and running locally:
```bash
docker pull cubejs/cubestore:latest
docker tag cubejs/cubestore:latest "${REGION}-docker.pkg.dev/${PROJECT_ID}/cube-repo/cube-store:latest"
docker push "${REGION}-docker.pkg.dev/${PROJECT_ID}/cube-repo/cube-store:latest"
```

### 5.2 Build and Push Cube Core (`cube-api:latest`)
Build the Cube Core semantic engine image using Google Cloud Build:
```bash
gcloud builds submit \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --impersonate-service-account="terraform@${PROJECT_ID}.iam.gserviceaccount.com" \
  --tag="${REGION}-docker.pkg.dev/${PROJECT_ID}/cube-repo/cube-api:latest" \
  src/cube/
```

### 5.3 Build and Push FastMCP (`fastmcp-api:latest`)
Build the FastMCP Python serving wrapper image:
```bash
gcloud builds submit \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --impersonate-service-account="terraform@${PROJECT_ID}.iam.gserviceaccount.com" \
  --tag="${REGION}-docker.pkg.dev/${PROJECT_ID}/cube-repo/fastmcp-api:latest" \
  src/fastmcp/
```

---

## 6. Authentication & Google OAuth 2.0 (Secret Manager)

FastMCP secures all MCP endpoints via Google OAuth 2.0 (RFC 6750 / Protected Resource Metadata).

### 6.1 Configure OAuth Consent Screen
1. In the Google Cloud Console, navigate to **APIs & Services > OAuth consent screen**.
2. Select **External** (or **Internal** if using Google Workspace).
3. Set the Application Name (e.g., `Cube Semantic Layer MCP`) and User Support Email.
4. Add the `openid` scope.
5. In **Test Users**, add your Google email address (e.g., `your-email@example.com`).

### 6.2 Create OAuth 2.0 Web Application Credentials
1. Navigate to **APIs & Services > Credentials > Create Credentials > OAuth client ID**.
2. Select Application Type: **Web application**.
3. Name: `fastmcp-cloud-run-client`.
4. Under **Authorized redirect URIs**, add:
   * Your Cloud Run endpoint callback (obtained after first deployment or pre-calculated):
     `https://<service-name>-<hash>-<region>.a.run.app/auth/callback`
   * Local bridge callback:
     `http://localhost:21081/oauth/callback`
5. Click **Create** and record your **Client ID** and **Client Secret**.

### 6.3 Ingest Credentials into Google Secret Manager
Store the OAuth credentials securely in Secret Manager:
```bash
# Ingest Client ID
echo -n "YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com" | gcloud secrets create fastmcp-google-client-id \
  --data-file=- \
  --replication-policy="automatic" \
  --project="$PROJECT_ID"

# Ingest Client Secret
echo -n "YOUR_GOOGLE_CLIENT_SECRET" | gcloud secrets create fastmcp-google-client-secret \
  --data-file=- \
  --replication-policy="automatic" \
  --project="$PROJECT_ID"
```

---

## 7. Infrastructure Provisioning via Terraform

### 7.1 Configure Variables ([terraform/terraform.tfvars](file:///home/angelo/projects/cube-core-mcp/terraform/terraform.tfvars))
Edit `terraform/terraform.tfvars` with your project parameters:

```hcl
project_id                   = "your-serving-project-id"
region                       = "asia-south1"
zone                         = "asia-south1-c"
environment                  = "dev"

# Target Data Warehouse Settings (Plug and Play)
# For cross-project mode, provide the external project ID:
reporting_project_id         = ""            # Leave "" if tables are in the serving project
reporting_dataset_id         = "analytics"   # Name of your curated BigQuery dataset

# Feature Switches
enable_cube_store            = true          # Set true to launch Spot VM L2 cache node
enable_cloud_run             = true          # Set true to deploy serverless serving pod
google_auth_enabled          = true          # Enforce OAuth 2.0 authentication
fastmcp_transport            = "streamable-http" # Recommended for Claude Web / Modern MCP

# Cost Optimization Sizing
cube_store_machine_type      = "e2-small"
cube_store_boot_disk_size_gb = 10

# Ingress Access
invoker_members = [
  "allUsers"                                 # FastMCP enforces OAuth at the application tier
]
```

### 7.2 Initialize and Deploy
Execute Terraform using the impersonated provisioning service account:

```bash
cd terraform

# 1. Initialize remote GCS backend
terraform init -backend-config="bucket=${PROJECT_ID}-tfstate"

# 2. Validate configuration
terraform validate

# 3. Plan deployment
terraform plan -var-file=terraform.tfvars

# 4. Apply deployment
terraform apply -auto-approve -var-file=terraform.tfvars
```

---

## 8. Post-Deployment Verification & Cache Diagnostics

### 8.1 Verify Health Probes
Retrieve the public Cloud Run HTTPS endpoint:
```bash
export SERVICE_URL=$(terraform output -raw cloud_run_service_uri)
echo "Serving URL: $SERVICE_URL"
```

Verify that the root ingress endpoint returns `HTTP 404` (FastAPI baseline response):
```bash
curl -i -s "$SERVICE_URL/"
```

### 8.2 Verify RFC 6750 Protected Resource Discovery
Verify that FastMCP correctly returns Protected Resource Metadata and triggers authentication challenges:
```bash
# 1. Probe the MCP endpoint (should return HTTP 401 with resource metadata header)
curl -i -s "$SERVICE_URL/mcp"

# 2. Inspect RFC 6750 resource metadata
curl -s "$SERVICE_URL/.well-known/oauth-protected-resource/mcp"
```

Expected JSON output:
```json
{
  "resource": "https://<service-url>/mcp",
  "authorization_servers": ["https://<service-url>/"],
  "scopes_supported": ["openid"],
  "bearer_methods_supported": ["header"]
}
```

### 8.3 Verify Cube Store L2 Columnar Cache
If `enable_cube_store = true`, verify that the Spot VM has initialized and connected to the GCS cache bucket:
```bash
# Check Cube Store container logs via IAP
gcloud compute ssh cube-store \
  --zone="${REGION}-c" \
  --tunnel-through-iap \
  --command="sudo docker logs cube-store.service"
```

Expected output:
```text
INFO [cubestore::mysql] MySQL port open on 0.0.0.0:3306
INFO [cubestore::http] Http Server is listening on 0.0.0.0:3030
INFO [cubestore::metastore::rocks_fs] Downloading remote metastore
```

---

## 9. AI Client Connectivity

### 9.1 Claude Web Integration
1. Open Claude Web ([claude.ai](https://claude.ai)) and navigate to **Settings > Integrations > MCP Servers**.
2. Click **Add Custom MCP Server**.
3. Name: `Cube Semantic Layer`.
4. URL: `https://<your-service-url>/mcp`.
5. Click **Connect**. Claude Web will open a popup window redirecting to Google OAuth.
6. Grant consent with your authorized test user email.
7. Claude Web will complete the handshake and display all 4 available tools.

### 9.2 Claude Code CLI Integration
To connect Claude Code (terminal interface) to your Cloud Run FastMCP service, add the server using the `claude mcp add` command:

```bash
# Option 1: Using npx mcp-remote for automated OAuth token negotiation
claude mcp add cube-semantic-layer -- npx -y mcp-remote https://<your-service-url>/mcp

# Option 2: Direct SSE/HTTP transport (if authenticated via Cloud Run IAM or proxy)
claude mcp add --transport sse cube-semantic-layer https://<your-service-url>/mcp
```

### 9.3 Claude Desktop Local Integration
Add the following snippet to your `claude_desktop_config.json`:
* **macOS:** `~/Library/Application Support/Claude/claude_desktop_config.json`
* **Linux:** `~/.config/Claude/claude_desktop_config.json`
* **Windows:** `%APPDATA%\Claude\claude_desktop_config.json`

```json
{
  "mcpServers": {
    "cube-semantic-layer": {
      "command": "npx",
      "args": [
        "-y",
        "mcp-remote",
        "https://<your-service-url>/mcp"
      ]
    }
  }
}
```

### 9.4 Cursor IDE Integration
In Cursor:
1. Open **Settings > Cursor Settings > Features > MCP**.
2. Click **+ Add New MCP Server**.
3. Configure the server:
   * **Name:** `cube-semantic-layer`
   * **Type:** `command`
   * **Command:** `npx -y mcp-remote https://<your-service-url>/mcp`
4. Save and click the refresh icon to establish connection and verify tools.

### 9.5 Available Semantic Tools

Once connected, your AI assistant has access to the following 4 tools:

1. **`get_metadata()`**: Returns the full catalog of cubes, dimensions, measures, segments, and pre-aggregations formatted in token-efficient Markdown.
2. **`run_semantic_query(measures, dimensions, filters, time_dimensions, order, limit)`**: Executes modeled queries against Cube Core with automatic L1 in-memory caching and L2 Cube Store columnar pre-aggregation routing.
3. **`run_sql_query(query, timezone)`**: Executes raw SQL against Cube's SQL API, supporting window functions, standard aggregates, and BigQuery pushdown.
4. **`explain_sql_query(measures, dimensions, filters)`**: Generates the target BigQuery SQL and cache routing execution plan without querying the warehouse.

---

## 10. Day-2 Operations & Cost Management

### 10.1 Pausing into Zero-Cost Resting State
When the system is not actively being queried, pause all compute resources to drop billing to ~$0.00/month:

1. In [terraform/terraform.tfvars](file:///home/angelo/projects/cube-core-mcp/terraform/terraform.tfvars), set:
   ```hcl
   enable_cloud_run  = false
   enable_cube_store = false
   ```
2. Apply the changes:
   ```bash
   terraform apply -auto-approve -var-file=terraform.tfvars
   ```
   Terraform will destroy the Cloud Run service and delete the Spot VM. BigQuery tables, Artifact Registry images, GCS Parquet chunks, and Secret Manager keys remain preserved within their respective Free Tiers.

### 10.2 Resuming Full Operation
To resume operation:
1. Set `enable_cloud_run = true` and `enable_cube_store = true` in `terraform.tfvars`.
2. Run `terraform apply -auto-approve -var-file=terraform.tfvars`.
3. The Spot VM will boot, reconstruct its RocksDB metastore from GCS in < 2 seconds, and Cloud Run will resume serving requests.

### 10.3 Troubleshooting Runbook Reference
If you encounter runtime errors during deployment or container initialization, refer to the exhaustive runbook in [docs/cloud_run_troubleshooting_and_error_runbook.md](file:///home/angelo/projects/cube-core-mcp/docs/cloud_run_troubleshooting_and_error_runbook.md).
