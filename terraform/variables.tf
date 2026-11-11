variable "project_id" {
  type        = string
  description = "The GCP Project ID where resources will be provisioned."
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
    "bigquery.googleapis.com",             # Google BigQuery
    "bigquerydatatransfer.googleapis.com", # BigQuery Data Transfer Service
    "compute.googleapis.com",              # Spot VM & MIG
    "run.googleapis.com",                  # Cloud Run Services
    "storage.googleapis.com",              # GCS Buckets (Cube Store & State)
    "vpcaccess.googleapis.com",            # Direct VPC Egress / Serverless Connector
    "logging.googleapis.com",              # Cloud Logging sinks
  ]
}
