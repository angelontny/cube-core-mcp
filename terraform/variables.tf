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

variable "gcp_services" {
  type        = list(string)
  description = "List of GCP APIs to enable for Phase 1 infrastructure."
  default = [
    "compute.googleapis.com",              # Spot VM & MIG
    "run.googleapis.com",                  # Cloud Run Services
    "storage.googleapis.com",              # GCS Buckets (Cube Store & State)
    "vpcaccess.googleapis.com",            # Direct VPC Egress / Serverless Connector
    "iam.googleapis.com",                  # IAM Roles & Service Accounts
    "cloudresourcemanager.googleapis.com", # Project metadata & IAM policy bindings
    "logging.googleapis.com",              # Cloud Logging sinks
  ]
}
