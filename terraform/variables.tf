variable "project_id" {
  type        = string
  description = "The GCP Project ID where serving resources will be provisioned (Project B)."
}

variable "reporting_project_id" {
  type        = string
  description = "Project ID of the BigQuery reporting/warehouse layer (Project A). Leave empty to use project_id."
  default     = ""
}

variable "reporting_dataset_id" {
  type        = string
  description = "BigQuery dataset name containing reporting fact and dimension tables."
  default     = "analytics"
}

variable "region" {
  type        = string
  description = "The primary GCP region for regional resources (Cloud Run, GCS)."
  default     = "us-central1"
}

variable "zone" {
  type        = string
  description = "The GCP zone for zonal resources (Spot VM)."
  default     = "us-central1-a"
}

variable "environment" {
  type        = string
  description = "Deployment environment name (dev, staging, prod)."
  default     = "dev"
}

variable "enable_cube_store" {
  type        = bool
  description = "Toggle to turn the Cube Store Spot VM on or off."
  default     = true
}

variable "enable_cloud_run" {
  type        = bool
  description = "Toggle to deploy the Cloud Run Cube Core API service. Keep false until container image is built and pushed."
  default     = false
}

variable "dev_mode" {
  type        = bool
  description = "Whether to run Cube Core in development mode. Only active when environment is 'dev'."
  default     = false
}

variable "cube_store_machine_type" {
  type        = string
  description = "Compute Engine machine type for the Cube Store Spot VM."
  default     = "e2-small"
}

variable "cube_store_boot_disk_size_gb" {
  type        = number
  description = "Boot disk size in GB for the Cube Store VM (minimum 10 GB for Container-Optimized OS)."
  default     = 10

  validation {
    condition     = var.cube_store_boot_disk_size_gb >= 10
    error_message = "The boot disk size must be at least 10 GB for Google Container-Optimized OS."
  }
}

variable "gcp_services" {
  type        = list(string)
  description = "List of GCP APIs to enable for Phase 1 infrastructure."
  default = [
    "artifactregistry.googleapis.com",     # Artifact Registry for Docker images
    "bigquery.googleapis.com",             # Google BigQuery
    "bigquerydatatransfer.googleapis.com", # BigQuery Data Transfer Service
    "cloudbuild.googleapis.com",           # Cloud Build for container builds
    "compute.googleapis.com",              # Spot VM & MIG
    "iamcredentials.googleapis.com",       # IAM Service Account Credentials API for signBlob
    "run.googleapis.com",                  # Cloud Run Services
    "storage.googleapis.com",              # GCS Buckets (Cube Store & State)
    "vpcaccess.googleapis.com",            # Direct VPC Egress / Serverless Connector
    "logging.googleapis.com",              # Cloud Logging sinks
    "secretmanager.googleapis.com",        # Secret Manager for OAuth & API secrets
  ]
}

variable "google_auth_enabled" {
  type        = bool
  description = "Whether to enforce Google OAuth authentication inside FastMCP."
  default     = false
}

variable "invoker_members" {
  type        = list(string)
  description = "List of IAM identities granted roles/run.invoker to access the Cloud Run service (e.g. user:alice@example.com, group:team@example.com, serviceAccount:...)."
  default     = []
}

variable "fastmcp_public_url" {
  type        = string
  description = "Public HTTPS URL of the Cloud Run service, used for Google OAuth 2.0 callback redirect URIs."
  default     = "https://cube-mcp-h3ungosjsa-el.a.run.app"
}

variable "fastmcp_transport" {
  type        = string
  description = "Transport protocol for FastMCP ('streamable-http' or 'sse')."
  default     = "streamable-http"
}
