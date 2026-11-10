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
