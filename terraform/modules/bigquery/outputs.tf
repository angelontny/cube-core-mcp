output "thelook_ecommerce_dataset_id" {
  description = "Dataset ID of the replicated raw eCommerce data."
  value       = google_bigquery_dataset.thelook_ecommerce.dataset_id
}

output "analytics_dataset_id" {
  description = "Dataset ID of the curated analytics marts."
  value       = google_bigquery_dataset.analytics.dataset_id
}

output "bq_transfer_service_account_email" {
  description = "Email of the service account used for BigQuery Data Transfer."
  value       = google_service_account.bq_transfer.email
}
