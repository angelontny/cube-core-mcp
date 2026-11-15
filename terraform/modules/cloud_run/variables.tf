# ------------------------------------------------------------------------------
# Cloud Run Module: Variables (Unified Multi-Container Service)
# ------------------------------------------------------------------------------

variable "project_id" {
  type        = string
  description = "The GCP Project ID where resources will be provisioned."
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
  description = "Whether to provision the Cloud Run service. Set to false initially until container images are built."
  default     = false
}

variable "service_name" {
  type        = string
  description = "Name of the unified multi-container Cloud Run v2 service."
  default     = "cube-mcp"
}

variable "container_image" {
  type        = string
  description = "Specific container image URL for Cube Core. If empty, defaults to Artifact Registry repository with cube_image_tag."
  default     = ""
}

variable "cube_image_tag" {
  type        = string
  description = "Container image tag for Cube Core in Artifact Registry."
  default     = "v0.36.0"
}

variable "fastmcp_container_image" {
  type        = string
  description = "Specific container image URL for FastMCP. If empty, defaults to Artifact Registry repository with fastmcp_image_tag."
  default     = ""
}

variable "fastmcp_image_tag" {
  type        = string
  description = "Container image tag for FastMCP ingress in Artifact Registry."
  default     = "v0.1.0"
}

# --- Sizing & Scaling (Service Level) ---

variable "min_instances" {
  type        = number
  description = "Minimum instances for the multi-container service (0 enables scale-to-zero when idle)."
  default     = 0
}

variable "max_instances" {
  type        = number
  description = "Maximum scaling ceiling for the multi-container service."
  default     = 3
}

# --- Container Limits: Cube Core Sidecar ---

variable "cube_cpu_limit" {
  type        = string
  description = "CPU limit for the Cube Core sidecar container."
  default     = "1000m"
}

variable "cube_memory_limit" {
  type        = string
  description = "Memory limit for the Cube Core sidecar container."
  default     = "1Gi"
}

# --- Container Limits: FastMCP Ingress ---

variable "fastmcp_cpu_limit" {
  type        = string
  description = "CPU limit for the FastMCP ingress container."
  default     = "1000m"
}

variable "fastmcp_memory_limit" {
  type        = string
  description = "Memory limit for the FastMCP ingress container."
  default     = "1Gi"
}

# --- Operational Toggles & Configuration ---

variable "dev_mode" {
  type        = bool
  description = "Whether to run Cube Core in development mode. Only active when environment is 'dev'."
  default     = false
}

variable "cubejs_api_secret" {
  type        = string
  description = "Security secret used by Cube Core to sign and verify API tokens. If left empty, an automated secret is generated in Secret Manager."
  default     = ""
  sensitive   = true
}

variable "google_auth_enabled" {
  type        = bool
  description = "Whether to enforce Google OAuth authentication inside FastMCP."
  default     = false
}

variable "fastmcp_public_url" {
  type        = string
  description = "Public URL of the FastMCP service for OAuth redirect URI construction."
  default     = ""
}

variable "fastmcp_transport" {
  type        = string
  description = "Transport protocol for FastMCP ('streamable-http' or 'sse')."
  default     = "streamable-http"
}

# --- Networking (Direct VPC Egress to Cube Store) ---

variable "network_id" {
  type        = string
  description = "The self-link or resource ID of the VPC network."
}

variable "subnet_id" {
  type        = string
  description = "The self-link or resource ID of the subnetwork for Direct VPC Egress."
}

variable "cube_store_host" {
  type        = string
  description = "Internal IP address of the Cube Store cache node (e.g. 10.10.0.10)."
  default     = ""
}

variable "cube_store_port" {
  type        = string
  description = "Port on which Cube Store accepts connections (default 3030)."
  default     = "3030"
}

variable "cube_store_bucket_name" {
  type        = string
  description = "GCS bucket name for Cube Store cache exports."
  default     = ""
}

variable "invoker_members" {
  type        = list(string)
  description = "List of IAM members authorized to invoke the private Cloud Run service."
  default     = []
}
