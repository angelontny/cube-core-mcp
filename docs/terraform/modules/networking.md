# Networking Terraform Module Documentation

The `networking` module constructs the private VPC backbone isolating the Cube Core semantic layer, the Cube Store cache engine, and downstream serverless services without exposing compute nodes to the public internet.

---

## 1. Architectural Purpose

* **Private Perimeter**: Deploys a custom VPC network and regional subnetwork (`10.10.0.0/24`) with `auto_create_subnetworks = false` to prevent default wide-open networking.
* **Direct Private Google Access**: Enables `private_ip_google_access = true` on the subnet so compute instances and Cloud Run Direct VPC Egress reach Google APIs (GCS, BigQuery, Cloud Logging) privately over Google's internal network.
* **Egress-Only Internet via Cloud NAT**: Attaches a regional Cloud Router and Cloud NAT gateway. The private Cube Store VM has zero external public IPs, but can pull public container images (`cubedev/cube-store:v0.36.0`) from Docker Hub during boot.
* **Targeted Ingress Firewall**: Permits incoming TCP traffic on ports `3030` (MySQL wire protocol) and `9999` (internal cluster metastore) strictly from within the internal subnet (`10.10.0.0/24`).
* **Deterministic Static Internal IP**: Pre-allocates static internal IP `10.10.0.10` so that Cloud Run services can target a stable private endpoint.

---

## 2. Directory Layout

```text
terraform/modules/networking/
├── main.tf          # VPC, subnet, Cloud Router, Cloud NAT, firewall, and static internal IP
├── variables.tf     # Input variables (project_id, region, subnet_cidr, cube_store_private_ip, etc.)
└── outputs.tf       # Exported attributes (network ID/name, subnet ID/name, reserved internal IP)
```

---

## 3. Resources Provisioned

| Resource Type | Resource Identifier | Purpose & Configuration |
| :--- | :--- | :--- |
| `google_compute_network` | `vpc` (`cube-network`) | Custom mode VPC network (`auto_create_subnetworks = false`). |
| `google_compute_subnetwork` | `subnet` (`cube-subnet`) | Regional subnet in `asia-south1`. CIDR: `10.10.0.0/24`. `private_ip_google_access = true`. |
| `google_compute_router` | `router` (`cube-router`) | Regional router in `asia-south1` managing Cloud NAT route propagation. |
| `google_compute_router_nat` | `nat` (`cube-nat-gateway`) | Managed NAT gateway providing outbound internet connectivity for private VMs. |
| `google_compute_firewall` | `allow_cube_store_internal` | Allows TCP `3030` and `9999` from `10.10.0.0/24` to instances tagged `cube-store-node`. |
| `google_compute_firewall` | `allow_iap_ssh` | Allows TCP `22` strictly from Google Cloud Identity-Aware Proxy (`35.235.240.0/20`) to instances tagged `cube-store-node`. |
| `google_compute_address` | `cube_store_internal_ip` | Static internal IP reservation (`10.10.0.10`) inside `cube-subnet`. |

---

## 4. Input Variables

| Variable Name | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `project_id` | `string` | *required* | The GCP Project ID where networking resources will be provisioned. |
| `region` | `string` | *required* | The primary GCP region for regional networking (`asia-south1`). |
| `environment` | `string` | `"dev"` | Deployment environment name (`dev`, `staging`, `prod`). |
| `subnet_cidr` | `string` | `"10.10.0.0/24"` | CIDR range for the private Cube subnet. |
| `cube_store_private_ip` | `string` | `"10.10.0.10"` | Static internal IP reserved for the Cube Store cache node. |
| `services_dependency` | `any` | `null` | Explicit dependency on API enablement timers (`time_sleep.wait_for_services`). |

---

## 5. Outputs Exported

| Output Name | Type | Description |
| :--- | :--- | :--- |
| `network_id` | `string` | The resource ID of the custom VPC network. |
| `network_name` | `string` | The name of the custom VPC network (`cube-network`). |
| `subnet_id` | `string` | The resource ID of the regional subnet. |
| `subnet_name` | `string` | The name of the regional subnet (`cube-subnet`). |
| `cube_store_internal_ip` | `string` | The reserved static internal IP address (`10.10.0.10`). |
