variable "project_id" {
  type        = string
  description = "The GCP Project ID where resources will be provisioned."
}

variable "region" {
  type        = string
  description = "The primary GCP region for regional resources (Artifact Registry, Cloud Run)."
}

variable "environment" {
  type        = string
  description = "Deployment environment name (dev, staging, prod)."
  default     = "dev"
}

variable "services_dependency" {
  type        = any
  description = "Explicit dependency object (e.g. time_sleep) to ensure GCP APIs are fully active."
  default     = null
}

variable "repository_id" {
  type        = string
  description = "The Artifact Registry repository ID for Docker images."
  default     = "cube-repo"
}

variable "service_account_id" {
  type        = string
  description = "The account ID for the dedicated Cloud Run runtime service account."
  default     = "cloud-run-cube-sa"
}

variable "enabled" {
  type        = bool
  description = "Whether to provision the Cloud Run service. Set to false initially until the container image is built and pushed to Artifact Registry."
  default     = false
}

variable "service_name" {
  type        = string
  description = "Name of the Cloud Run v2 service."
  default     = "cube-api"
}

variable "container_image" {
  type        = string
  description = "Specific container image URL to deploy. If empty, defaults to the latest tag in the provisioned Artifact Registry repository."
  default     = ""
}

variable "container_port" {
  type        = number
  description = "Container port that Cube Core listens on."
  default     = 4000
}

variable "min_instances" {
  type        = number
  description = "Minimum number of Cloud Run container instances. Default is 0 (scale to zero when idle for $0.00 compute cost)."
  default     = 0
}

variable "max_instances" {
  type        = number
  description = "Maximum number of Cloud Run container instances."
  default     = 3
}

variable "cpu_limit" {
  type        = string
  description = "CPU allocation for the Cloud Run container (e.g. 1000m = 1 vCPU)."
  default     = "1000m"
}

variable "memory_limit" {
  type        = string
  description = "Memory allocation for the Cloud Run container."
  default     = "1Gi"
}

variable "dev_mode" {
  type        = bool
  description = "Whether to enable Cube developer mode (CUBEJS_DEV_MODE)."
  default     = true
}

variable "cubejs_api_secret" {
  type        = string
  description = "Security secret used by Cube Core to sign and verify API tokens."
  default     = "cube-core-mcp-secure-api-secret-key-2026"
}

variable "network_id" {
  type        = string
  description = "The VPC network ID for Direct VPC Egress."
}

variable "subnet_id" {
  type        = string
  description = "The regional subnetwork ID for Direct VPC Egress."
}

variable "cube_store_host" {
  type        = string
  description = "Internal IP address or hostname of the Cube Store cache node (empty when running in Direct BigQuery Mode)."
  default     = ""
}

variable "cube_store_port" {
  type        = string
  description = "Port of the Cube Store cache node."
  default     = "3030"
}

variable "cube_store_bucket_name" {
  type        = string
  description = "GCS bucket name for Cube Store cache exports (optional)."
  default     = ""
}

variable "allow_unauthenticated" {
  type        = bool
  description = "Whether to allow unauthenticated invocations (allUsers) on the Cloud Run service. Default is false (strictly private/authenticated)."
  default     = false
}

variable "invoker_members" {
  type        = list(string)
  description = "List of IAM members authorized to invoke the private Cloud Run service (e.g. serviceAccount:terraform@...)."
  default     = []
}
