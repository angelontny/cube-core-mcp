# ADR-0005: Artifact Registry Image Mirroring vs. Cloud NAT Gateway

* **Status:** Accepted
* **Date:** 2026-11-14 (Updated 2026-11-15)
* **Deciders:** Cloud Platform Architecture & FinOps Team
* **Consulted:** Security, Network Operations
* **Informed:** All Engineering Teams

---

## 1. Context and Problem Statement

The Cube Store cache node runs on a Compute Engine Spot VM in a custom private VPC (`cube-subnet`, `10.10.0.0/24`). To maintain a minimal security footprint, the VM has **zero external public IP addresses**.

During cold boots, the Container-Optimized OS (COS) host must download the `cubedev/cube-store` Docker container image. Originally, to pull this public image from Docker Hub, a Google Cloud Router and Cloud NAT Gateway were provisioned on the subnet.

However, Google Cloud NAT incurs a fixed baseline fee of **~$32.40 per month** ($0.045 per hour per gateway), regardless of whether traffic is flowing. In a proof-of-concept or staging environment designed to scale to zero, this static charge accounted for over 90% of the entire infrastructure baseline cost.

---

## 2. Decision Drivers

* **Zero-Cost Resting State:** When infrastructure is idle, fixed hourly charges must approach $0.00/month.
* **Network Security / Air-Gap:** Instances in `cube-subnet` should not have arbitrary outbound internet egress paths.
* **Deterministic Deployment:** Deployments should not depend on Docker Hub rate limits or external registry downtime.

---

## 3. Considered Options

* **Option 1: Retain Cloud NAT Gateway on `cube-subnet`**
* **Option 2: Assign an Ephemeral Public IP to the Spot VM with Strict Outbound Firewall Rules**
* **Option 3: Mirror the Upstream Container into Google Artifact Registry and pull via Private Google Access (Selected)**

---

## 4. Evaluation and Decision Outcome

**Chosen Option:** **Option 3: Mirror the Upstream Container into Google Artifact Registry and pull via Private Google Access**.

### Architectural Mechanics
1. **Private Google Access:** The regional subnetwork (`cube-subnet`) has `private_ip_google_access = true`. Compute Engine instances without external public IPs can resolve and access all Google APIs and services—including **Google Artifact Registry** (`*.pkg.dev`) and **Google Cloud Storage**—over Google's internal private network backbone.
2. **Private Container Mirror:** The upstream `cubejs/cubestore:latest` image is mirrored into the project's regional Docker repository in Artifact Registry:
   `${REGION}-docker.pkg.dev/${PROJECT_ID}/cube-repo/cube-store:latest`
3. **Decommissioning Cloud NAT:** `google_compute_router_nat` and `google_compute_router` were completely removed from [terraform/modules/networking/main.tf](file:///home/angelo/projects/cube-core-mcp/terraform/modules/networking/main.tf).
4. **Cloud-Init Credential Helper:** In the VM's `cloud-init` systemd service unit:
   ```bash
   ExecStartPre=/usr/bin/docker-credential-gcr configure-docker --registries=${var.region}-docker.pkg.dev
   ExecStartPre=/usr/bin/docker pull ${var.cube_store_image}
   ```
   The VM uses its attached Service Account (`cube-store-sa`) to authenticate directly to Artifact Registry.

### Financial and Operational Comparison

| Evaluation Metric | Option 1: Cloud NAT Gateway | Option 2: Public IP on VM | Option 3: Artifact Registry Mirroring (Chosen) |
| :--- | :--- | :--- | :--- |
| **Fixed Hourly Baseline Cost** | **$32.40 / month** ($0.045/hr) | $3.60 / month ($0.005/hr IPv4) | **$0.00 / month** (Free tier storage / PGA) |
| **Resting State Cost** | $32.40 / month (continuous) | $0.00 (when VM destroyed) | **$0.00 / month (true zero-cost)** |
| **VPC Outbound Perimeter** | Open to all internet via NAT | Open to internet | **Strictly internal (zero outbound internet)** |
| **Supply Chain Reliability** | Vulnerable to Docker Hub limits | Vulnerable to Docker Hub limits | **Hermetic (hosted within GCP project)** |

---

## 5. Consequences

### Positive Consequences
* **Immediate Cost Reduction:** Eliminates ~$32.40/month in mandatory baseline fees.
* **Stronger Security Posture:** The private subnet is completely isolated from the public internet. No container on the Spot VM can initiate arbitrary outbound connections to external hosts.
* **Immunity to Docker Hub Rate Limiting:** Cold boot image pulls are fast and internal to the GCP regional data center network.

### Negative Consequences / Risks
* Upstream updates to `cubedev/cube-store` must be periodically re-mirrored into Artifact Registry (automated via Cloud Build `src/cube_store/cloudbuild.yaml`).

---

## 6. Related Documents
* [ADR-0001: Why Cube Store Cannot Run on Cloud Run](file:///home/angelo/projects/cube-core-mcp/docs/architecture/adrs/0001_why_cube_store_cannot_run_on_cloud_run.md)
* [ADR-0002: Why systemd Supervises Cube Store on COS](file:///home/angelo/projects/cube-core-mcp/docs/architecture/adrs/0002_why_systemd_supervises_cube_store_on_cos.md)
* [terraform/modules/networking.md](file:///home/angelo/projects/cube-core-mcp/docs/terraform/modules/networking.md)
