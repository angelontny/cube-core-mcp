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
  value       = google_bigquery_dataset.thelook_ecommerce.dataset_id
}

output "bigquery_analytics_dataset_id" {
  description = "The BigQuery dataset ID for dbt analytics marts."
  value       = google_bigquery_dataset.analytics.dataset_id
}

output "bigquery_transfer_config_id" {
  description = "The resource name of the cross-region dataset transfer config."
  value       = google_bigquery_data_transfer_config.thelook_cross_region_copy.name
}
