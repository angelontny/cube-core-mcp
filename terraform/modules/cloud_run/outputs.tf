output "repository_id" {
  description = "The ID of the Artifact Registry repository."
  value       = google_artifact_registry_repository.cube_repo.repository_id
}

output "repository_name" {
  description = "The full resource name of the Artifact Registry repository."
  value       = google_artifact_registry_repository.cube_repo.name
}

output "service_account_email" {
  description = "The email address of the Cloud Run runtime service account."
  value       = google_service_account.cloud_run_cube.email
}

output "service_uri" {
  description = "The URL of the deployed Cloud Run Cube Core API service."
  value       = var.enabled ? google_cloud_run_v2_service.cube_api[0].uri : null
}

output "service_name" {
  description = "The name of the Cloud Run Cube Core API service."
  value       = var.enabled ? google_cloud_run_v2_service.cube_api[0].name : null
}
