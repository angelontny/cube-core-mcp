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

# ------------------------------------------------------------------------------
# Tier 3: Compute Layer (Cube Store Standalone Spot VM)
# ------------------------------------------------------------------------------

module "compute" {
  source = "./modules/compute"

  project_id             = var.project_id
  region                 = var.region
  zone                   = var.zone
  environment            = var.environment
  enabled                = var.enable_cube_store
  machine_type           = var.cube_store_machine_type
  boot_disk_size_gb      = var.cube_store_boot_disk_size_gb
  subnet_id              = module.networking.subnet_id
  cube_store_private_ip  = module.networking.cube_store_internal_ip
  cube_store_sa_email    = module.storage.service_account_email
  cube_store_bucket_name = module.storage.bucket_name
}
