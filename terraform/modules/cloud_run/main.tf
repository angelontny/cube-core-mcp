# ------------------------------------------------------------------------------
# Cloud Run Module: Multi-Container Service (FastMCP Ingress + Cube Core Sidecar)
# ------------------------------------------------------------------------------

# 1. Artifact Registry Docker Repository (Hosts both cube-api and fastmcp-api)
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

# 2. Unified Runtime Service Account
resource "google_service_account" "cloud_run_cube" {
  account_id   = var.service_account_id
  display_name = "Cloud Run Cube & FastMCP Workload Service Account"
  description  = "Unified runtime service account for the multi-container Cube & FastMCP service on Cloud Run"
}

# 3. Workload Self-Signing: Token Creator (permits signBlob for GCS export)
resource "google_service_account_iam_member" "cloud_run_cube_token_creator" {
  service_account_id = google_service_account.cloud_run_cube.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.cloud_run_cube.email}"
}

# 4. Additive IAM: BigQuery Job User (project level to submit queries)
resource "google_project_iam_member" "cube_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.cloud_run_cube.email}"
}

# 5. Additive IAM: BigQuery Data Editor (project level to read, write, and export pre-aggregations)
resource "google_project_iam_member" "cube_bq_data_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.cloud_run_cube.email}"
}

# 6. Additive IAM: Cloud Logging Writer
resource "google_project_iam_member" "cube_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud_run_cube.email}"
}

# 7. Additive IAM: Storage Object Admin (for Cube Store cache bucket access)
resource "google_storage_bucket_iam_member" "cube_storage_access" {
  count  = var.cube_store_bucket_name != "" ? 1 : 0
  bucket = var.cube_store_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.cloud_run_cube.email}"
}

# 8. Cross-Project Read Access (Conditional: only created if reporting_project_id differs from project_id)
resource "google_bigquery_dataset_iam_member" "cross_project_reporting_reader" {
  count      = (var.reporting_project_id != "" && var.reporting_project_id != var.project_id) ? 1 : 0
  project    = var.reporting_project_id
  dataset_id = var.reporting_dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.cloud_run_cube.email}"
}

# 8. Secret Manager: FastMCP Google OAuth Credentials
resource "google_secret_manager_secret" "google_client_id" {
  secret_id = "fastmcp-google-client-id"

  replication {
    auto {}
  }

  labels = {
    environment = var.environment
    purpose     = "fastmcp-oauth"
  }

  depends_on = [var.services_dependency]
}

resource "google_secret_manager_secret_version" "google_client_id_placeholder" {
  secret      = google_secret_manager_secret.google_client_id.id
  secret_data = "placeholder"

  lifecycle {
    ignore_changes = [secret_data]
  }
}

resource "google_secret_manager_secret" "google_client_secret" {
  secret_id = "fastmcp-google-client-secret"

  replication {
    auto {}
  }

  labels = {
    environment = var.environment
    purpose     = "fastmcp-oauth"
  }

  depends_on = [var.services_dependency]
}

resource "google_secret_manager_secret_version" "google_client_secret_placeholder" {
  secret      = google_secret_manager_secret.google_client_secret.id
  secret_data = "placeholder"

  lifecycle {
    ignore_changes = [secret_data]
  }
}

# 9. Secret Manager & Random Generator: Cube Core API Secret
resource "random_password" "cube_api_secret" {
  length  = 48
  special = false
}

resource "google_secret_manager_secret" "cube_api_secret" {
  secret_id = "cube-api-secret"

  replication {
    auto {}
  }

  labels = {
    environment = var.environment
    purpose     = "cube-auth"
  }

  depends_on = [var.services_dependency]
}

resource "google_secret_manager_secret_version" "cube_api_secret" {
  secret      = google_secret_manager_secret.cube_api_secret.id
  secret_data = var.cubejs_api_secret != "" ? var.cubejs_api_secret : random_password.cube_api_secret.result
}

# 10. IAM: Secret Accessor on OAuth & API Secrets for Unified Service Account
resource "google_secret_manager_secret_iam_member" "cube_sa_secrets_accessor" {
  for_each = toset([
    google_secret_manager_secret.google_client_id.secret_id,
    google_secret_manager_secret.google_client_secret.secret_id,
    google_secret_manager_secret.cube_api_secret.secret_id,
  ])
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_run_cube.email}"
}

# 11. Multi-Container Cloud Run v2 Service (Conditional on enabled = true)
locals {
  cube_image_url         = var.container_image != "" ? var.container_image : "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.cube_repo.repository_id}/cube-api:${var.cube_image_tag}"
  fastmcp_image_url      = var.fastmcp_container_image != "" ? var.fastmcp_container_image : "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.cube_repo.repository_id}/fastmcp-api:${var.fastmcp_image_tag}"
  reporting_project_id   = var.reporting_project_id != "" ? var.reporting_project_id : var.project_id
  reporting_table_prefix = var.reporting_project_id != "" && var.reporting_project_id != var.project_id ? "`${var.reporting_project_id}`.${var.reporting_dataset_id}" : var.reporting_dataset_id
}

resource "google_cloud_run_v2_service" "cube_mcp" {
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

    # Container 1: Sidecar - Cube Core Semantic Engine (internal port 4000)
    containers {
      name  = "cube-core"
      image = local.cube_image_url

      startup_probe {
        initial_delay_seconds = 2
        timeout_seconds       = 4
        period_seconds        = 5
        failure_threshold     = 24

        tcp_socket {
          port = 4000
        }
      }

      resources {
        limits = {
          cpu    = var.cube_cpu_limit
          memory = var.cube_memory_limit
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
        name  = "CUBEJS_REPORTING_PROJECT_ID"
        value = local.reporting_project_id
      }
      env {
        name  = "CUBEJS_REPORTING_DATASET_ID"
        value = var.reporting_dataset_id
      }
      env {
        name  = "CUBEJS_REPORTING_TABLE_PREFIX"
        value = local.reporting_table_prefix
      }
      env {
        name  = "CUBEJS_DB_BQ_LOCATION"
        value = var.region
      }
      env {
        name  = "CUBEJS_DEV_MODE"
        value = (var.environment == "dev" && var.dev_mode) ? "true" : "false"
      }
      env {
        name = "CUBEJS_API_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.cube_api_secret.secret_id
            version = "latest"
          }
        }
      }
      env {
        name  = "CUBEJS_TELEMETRY"
        value = "false"
      }
      env {
        name  = "CUBEJS_PORT"
        value = "4000"
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

    # Container 2: Ingress - FastMCP Service (external port 8080)
    containers {
      name       = "fastmcp"
      image      = local.fastmcp_image_url
      depends_on = ["cube-core"]

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = var.fastmcp_cpu_limit
          memory = var.fastmcp_memory_limit
        }
      }

      env {
        name  = "CUBE_API_URL"
        value = "http://127.0.0.1:4000"
      }
      env {
        name = "CUBE_API_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.cube_api_secret.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "GOOGLE_CLIENT_ID"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.google_client_id.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "GOOGLE_CLIENT_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.google_client_secret.secret_id
            version = "latest"
          }
        }
      }
      env {
        name  = "GOOGLE_AUTH_ENABLED"
        value = var.google_auth_enabled ? "true" : "false"
      }
      env {
        name  = "FASTMCP_TRANSPORT"
        value = var.fastmcp_transport
      }
      dynamic "env" {
        for_each = var.fastmcp_public_url != "" ? [1] : []
        content {
          name  = "FASTMCP_PUBLIC_URL"
          value = var.fastmcp_public_url
        }
      }
    }

    # Shared Direct VPC Egress for the entire multi-container pod
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
    google_project_iam_member.cube_bq_data_editor,
    google_project_iam_member.cube_logging,
    google_secret_manager_secret_version.google_client_id_placeholder,
    google_secret_manager_secret_version.google_client_secret_placeholder,
    google_secret_manager_secret_version.cube_api_secret,
    google_secret_manager_secret_iam_member.cube_sa_secrets_accessor,
    var.services_dependency
  ]
}

# 11. Private Authorized Invoker IAM (Restricts invocation of FastMCP ingress to authorized callers)
resource "google_cloud_run_v2_service_iam_member" "invoker_access" {
  for_each = var.enabled ? toset(var.invoker_members) : []
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.cube_mcp[0].name
  role     = "roles/run.invoker"
  member   = each.value
}
