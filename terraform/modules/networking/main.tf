# ------------------------------------------------------------------------------
# Networking Module: Custom VPC, Private Subnet, Cloud NAT & Security Firewalls
# ------------------------------------------------------------------------------

# 1. Custom Mode VPC Network
resource "google_compute_network" "vpc" {
  name                    = "cube-network"
  auto_create_subnetworks = false
  description             = "Dedicated VPC network isolating Cube Core semantic services and Cube Store cache"

  depends_on = [var.services_dependency]
}

# 2. Regional Subnetwork with Private Google Access
resource "google_compute_subnetwork" "subnet" {
  name                     = "cube-subnet"
  ip_cidr_range            = var.subnet_cidr
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
  description              = "Private subnet hosting Cube Store Spot VM and Cloud Run Direct VPC Egress"
}

# 3. Regional Cloud Router for Cloud NAT Gateway
resource "google_compute_router" "router" {
  name    = "cube-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

# 4. Regional Cloud NAT Gateway
# Enables egress-only internet connectivity for private Spot VMs to pull public
# container images from Docker Hub without assigning an external public IP.
resource "google_compute_router_nat" "nat" {
  name                               = "cube-nat-gateway"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.subnet.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# 5. Ingress Firewall: Port 3030 (MySQL wire protocol) and Port 9999 (internal metastore)
# Allowed strictly from internal subnet addresses (Cloud Run Direct VPC Egress).
resource "google_compute_firewall" "allow_cube_store_internal" {
  name        = "allow-cube-store-internal"
  network     = google_compute_network.vpc.name
  description = "Allows incoming traffic to Cube Store on ports 3030 and 9999 from the internal subnet"

  allow {
    protocol = "tcp"
    ports    = ["3030", "9999"]
  }

  source_ranges = [var.subnet_cidr]
  target_tags   = ["cube-store-node"]
}

# 6. Static Private IP Reservation for Cube Store Node
# Guarantees that Cloud Run Direct VPC Egress targets a stable internal IP address
resource "google_compute_address" "cube_store_internal_ip" {
  name         = "cube-store-internal-ip"
  subnetwork   = google_compute_subnetwork.subnet.id
  address_type = "INTERNAL"
  address      = var.cube_store_private_ip
  region       = var.region
  description  = "Static internal IP reserved for the Cube Store cache engine instance"
}

# 7. Ingress Firewall: Port 22 (SSH via Identity-Aware Proxy)
# Allows secure administrative SSH access strictly via Google Cloud IAP with zero public IP.
resource "google_compute_firewall" "allow_iap_ssh" {
  name        = "allow-iap-ssh"
  network     = google_compute_network.vpc.name
  description = "Allows incoming SSH traffic on port 22 strictly from Google Identity-Aware Proxy"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # Official Google Cloud IAP netblock
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["cube-store-node"]
}
