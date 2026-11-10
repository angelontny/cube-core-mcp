output "bucket_name" {
  description = "The name of the Cube Store Parquet cache bucket."
  value       = google_storage_bucket.cube_store_cache.name
}

output "bucket_url" {
  description = "The gs:// URL of the Cube Store Parquet cache bucket."
  value       = google_storage_bucket.cube_store_cache.url
}

output "service_account_email" {
  description = "The email address of the dedicated Cube Store service account."
  value       = google_service_account.cube_store.email
}

output "service_account_name" {
  description = "The fully qualified resource name of the dedicated Cube Store service account."
  value       = google_service_account.cube_store.name
}
