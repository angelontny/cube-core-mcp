# Compute Terraform Module Documentation

The `compute` module provisions the ephemeral, high-performance OLAP pre-aggregation caching node running Cube Store in Standalone mode on Google Compute Engine.

---

## 1. Architectural Purpose

* **Sub-Second OLAP Query Cache**: Runs `cubejs/cubestore:latest` in Standalone mode (`CUBESTORE_SERVER_NAME=localhost:9999`), co-locating the metadata Router and columnar Worker processes on a single lean VM for proof-of-concept efficiency.
* **Minimal POC Sizing & Cost Optimization**: Configured as an **`e2-small`** Spot VM (2 shared vCPUs, 2 GB RAM) with a minimal **10 GB** standard persistent boot disk. Operates at approximately **~$0.010 per hour** on Spot capacity.
* **Master On/Off Toggle Switch**: Built with an `enabled` boolean argument (`count = var.enabled ? 1 : 0`). Setting `enable_cube_store = false` in `terraform.tfvars` completely destroys the instance, dropping compute billing to **$0.00** between active coding sessions.
* **Zero Public Attack Surface**: Assigned deterministic private IP `10.10.0.10` with zero external IP addresses. Outbound image pulls traverse Cloud NAT; inbound analytical traffic is gated by VPC firewall tags (`cube-store-node`).
* **Ephemeral Workload Key Lifecycle**: Provisions a dedicated, ephemeral service account key for `cube-store-sa` (`google_service_account_key.cube_store`) that is written to `/etc/cube-store/sa-key.json` via `cloud-init` and destroyed whenever `enable_cube_store = false`.
* **Supervised Systemd Execution**: Runs as a managed `systemd` service via `cloud-init` rather than a raw detached container. For architectural justification, see [adr_why_systemd_supervises_cube_store_on_cos.md](file:///home/angelo/projects/cube-core-mcp/docs/adr_why_systemd_supervises_cube_store_on_cos.md).

---

## 2. Directory Layout

```text
terraform/modules/compute/
├── main.tf          # Compute Engine instance definition, Spot scheduling, and startup script
├── variables.tf     # Input variables (sizing, toggle switch, disk size, image tag, network IP)
└── outputs.tf       # Exported attributes (instance name, instance ID, assigned internal IP)
```

---

## 3. Resources Provisioned

| Resource Type | Resource Identifier | Purpose & Configuration |
| :--- | :--- | :--- |
| `google_service_account_key` | `cube_store[0]` | Ephemeral JSON credential key generated for `cube-store-sa`. Automatically provisioned and destroyed with the VM lifecycle (`count = var.enabled ? 1 : 0`). |
| `google_compute_instance` | `cube_store[0]` | Single Spot VM instance running Container-Optimized OS (COS) in `asia-south1-c`. Machine type: `e2-small`. Boot disk: 10 GB `pd-standard`. Network IP: `10.10.0.10`. Managed systemd unit launches `cubejs/cubestore:latest` with `restart = always`. |

---

## 4. Input Variables

### Module-Level Variables (`terraform/modules/compute/variables.tf`)

| Variable Name | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `project_id` | `string` | *required* | The GCP Project ID where compute resources will be provisioned. |
| `region` | `string` | *required* | The primary GCP region (`asia-south1`). |
| `zone` | `string` | *required* | The GCP zone for the compute instance (`asia-south1-c`). |
| `environment` | `string` | `"dev"` | Deployment environment name (`dev`, `staging`, `prod`). |
| `enabled` | `bool` | `true` | Master toggle to turn the Cube Store Spot VM on or off. |
| `subnet_id` | `string` | *required* | Resource ID of the private subnet where the VM will reside. |
| `cube_store_private_ip` | `string` | *required* | Static internal IP address reserved for the node (`10.10.0.10`). |
| `cube_store_sa_email` | `string` | *required* | Email of the dedicated service account (`cube-store-sa@...`). |
| `cube_store_bucket_name` | `string` | *required* | Name of the GCS bucket storing Cube Store Parquet files. |
| `machine_type` | `string` | `"e2-small"` | Compute Engine machine type for the Spot VM. |
| `boot_disk_size_gb` | `number` | `10` | Size of the boot disk in GB (minimum 10 GB for COS). |
| `cube_store_image` | `string` | `"cubejs/cubestore:latest"` | Docker container image repository and tag. |

### Root-Level Variables (`terraform/variables.tf` & `terraform.tfvars`)

Instance hardware sizing and operational toggles are surfaced at the project root for environment-level tuning:

| Root Variable Name | Module Parameter | Default | Validation / Constraint |
| :--- | :--- | :--- | :--- |
| `enable_cube_store` | `enabled` | `true` | Boolean toggle (`count = var.enabled ? 1 : 0`). |
| `cube_store_machine_type` | `machine_type` | `"e2-small"` | Any valid GCE machine type (e.g., `e2-small`, `e2-medium`, `e2-standard-4`). |
| `cube_store_boot_disk_size_gb` | `boot_disk_size_gb` | `10` | Minimum `10` GB enforced via Terraform validation rule. |

---

## 5. Outputs Exported

| Output Name | Type | Description |
| :--- | :--- | :--- |
| `instance_name` | `string` | Name of the deployed Compute Engine instance (`cube-store` or `null` if disabled). |
| `instance_id` | `string` | Server-assigned unique identifier of the instance. |
| `internal_ip` | `string` | Assigned internal IP address of the instance (`10.10.0.10`). |

---

## 6. Operational Runbook: Managing the On/Off Switch

### Option A: Via Terraform (Recommended for Extended Inactivity)
When you are done coding for the day and want to drop compute costs to **$0.00**:
1. In `terraform/terraform.tfvars`, set:
   ```hcl
   enable_cube_store = false
   ```
2. Run:
   ```bash
   terraform apply -var-file=terraform.tfvars
   ```
   *Terraform will destroy the Spot VM and its 10 GB boot disk. All Parquet data remains safe in GCS.*
3. When you resume work, set `enable_cube_store = true` and re-apply. The VM recreates in ~25 seconds and re-attaches to the GCS bucket.

### Option B: Via Google Cloud CLI (Instant Pause / Resume)
If you just want to pause CPU/RAM billing between coding breaks without modifying Terraform:
```bash
# Stop instance (CPU and RAM billing stops immediately):
gcloud compute instances stop cube-store --zone=asia-south1-c

# Start instance when ready to test:
gcloud compute instances start cube-store --zone=asia-south1-c
```

---

## 7. Diagnosing the Instance via SSH & Identity-Aware Proxy (IAP)

Because the VM has no external public IP, SSH access is securely routed through Google Cloud IAP without exposing port 22 to the public internet. `gcloud compute ssh` automatically generates and manages ephemeral SSH key pairs without manual configuration.

### Step 1: Apply the Terraform Configuration
Applies the `allow-iap-ssh` firewall rule (TCP port 22 from `35.235.240.0/20`):
```bash
terraform apply -var-file=terraform.tfvars
```

### Step 2: Grant IAP Permissions to the Terraform Service Account (One-Time)
```bash
gcloud projects add-iam-policy-binding cube-core-mcp \
  --member="serviceAccount:terraform@cube-core-mcp.iam.gserviceaccount.com" \
  --role="roles/iap.tunnelResourceAccessor"
```

### Step 3: Connect via IAP Tunnel from Cloud Shell or Workstation
`gcloud` will automatically generate an SSH key pair and inject it into the VM metadata:
```bash
gcloud compute ssh cube-store \
  --zone=asia-south1-c \
  --tunnel-through-iap \
  --impersonate-service-account="terraform@cube-core-mcp.iam.gserviceaccount.com"
```

### Step 4: (Optional) Local Workstation `~/.ssh/config` Setup
To connect with plain `ssh cube-store` or use **VS Code / Cursor Remote - SSH**:
Add the following block to your local `~/.ssh/config`:
```text
Host cube-store
    HostName cube-store
    IdentityFile ~/.ssh/google_compute_engine
    ProxyCommand gcloud compute start-iap-tunnel %h %p --listen-on-stdin --project=cube-core-mcp --zone=asia-south1-c --impersonate-service-account=terraform@cube-core-mcp.iam.gserviceaccount.com --verbosity=warning
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```
Then run:
```bash
ssh cube-store
```

### Step 5: Run Diagnostic Commands on the VM
```bash
# Check Docker daemon and running containers:
docker ps -a

# View systemd logs for the managed cube-store service:
journalctl -u cube-store.service -f

# Inspect container logs directly:
docker logs --tail 50 cube-store
```

---

## 8. Service Account Key Lifecycle & Cube Store GCS Authentication

### Why Cube Store Requires an Explicit Service Account Key

Cube Store is implemented in Rust. Its Google Cloud Storage remote filesystem driver is backed by the third-party Rust crate `cloud-storage-rs` (v0.7.1). 

Unlike standard Google SDKs (Node.js, Python, Go) which query the Compute Engine instance metadata server (`http://metadata.google.internal/computeMetadata/v1/`) for Application Default Credentials (ADC), `cloud-storage-rs` **does not support metadata server token discovery**.

When `cubestored` initializes the GCS backend, `cloud-storage-rs` executes:
```rust
// cloud-storage-0.7.1/src/resources/service_account.rs:35:14
SERVICE_ACCOUNT(_JSON) or GOOGLE_APPLICATION_CREDENTIALS(_JSON) environment parameter required: NotPresent
```
If an explicit JSON key file path is not provided via `GOOGLE_APPLICATION_CREDENTIALS` or `CUBESTORE_GCP_KEY_FILE`, the binary panics immediately with exit code `101`.

### How We Handle Key Security Ephemerally in Terraform

To avoid storing static JSON keys in git or long-lived developer environments, Terraform automates the key lifecycle tied directly to the VM:

1. **Lifecycle Binding (`count = var.enabled ? 1 : 0`)**:
   Terraform provisions `google_service_account_key.cube_store[0]` strictly when `enable_cube_store = true`. Setting `enable_cube_store = false` automatically destroys both the VM and the key in GCP.
2. **Host Injection via `cloud-init`**:
   The key's `private_key` attribute (base64-encoded) is injected into instance metadata and written to the host at `/etc/cube-store/sa-key.json` with strict `0600` permissions (readable solely by `root`).
3. **Container Mount & Environment Wiring**:
   The file is mounted read-only into the Docker container (`-v /etc/cube-store/sa-key.json:/etc/cube-store/sa-key.json:ro`) and surfaced to `cubestored` via `-e GOOGLE_APPLICATION_CREDENTIALS=/etc/cube-store/sa-key.json`.

### IAM Prerequisite: `roles/iam.serviceAccountKeyAdmin`

Because creating service account keys is separated from managing service accounts in Google Cloud, the Terraform deployment identity requires:
* **Role**: `roles/iam.serviceAccountKeyAdmin`
* **Permission**: `iam.serviceAccountKeys.create`
* **Grant Command**:
  ```bash
  gcloud projects add-iam-policy-binding cube-core-mcp \
    --member="serviceAccount:terraform@cube-core-mcp.iam.gserviceaccount.com" \
    --role="roles/iam.serviceAccountKeyAdmin"
  ```
