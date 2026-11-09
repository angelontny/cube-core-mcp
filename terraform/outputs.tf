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
