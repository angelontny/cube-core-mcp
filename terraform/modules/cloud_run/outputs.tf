# ------------------------------------------------------------------------------
# Cloud Run Module: Outputs (Unified Multi-Container Service)
# ------------------------------------------------------------------------------

output "repository_id" {
  description = "The ID of the Artifact Registry repository."
  value       = google_artifact_registry_repository.cube_repo.repository_id
}

output "repository_name" {
  description = "The full resource name of the Artifact Registry repository."
  value       = google_artifact_registry_repository.cube_repo.name
}

output "service_account_email" {
  description = "The email address of the unified Cloud Run runtime service account."
  value       = google_service_account.cloud_run_cube.email
}

output "service_uri" {
  description = "The public HTTPS endpoint of the unified multi-container Cloud Run service (FastMCP Ingress)."
  value       = var.enabled ? google_cloud_run_v2_service.cube_mcp[0].uri : null
}

output "service_name" {
  description = "The name of the unified multi-container Cloud Run service."
  value       = var.enabled ? google_cloud_run_v2_service.cube_mcp[0].name : null
}

# --- Secret Manager Outputs ---

output "google_client_id_secret_id" {
  description = "Resource name of the Secret Manager secret for Google OAuth Client ID."
  value       = google_secret_manager_secret.google_client_id.secret_id
}

output "google_client_secret_secret_id" {
  description = "Resource name of the Secret Manager secret for Google OAuth Client Secret."
  value       = google_secret_manager_secret.google_client_secret.secret_id
}
