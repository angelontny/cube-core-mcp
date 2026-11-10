# ------------------------------------------------------------------------------
# Root Module: BigQuery Data Warehouse & Data Transfer
# ------------------------------------------------------------------------------

module "bigquery" {
  source = "./modules/bigquery"

  project_id          = var.project_id
  region              = var.region
  environment         = var.environment
  services_dependency = time_sleep.wait_for_services
}

# ------------------------------------------------------------------------------
# Tier 1: Storage Layer (Cube Store Parquet Cache & Workload IAM)
# ------------------------------------------------------------------------------

module "storage" {
  source = "./modules/storage"

  project_id          = var.project_id
  region              = var.region
  environment         = var.environment
  services_dependency = time_sleep.wait_for_services
}

# ------------------------------------------------------------------------------
# Tier 2: Private Networking Layer (VPC, Subnet, Cloud NAT & Internal Firewall)
# ------------------------------------------------------------------------------

module "networking" {
  source = "./modules/networking"

  project_id          = var.project_id
  region              = var.region
  environment         = var.environment
  services_dependency = time_sleep.wait_for_services
}
