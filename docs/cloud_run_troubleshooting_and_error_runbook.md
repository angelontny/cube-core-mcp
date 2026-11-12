# Cloud Run Deployment & Troubleshooting Runbook

This runbook chronicles the configuration, startup errors, root cause analyses, and solutions encountered while packaging and deploying the **Cube Core API** on **Google Cloud Run v2** in Direct BigQuery Mode.

---

## 1. Executive Summary

During Tier 4 deployment, Cube Core was packaged as a container image based on `cubejs/cube:latest` and deployed to Cloud Run using Terraform. We encountered startup probe timeouts (`Error code 9`), container exits (`exit(1)`), state lock contention, and storage accumulation. 

Each issue was diagnosed using container stderr logs retrieved via `gcloud logging read`, cross-referenced with official Cube Core source code and documentation, and systematically resolved.

---

## 2. Issues, Error Messages & Resolutions

### Issue 1: Deprecated `dbType` in Cube.js Configuration

#### Exact Error Output (Revision: `cube-api-00001-shj`)
```text
Cube Error ---------------------------------------
Error: CreateOptions.dbType was removed in v1.7.0. Use driverFactory instead (return a DriverConfig `{ type, ... }`), or set the CUBEJS_DB_TYPE environment variable. See https://github.com/cube-js/cube/blob/master/DEPRECATION.md#dbtype
    at OptsHandler.sanitizeOptions (/cube/node_modules/@cubejs-backend/server-core/src/core/OptsHandler.ts:70:13)
    at new OptsHandler (/cube/node_modules/@cubejs-backend/server-core/src/core/OptsHandler.ts:46:26)
    at new CubejsServerCore (/cube/node_modules/@cubejs-backend/server-core/src/core/server.ts:219:24)
    at CubejsServer.createCoreInstance (/cube/node_modules/@cubejs-backend/server/src/server.ts:85:12)
    at new CubejsServer (/cube/node_modules/@cubejs-backend/server/src/server.ts:80:22)
    at ServerContainer.createServer (/cube/node_modules/@cubejs-backend/server/src/server/container.ts:247:12)
    at ServerContainer.runServerInstance (/cube/node_modules/@cubejs-backend/server/src/server/container.ts:228:25)
    at makeInstance (/cube/node_modules/@cubejs-backend/server/src/server/container.ts:395:33)
    at ServerContainer.start (/cube/node_modules/@cubejs-backend/server/src/server/container.ts:410:20)
    at Server.run (/cube/node_modules/@cubejs-backend/server/src/command/server.ts:25:5)
Container called exit(1).
Default STARTUP TCP probe failed 1 time consecutively for container "cube-api-1" on port 4000.
```

#### Root Cause
In Cube `>= 1.7.0`, the `dbType` key was deprecated and removed from the exported configuration object. `OptsHandler.sanitizeOptions` throws a fatal error if `dbType` is passed in `cube.js`, causing the container to exit with code 1 before binding to port 4000.

#### Resolution
1. Removed `dbType: 'bigquery'` from [src/cube/cube.js](file:///home/angelo/projects/cube-core-mcp/src/cube/cube.js).
2. Ensured database driver selection is handled exclusively via the environment variable in [terraform/modules/cloud_run/main.tf](file:///home/angelo/projects/cube-core-mcp/terraform/modules/cloud_run/main.tf):
   ```hcl
   env {
     name  = "CUBEJS_DB_TYPE"
     value = "bigquery"
   }
   ```

---

### Issue 2: Joi Validation Rejection on `devMode` in `cube.js`

#### Exact Error Output (Revision: `cube-api-00001-zv9`)
```text
Cube Error ---------------------------------------
Error: Invalid cube-server-core options: "devMode" is not allowed
    at validateOptions (/cube/node_modules/@cubejs-backend/server-core/src/core/optionsValidate.ts:167:11)
    at OptsHandler.sanitizeOptions (/cube/node_modules/@cubejs-backend/server-core/src/core/OptsHandler.ts:78:38)
    at new OptsHandler (/cube/node_modules/@cubejs-backend/server-core/src/core/OptsHandler.ts:46:26)
    at new CubejsServerCore (/cube/node_modules/@cubejs-backend/server-core/src/core/server.ts:219:24)
    at CubejsServer.createCoreInstance (/cube/node_modules/@cubejs-backend/server/src/server.ts:85:12)
    at new CubejsServer (/cube/node_modules/@cubejs-backend/server/src/server.ts:80:22)
    at ServerContainer.createServer (/cube/node_modules/@cubejs-backend/server/src/server/container.ts:247:12)
    at ServerContainer.runServerInstance (/cube/node_modules/@cubejs-backend/server/src/server/container.ts:228:25)
    at makeInstance (/cube/node_modules/@cubejs-backend/server/src/server/container.ts:395:33)
    at ServerContainer.start (/cube/node_modules/@cubejs-backend/server/src/server/container.ts:410:20)
Container called exit(1).
Default STARTUP TCP probe failed 1 time consecutively for container "cube-api-1" on port 4000.
```

#### Root Cause
Cube Core utilizes the Joi validation library in `packages/cubejs-server-core/src/core/optionsValidate.ts` to strictly validate configuration properties exported by `cube.js`. `devMode` is **not** a valid property in the Joi configuration schema. Development mode must be passed via environment variables.

#### Resolution
1. Removed `devMode` from [src/cube/cube.js](file:///home/angelo/projects/cube-core-mcp/src/cube/cube.js), leaving only schema-validated options:
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
2. Controlled development mode through Cloud Run container environment variables:
   ```hcl
   env {
     name  = "CUBEJS_DEV_MODE"
     value = var.dev_mode ? "true" : "false"
   }
   ```

---

### Issue 3: BigQuery Regional Dataset Location Mismatch

#### Problem Statement
The BigQuery datasets (`thelook_ecommerce`, `analytics`) reside in `asia-south1`. By default, the Google BigQuery Node.js client assumes datasets reside in the `US` multi-region unless told otherwise. Without specifying the location, queries fail with:
```text
Error: Dataset cube-core-mcp:analytics was not found in location US
```

#### Resolution
Added `CUBEJS_DB_BQ_LOCATION` to the Cloud Run environment in [terraform/modules/cloud_run/main.tf](file:///home/angelo/projects/cube-core-mcp/terraform/modules/cloud_run/main.tf):
```hcl
env {
  name  = "CUBEJS_DB_BQ_LOCATION"
  value = var.region # asia-south1
}
```

---

### Issue 4: Parquet Export Bucket Configuration Scoping

#### Problem Statement
In Stage 1 (Direct BigQuery mode), Cube Store is turned off (`enable_cube_store = false`). However, the Cloud Run module previously passed `CUBEJS_DB_EXPORT_BUCKET` unconditionally. Furthermore, Cube's BigQuery driver expects `CUBEJS_DB_EXPORT_BUCKET_TYPE = "gcp"` whenever an export bucket is declared.

#### Resolution
Scoped the export bucket environment variables to only inject when Cube Store is active (`var.cube_store_host != ""`):
```hcl
dynamic "env" {
  for_each = var.cube_store_host != "" && var.cube_store_bucket_name != "" ? [1] : []
  content {
    name  = "CUBEJS_DB_EXPORT_BUCKET"
    value = var.cube_store_bucket_name
  }
}

dynamic "env" {
  for_each = var.cube_store_host != "" && var.cube_store_bucket_name != "" ? [1] : []
  content {
    name  = "CUBEJS_DB_EXPORT_BUCKET_TYPE"
    value = "gcp"
  }
}
```

---

### Issue 5: Terraform GCS State Lock Contention

#### Exact Error Output
```text
╷
│ Error: Error acquiring the state lock
│
│ Error message: writing "gs://cube-core-mcp-tfstate/terraform/state/default.tflock" failed: googleapi: Error 412: At least one of the pre-conditions you specified did not hold., conditionNotMet
│ Lock Info:
│   ID:        1794503327802019
│   Path:      gs://cube-core-mcp-tfstate/terraform/state/default.tflock
│   Operation: OperationTypeApply
│   Who:       angelo@katana
│   Version:   1.15.9
│   Created:   2026-11-12 17:06:02.879547623 +0000 UTC
╵
```

#### Root Cause
When a previous `terraform apply` timed out or was interrupted while waiting for Cloud Run's health check probe, Terraform's graceful exit handlers did not execute, leaving the lease file `default.tflock` in the remote GCS backend.

#### Resolution
Force-unlocked the state using the Lock ID reported in the error message:
```bash
cd terraform
terraform force-unlock 1794503327802019
```

---

### Issue 6: Artifact Registry Storage Accumulation & Cost Control

#### Problem Statement
Each Cloud Build execution generates a new container image digest. Untagged intermediate blobs and previous image revisions accumulate storage indefinitely in Google Artifact Registry, potentially exceeding the 0.5 GB free tier.

#### Resolution
Configured automated `cleanup_policies` in `google_artifact_registry_repository.cube_repo` ([terraform/modules/cloud_run/main.tf](file:///home/angelo/projects/cube-core-mcp/terraform/modules/cloud_run/main.tf)):
1. **`keep-latest-version`**: `action = "KEEP"`, `keep_count = 1` (guarantees the active version is preserved).
2. **`delete-untagged`**: `action = "DELETE"`, `older_than = "3600s"` (purges unreferenced build layers older than 1 hour).
3. **`delete-older-than-1-day`**: `action = "DELETE"`, `older_than = "86400s"` (prunes historical versions older than 1 day).

---

## 3. Post-Deployment Verification Runbook

Once the configuration was applied, the live Cloud Run endpoint was verified using Service Account impersonation:

### 1. Acquire Identity Token via SA Impersonation
```bash
CUBE_URL="https://cube-api-h3ungosjsa-el.a.run.app"
ID_TOKEN=$(gcloud auth print-identity-token \
  --impersonate-service-account=terraform@cube-core-mcp.iam.gserviceaccount.com \
  --audiences="$CUBE_URL")
```

### 2. Verify Health
```bash
curl -i -H "Authorization: Bearer $ID_TOKEN" "$CUBE_URL/readyz"
```
*Response:* `HTTP/2 200 {"health":"HEALTH"}`

### 3. Verify Metadata Compilation
```bash
curl -s -H "Authorization: Bearer $ID_TOKEN" "$CUBE_URL/cubejs-api/v1/meta"
```
*Result:* Returns all 4 compiled cubes (`orders`, `order_items`, `products`, `users`).

### 4. Execute Live Semantic Queries against BigQuery
```bash
# Query Total Orders, Revenue, and Gross Profit
curl -s -X POST "$CUBE_URL/cubejs-api/v1/load" \
  -H "Authorization: Bearer $ID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "measures": ["orders.count", "orders.total_revenue", "orders.total_profit"]
    }
  }'
```

*Live Verification Output:*
```json
{
  "orders.count": "125079",
  "orders.total_revenue": "10861666.88",
  "orders.total_profit": "5639199.35"
}
```

```bash
# Query Cross-Cube Join (orders joined to users by country)
curl -s -X POST "$CUBE_URL/cubejs-api/v1/load" \
  -H "Authorization: Bearer $ID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "measures": ["orders.total_revenue"],
      "dimensions": ["users.country"],
      "limit": 3
    }
  }'
```

*Live Verification Output:*
```json
[
  {"users.country": "China", "orders.total_revenue": "3707101.90"},
  {"users.country": "United States", "orders.total_revenue": "2378410.27"},
  {"users.country": "Brasil", "orders.total_revenue": "1579146.43"}
]
```
