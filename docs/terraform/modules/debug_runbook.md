# Active Infrastructure Debug & Verification Runbook

This runbook provides actionable, copy-pasteable `gcloud` and `bq` commands specifically tailored to debug, inspect, and verify the **three active modules** deployed so far:
1. **BigQuery Module (`modules/bigquery/`)**
2. **Storage Module (`modules/storage/`)**
3. **Networking Module (`modules/networking/`)**
4. **Compute Module (`modules/compute/`)**

---

## 1. BigQuery Module Debug Commands

### Check Dataset Existence & Configuration
```bash
# Verify both regional datasets exist in asia-south1
bq show --format=prettyjson cube-core-mcp:thelook_ecommerce | jq '{datasetId: .datasetReference.datasetId, location: .location}'
bq show --format=prettyjson cube-core-mcp:analytics | jq '{datasetId: .datasetReference.datasetId, location: .location}'
```

### Inspect Replicated Raw Tables & Row Counts
```bash
# List all 7 raw eCommerce tables
bq ls --project_id=cube-core-mcp thelook_ecommerce

# Verify data exists inside a table (e.g., orders table)
bq query --use_legacy_sql=false \
  'SELECT count(*) as total_orders FROM `cube-core-mcp.thelook_ecommerce.orders`'
```

### Debug Data Transfer Service (DTS)
```bash
# List transfer configurations in asia-south1
bq ls --transfer_config --transfer_location=asia-south1 --project_id=cube-core-mcp

# If a transfer is stuck or failed, get the latest run status and error message:
CONFIG_NAME=$(bq ls --transfer_config --transfer_location=asia-south1 --format=json | jq -r '.[0].name')
bq ls --transfer_run --transfer_location=asia-south1 "${CONFIG_NAME}" --format=prettyjson | jq '.[0] | {state: .state, errorStatus: .errorStatus, runTime: .runTime}'
```

---

## 2. Storage Module Debug Commands

### Verify Cache Bucket Properties & Security
```bash
# Check bucket location (must be ASIA-SOUTH1), storage class, and uniform access
gcloud storage buckets describe gs://cube-core-mcp-cube-store-cache \
  --format="table(name,location,storageClass,uniformBucketLevelAccess.enabled,publicAccessPrevention)"
```

### Debug IAM Permissions on the Bucket
```bash
# Verify cube-store-sa has roles/storage.objectAdmin
gcloud storage buckets get-iam-policy gs://cube-core-mcp-cube-store-cache \
  --filter="bindings.members:cube-store-sa@cube-core-mcp.iam.gserviceaccount.com" \
  --format="table(bindings.role,bindings.members)"
```

### Inspect Stored Parquet Files
```bash
# List files currently cached by Cube Store
gcloud storage ls --recursive gs://cube-core-mcp-cube-store-cache/

# Test write permissions manually using the service account identity (if impersonating)
echo "test" | gcloud storage cp - gs://cube-core-mcp-cube-store-cache/health_check.txt
gcloud storage rm gs://cube-core-mcp-cube-store-cache/health_check.txt
```

---

## 3. Networking Module Debug Commands

### Verify VPC & Subnet Status
```bash
# Check the custom VPC network
gcloud compute networks describe cube-network \
  --format="table(name,autoCreateSubnetworks,subnetworks[0])"

# Verify the regional subnet has Private Google Access enabled
gcloud compute networks subnets describe cube-subnet \
  --region=asia-south1 \
  --format="table(name,ipCidrRange,privateIpGoogleAccess,gatewayAddress)"
```

### Inspect the Reserved Static Internal IP
```bash
# Must show '10.10.0.10' with status 'RESERVED' or 'IN_USE'
gcloud compute addresses describe cube-store-internal-ip \
  --region=asia-south1 \
  --format="table(name,address,status,subnetwork.basename(),users[0].basename())"
```

### Debug Cloud NAT & Outbound Connectivity
```bash
# Check Cloud NAT gateway status (allows private VMs to reach Docker Hub)
gcloud compute routers nats describe cube-nat-gateway \
  --router=cube-router \
  --region=asia-south1 \
  --format="table(name,natIpAllocateOption,subnetworks[0].name.basename())"
```

### Verify VPC Firewall Rules
```bash
# Verify internal ingress rule for ports 3030 and 9999
gcloud compute firewall-rules describe allow-cube-store-internal \
  --format="table(name,network.basename(),allowed[0].ports,sourceRanges,targetTags)"
```

---

## 4. Compute Module (Cube Store Spot VM) Debug Commands

### Check Instance Lifecycle & Internal IP
```bash
# Check VM status (RUNNING, STOPPED, or TERMINATED) and confirm internal IP
gcloud compute instances describe cube-store \
  --zone=asia-south1-c \
  --format="table(name,status,machineType.basename(),scheduling.provisioningModel,networkInterfaces[0].networkIP)"
```

### Inspect Boot & Docker Startup Logs
```bash
# Check the last 60 lines of serial console output
gcloud compute instances get-serial-port-output cube-store \
  --zone=asia-south1-c | tail -n 60

# Check specifically for Docker container pull and startup status
gcloud compute instances get-serial-port-output cube-store \
  --zone=asia-south1-c | grep -E "cube-store|docker run|exit status|pulling|digest"

# Stream live console logs from the VM
gcloud compute instances tail-serial-port-output cube-store --zone=asia-south1-c
```

### Test Port 3030 Accessibility from Within the VPC
```bash
# Check Cloud Logging for firewall drop events on port 3030
gcloud logging read 'resource.type="gce_subnetwork" AND jsonPayload.connection.dest_port=3030' \
  --limit=10 \
  --format="table(timestamp,jsonPayload.disposition,jsonPayload.connection.src_ip,jsonPayload.connection.dest_ip)"
```

### Instant CLI On/Off Controls
```bash
# Stop VM (CPU and RAM billing stops immediately):
gcloud compute instances stop cube-store --zone=asia-south1-c

# Start VM (Boots up and runs Cube Store container via Cloud NAT):
gcloud compute instances start cube-store --zone=asia-south1-c
```
