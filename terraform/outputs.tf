output "project_id" {
  description = "The GCP Project ID."
  value       = var.project_id
}

output "enabled_services" {
  description = "List of services enabled by Terraform."
  value       = keys(google_project_service.enabled_services)
}

output "terraform_state_bucket" {
  description = "The GCS bucket name for remote Terraform state."
  value       = google_storage_bucket.terraform_state.name
}

output "bigquery_raw_dataset_id" {
  description = "The BigQuery dataset ID for raw replicated data."
  value       = module.bigquery.thelook_ecommerce_dataset_id
}

output "bigquery_analytics_dataset_id" {
  description = "The BigQuery dataset ID for dbt analytics marts."
  value       = module.bigquery.analytics_dataset_id
}

output "bigquery_transfer_config_id" {
  description = "The resource name of the cross-region dataset transfer config."
  value       = module.bigquery.transfer_config_id
}

output "bigquery_transfer_service_account" {
  description = "The email of the BigQuery Data Transfer service account."
  value       = module.bigquery.bq_transfer_service_account_email
}

output "cube_store_cache_bucket" {
  description = "The GCS bucket name for Cube Store Parquet cache files."
  value       = module.storage.bucket_name
}

output "cube_store_service_account_email" {
  description = "The email address of the dedicated Cube Store service account."
  value       = module.storage.service_account_email
}

output "vpc_network_name" {
  description = "The name of the custom VPC network."
  value       = module.networking.network_name
}

output "cube_subnet_name" {
  description = "The name of the private Cube subnet."
  value       = module.networking.subnet_name
}

output "cube_store_internal_ip" {
  description = "The reserved internal IP address for the Cube Store cache node."
  value       = module.networking.cube_store_internal_ip
}
