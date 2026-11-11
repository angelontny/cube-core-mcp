# Google Cloud CLI (`gcloud`) Operational & Health Check Runbook

This runbook provides copy-pasteable `gcloud` commands to inspect, monitor, debug, and verify the health of all deployed GCP components across BigQuery, GCS Storage, VPC Networking, Compute Engine, and Cloud Run.

---

## 1. Project & Authentication Pre-Flight

```bash
# Verify your active account and quota project
gcloud config get-value account
gcloud config get-value project

# Set target project explicitly if needed
gcloud config set project cube-core-mcp

# Verify billing status (must return 'True')
gcloud billing projects describe cube-core-mcp --format="value(billingEnabled)"

# Check enabled GCP APIs
gcloud services list --enabled --filter="name:(bigquery OR compute OR run OR storage OR logging OR vpcaccess)"
```

---

## 2. BigQuery & Data Transfer Service

```bash
# List datasets in the project
gcloud alpha bq datasets list --project=cube-core-mcp

# List replicated tables in the raw eCommerce dataset
bq ls --project_id=cube-core-mcp thelook_ecommerce

# List tables and views in the dbt analytics marts dataset
bq ls --project_id=cube-core-mcp analytics

# Check the status of the Data Transfer configuration
bq ls --transfer_config --transfer_location=asia-south1 --project_id=cube-core-mcp

# Inspect the latest run logs for the BigQuery Data Transfer job
TRANSFER_CONFIG_ID=$(bq ls --transfer_config --transfer_location=asia-south1 --format=json | jq -r '.[0].name')
bq ls --transfer_run --transfer_location=asia-south1 "${TRANSFER_CONFIG_ID}"
```

---

## 3. Storage Layer (Cube Store GCS Cache)

```bash
# Verify the cache bucket exists in asia-south1 with uniform access
gcloud storage buckets describe gs://cube-core-mcp-cube-store-cache \
  --format="table(name,location,storageClass,uniformBucketLevelAccess.enabled,publicAccessPrevention)"

# List Parquet pre-aggregation files cached in the bucket
gcloud storage ls --recursive gs://cube-core-mcp-cube-store-cache/

# Verify IAM permissions on the bucket (ensure cube-store-sa has objectAdmin)
gcloud storage buckets get-iam-policy gs://cube-core-mcp-cube-store-cache
```

---

## 4. Private Networking & Firewalls

```bash
# Inspect the custom VPC network
gcloud compute networks describe cube-network \
  --format="table(name,autoCreateSubnetworks,subnetworks[0])"

# Inspect the regional subnet and verify Private Google Access is enabled
gcloud compute networks subnets describe cube-subnet \
  --region=asia-south1 \
  --format="table(name,ipCidrRange,privateIpGoogleAccess)"

# Verify the reserved static internal IP for Cube Store
gcloud compute addresses describe cube-store-internal-ip \
  --region=asia-south1 \
  --format="table(name,address,status,subnetwork)"

# Check Cloud NAT Gateway status (enables private VMs to pull Docker images)
gcloud compute routers nats describe cube-nat-gateway \
  --router=cube-router \
  --region=asia-south1

# Verify the ingress firewall rule allowing ports 3030 and 9999
gcloud compute firewall-rules describe allow-cube-store-internal \
  --format="table(name,network,allowed,sourceRanges,targetTags)"

# Verify the ingress firewall rule for Identity-Aware Proxy SSH tunneling (port 22)
gcloud compute firewall-rules describe allow-iap-ssh \
  --format="table(name,network,allowed,sourceRanges,targetTags)"
```

---

## 5. Compute Engine Spot VM (Cube Store Cache Node)

```bash
# Check instance status and verify private IP binding (10.10.0.10)
gcloud compute instances describe cube-store \
  --zone=asia-south1-c \
  --format="table(name,status,machineType.basename(),scheduling.provisioningModel,networkInterfaces[0].networkIP)"

# Inspect boot logs / serial port output to check container startup status
gcloud compute instances get-serial-port-output cube-store \
  --zone=asia-south1-c | tail -n 50

# Check specifically for Cube Store container startup messages
gcloud compute instances get-serial-port-output cube-store \
  --zone=asia-south1-c | grep -E "cube-store|docker run|exit status"

# Stream live serial port logs from the VM
gcloud compute instances tail-serial-port-output cube-store --zone=asia-south1-c

# SSH into the private instance securely via Identity-Aware Proxy (zero public IP required)
gcloud compute ssh cube-store --zone=asia-south1-c --tunnel-through-iap

# SSH using Terraform Service Account impersonation:
gcloud compute ssh cube-store --zone=asia-south1-c --tunnel-through-iap \
  --impersonate-service-account="terraform@cube-core-mcp.iam.gserviceaccount.com"

# Grant IAP Tunnel User role to the Terraform Service Account (run once if needed):
# gcloud projects add-iam-policy-binding cube-core-mcp \
#   --member="serviceAccount:terraform@cube-core-mcp.iam.gserviceaccount.com" \
#   --role="roles/iap.tunnelResourceAccessor"

# Forward Cube Store MySQL port 3030 directly to localhost:3030 on your workstation:
# gcloud compute start-iap-tunnel cube-store 3030 --local-host-port=localhost:3030 --zone=asia-south1-c \
#   --impersonate-service-account="terraform@cube-core-mcp.iam.gserviceaccount.com"

# Once inside the VM, diagnose the container and systemd service:
# docker ps -a
# journalctl -u cube-store.service -f
# docker logs --tail 50 cube-store

# Instant Pause / Resume Controls (Stops CPU/RAM billing without destroying state)
gcloud compute instances stop cube-store --zone=asia-south1-c
gcloud compute instances start cube-store --zone=asia-south1-c
```

---

## 6. Cloud Run Services (Cube API & Refresh Worker)

```bash
# List all Cloud Run services in the region
gcloud run services list --region=asia-south1

# Describe the Cube API service status, URL, and VPC connectivity
gcloud run services describe cube-api \
  --region=asia-south1 \
  --format="table(status.url,status.conditions[0].type,status.conditions[0].status,spec.template.spec.vpcAccess)"

# Describe the Refresh Worker service status
gcloud run services describe cube-refresh-worker \
  --region=asia-south1 \
  --format="table(status.url,status.conditions[0].type,status.conditions[0].status)"

# Tail live application logs for Cube API
gcloud logging tail 'resource.type="cloud_run_revision" AND resource.labels.service_name="cube-api"'

# Tail live application logs for the Refresh Worker
gcloud logging tail 'resource.type="cloud_run_revision" AND resource.labels.service_name="cube-refresh-worker"'
```

---

## 7. Cloud Logging: System-Wide Diagnostics

```bash
# Query the last 20 warning or error logs across the entire project
gcloud logging read "severity>=WARNING" --limit=20 --format="table(timestamp,severity,resource.type,textPayload)"

# Check audit logs for IAM or permission denial errors (HTTP 403)
gcloud logging read 'protoPayload.status.code=7 OR protoPayload.status.message:"PERMISSION_DENIED"' \
  --limit=10 \
  --format="table(timestamp,protoPayload.authenticationInfo.principalEmail,protoPayload.methodName,protoPayload.status.message)"
```
