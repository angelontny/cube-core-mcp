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
  cube_store_image       = "${var.region}-docker.pkg.dev/${var.project_id}/cube-repo/cube-store:latest"
}

# ------------------------------------------------------------------------------
# Tier 4: Serving Layer (Cube Core API on Cloud Run with Direct VPC Egress)
# ------------------------------------------------------------------------------

module "cloud_run" {
  source = "./modules/cloud_run"

  project_id           = var.project_id
  reporting_project_id = var.reporting_project_id
  reporting_dataset_id = var.reporting_dataset_id
  region               = var.region
  environment          = var.environment
  enabled              = var.enable_cloud_run
  dev_mode             = var.dev_mode
  invoker_members = distinct(concat(
    ["serviceAccount:terraform@${var.project_id}.iam.gserviceaccount.com"],
    var.invoker_members
  ))
  network_id             = module.networking.network_id
  subnet_id              = module.networking.subnet_id
  cube_store_host        = var.enable_cube_store ? module.networking.cube_store_internal_ip : ""
  cube_store_bucket_name = module.storage.bucket_name
  google_auth_enabled    = var.google_auth_enabled
  fastmcp_public_url     = var.fastmcp_public_url
  fastmcp_transport      = var.fastmcp_transport
  services_dependency    = time_sleep.wait_for_services
}
