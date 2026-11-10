# ------------------------------------------------------------------------------
# Storage Module: Cube Store Pre-Aggregation Parquet Cache & Workload IAM
# ------------------------------------------------------------------------------

# 1. Cube Store Parquet Cache Bucket
resource "google_storage_bucket" "cube_store_cache" {
  name     = "${var.project_id}-cube-store-cache"
  location = var.region

  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Prevent accidental bucket deletion with cached rollups in production; allow in dev
  force_destroy = var.environment == "dev" ? true : false

  versioning {
    enabled = false
  }

  labels = {
    environment = var.environment
    purpose     = "cube-store-cache"
  }

  depends_on = [var.services_dependency]
}

# 2. Dedicated Workload Service Account for Cube Store
resource "google_service_account" "cube_store" {
  account_id   = "cube-store-sa"
  display_name = "Cube Store Cache Engine Service Account"
  description  = "Dedicated identity used by Cube Store compute nodes for Parquet storage access"
}

# 3. Additive IAM: Object Admin strictly on the Cube Store cache bucket
resource "google_storage_bucket_iam_member" "cube_store_object_admin" {
  bucket = google_storage_bucket.cube_store_cache.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.cube_store.email}"
}

# 4. Additive IAM: Cloud Logging writer for container logs
resource "google_project_iam_member" "cube_store_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cube_store.email}"
}
