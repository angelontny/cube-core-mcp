# ------------------------------------------------------------------------------
# Cloud Run Module: Artifact Registry, Workload IAM & Cube Core API Service
# ------------------------------------------------------------------------------

# 1. Artifact Registry Docker Repository
resource "google_artifact_registry_repository" "cube_repo" {
  location      = var.region
  repository_id = var.repository_id
  description   = "Docker repository for Cube Core and FastMCP container images"
  format        = "DOCKER"

  cleanup_policy_dry_run = false

  cleanup_policies {
    id     = "keep-latest-version"
    action = "KEEP"
    most_recent_versions {
      keep_count = 1
    }
  }

  cleanup_policies {
    id     = "delete-untagged"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "3600s" # 1 hour
    }
  }

  cleanup_policies {
    id     = "delete-older-than-1-day"
    action = "DELETE"
    condition {
      tag_state  = "ANY"
      older_than = "86400s" # 1 day
    }
  }

  labels = {
    environment = var.environment
    purpose     = "cube-core-mcp"
  }

  depends_on = [var.services_dependency]
}

# 2. Dedicated Cloud Run Workload Service Account
resource "google_service_account" "cloud_run_cube" {
  account_id   = var.service_account_id
  display_name = "Cloud Run Cube Core API Service Account"
  description  = "Dedicated runtime service account for the Cube Core API service on Cloud Run"
}

# 3. Additive IAM: BigQuery Job User (project level to submit queries)
resource "google_project_iam_member" "cube_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.cloud_run_cube.email}"
}

# 4. Additive IAM: BigQuery Data Viewer (project level to read analytics & thelook_ecommerce)
resource "google_project_iam_member" "cube_bq_data_viewer" {
  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.cloud_run_cube.email}"
}

# 5. Additive IAM: Cloud Logging Writer
resource "google_project_iam_member" "cube_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud_run_cube.email}"
}

# 6. Additive IAM: Storage Object Admin (optional, for Cube Store cache bucket access)
resource "google_storage_bucket_iam_member" "cube_storage_access" {
  count  = var.cube_store_bucket_name != "" ? 1 : 0
  bucket = var.cube_store_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.cloud_run_cube.email}"
}

# 7. Cloud Run v2 Service (Conditional on enabled = true)
locals {
  image_url = var.container_image != "" ? var.container_image : "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.cube_repo.repository_id}/cube-api:latest"
}

resource "google_cloud_run_v2_service" "cube_api" {
  count    = var.enabled ? 1 : 0
  name     = var.service_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.cloud_run_cube.email

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    containers {
      image = local.image_url

      ports {
        container_port = var.container_port
      }

      resources {
        limits = {
          cpu    = var.cpu_limit
          memory = var.memory_limit
        }
      }

      env {
        name  = "CUBEJS_DB_TYPE"
        value = "bigquery"
      }
      env {
        name  = "CUBEJS_DB_BQ_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "CUBEJS_DB_BQ_LOCATION"
        value = var.region
      }
      env {
        name  = "CUBEJS_DEV_MODE"
        value = var.dev_mode ? "true" : "false"
      }
      env {
        name  = "CUBEJS_API_SECRET"
        value = var.cubejs_api_secret
      }
      env {
        name  = "CUBEJS_TELEMETRY"
        value = "false"
      }

      dynamic "env" {
        for_each = var.cube_store_host != "" ? [1] : []
        content {
          name  = "CUBEJS_CUBESTORE_HOST"
          value = var.cube_store_host
        }
      }

      dynamic "env" {
        for_each = var.cube_store_host != "" ? [1] : []
        content {
          name  = "CUBEJS_CUBESTORE_PORT"
          value = var.cube_store_port
        }
      }

      dynamic "env" {
        for_each = var.cube_store_host != "" && var.cube_store_bucket_name != "" ? [1] : []
        content {
          name  = "CUBEJS_DB_EXPORT_BUCKET"
          value = var.cube_store_bucket_name
        }
      }

      dynamic "env" {
        for_each = var.cube_store_host != "" && var.cube_store_bucket_name != "" ? [1] : []
        content {
          name  = "CUBEJS_DB_EXPORT_BUCKET_TYPE"
          value = "gcp"
        }
      }
    }

    vpc_access {
      network_interfaces {
        network    = var.network_id
        subnetwork = var.subnet_id
      }
      egress = "PRIVATE_RANGES_ONLY"
    }
  }

  labels = {
    environment = var.environment
    service     = var.service_name
  }

  depends_on = [
    google_artifact_registry_repository.cube_repo,
    google_project_iam_member.cube_bq_job_user,
    google_project_iam_member.cube_bq_data_viewer,
    google_project_iam_member.cube_logging,
    var.services_dependency
  ]
}

# 8. Unauthenticated Access IAM (Optional, for easy testing in dev)
resource "google_cloud_run_v2_service_iam_member" "public_access" {
  count    = var.enabled && var.allow_unauthenticated ? 1 : 0
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.cube_api[0].name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# 9. Private Authorized Invoker IAM
resource "google_cloud_run_v2_service_iam_member" "invoker_access" {
  for_each = var.enabled ? toset(var.invoker_members) : []
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.cube_api[0].name
  role     = "roles/run.invoker"
  member   = each.value
}
