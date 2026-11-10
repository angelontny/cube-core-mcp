variable "project_id" {
  type        = string
  description = "The GCP Project ID where BigQuery datasets will be provisioned."
}

variable "region" {
  type        = string
  description = "The primary GCP region for BigQuery datasets and transfer service."
}

variable "environment" {
  type        = string
  description = "Deployment environment name (dev, staging, prod)."
  default     = "dev"
}

variable "services_dependency" {
  type        = any
  description = "Dependency trigger ensuring GCP APIs and propagation timers have resolved."
  default     = null
}
