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

output "bigquery_transfer_service_account" {
  description = "The email of the BigQuery Data Transfer service account."
  value       = module.bigquery.bq_transfer_service_account_email
}
