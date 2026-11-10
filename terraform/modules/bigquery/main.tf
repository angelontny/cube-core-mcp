# ------------------------------------------------------------------------------
# BigQuery Module: Datasets & Cross-Region Data Transfer
# ------------------------------------------------------------------------------

data "google_project" "project" {}

resource "google_service_account" "bq_transfer" {
  account_id   = "bq-transfer-sa"
  display_name = "BigQuery Data Transfer Service Account"
  description  = "Dedicated identity for executing BigQuery cross-region dataset replication"
}

resource "google_project_iam_member" "bq_transfer_admin" {
  project = var.project_id
  role    = "roles/bigquery.admin"
  member  = "serviceAccount:${google_service_account.bq_transfer.email}"
}

resource "google_service_account_iam_member" "transfer_agent_token_creator" {
  service_account_id = google_service_account.bq_transfer.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-bigquerydatatransfer.iam.gserviceaccount.com"
}

# Wait buffer to allow IAM token minting cache to propagate before transfer config tests delegation
resource "time_sleep" "wait_for_transfer_iam" {
  depends_on = [
    google_service_account_iam_member.transfer_agent_token_creator,
    google_project_iam_member.bq_transfer_admin,
  ]

  create_duration = "30s"
}

resource "google_bigquery_dataset" "thelook_ecommerce" {
  dataset_id                  = "thelook_ecommerce"
  friendly_name               = "TheLook eCommerce Raw Data"
  description                 = "Local regional replica of bigquery-public-data.thelook_ecommerce"
  location                    = var.region
  default_table_expiration_ms = null

  labels = {
    environment = var.environment
    managed_by  = "terraform"
    source_data = "thelook-ecommerce"
  }

  delete_contents_on_destroy = var.environment == "dev" ? true : false

  depends_on = [var.services_dependency]
}

resource "google_bigquery_dataset" "analytics" {
  dataset_id                  = "analytics"
  friendly_name               = "TheLook Analytics Marts"
  description                 = "Curated analytics dimensional models and facts transformed by dbt"
  location                    = var.region
  default_table_expiration_ms = null

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }

  delete_contents_on_destroy = var.environment == "dev" ? true : false

  depends_on = [var.services_dependency]
}

resource "google_bigquery_data_transfer_config" "thelook_cross_region_copy" {
  display_name           = "thelook-ecommerce-cross-region-sync"
  location               = var.region
  data_source_id         = "cross_region_copy"
  destination_dataset_id = google_bigquery_dataset.thelook_ecommerce.dataset_id
  service_account_name   = google_service_account.bq_transfer.email

  schedule_options {
    disable_auto_scheduling = true
  }

  params = {
    source_project_id           = "bigquery-public-data"
    source_dataset_id           = "thelook_ecommerce"
    overwrite_destination_table = "true"
  }

  depends_on = [
    google_bigquery_dataset.thelook_ecommerce,
    time_sleep.wait_for_transfer_iam,
    var.services_dependency,
  ]
}
