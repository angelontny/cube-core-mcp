variable "project_id" {
  type        = string
  description = "The GCP Project ID where compute resources will be provisioned."
}

variable "region" {
  type        = string
  description = "The primary GCP region for regional compute resources."
}

variable "zone" {
  type        = string
  description = "The GCP zone for the compute resources."
}

variable "environment" {
  type        = string
  description = "Deployment environment name (dev, staging, prod)."
  default     = "dev"
}

variable "enabled" {
  type        = bool
  description = "Master switch to turn the Cube Store Spot VM on or off."
  default     = true
}

variable "subnet_id" {
  type        = string
  description = "The ID of the private subnet where the Cube Store VM will reside."
}

variable "cube_store_private_ip" {
  type        = string
  description = "The static internal IP address reserved for the Cube Store cache node."
}

variable "cube_store_address_id" {
  type        = string
  description = "The resource ID or self-link of the reserved static internal IP address for Cube Store."
  default     = ""
}

variable "cube_store_sa_email" {
  type        = string
  description = "The email of the dedicated service account attached to the Cube Store VM."
}

variable "cube_store_bucket_name" {
  type        = string
  description = "The name of the GCS bucket storing Cube Store Parquet files."
}

variable "machine_type" {
  type        = string
  description = "Compute Engine machine type for the Cube Store Spot VM."
  default     = "e2-small"
}

variable "boot_disk_size_gb" {
  type        = number
  description = "Size of the boot disk in GB (minimum 10 GB for Container-Optimized OS)."
  default     = 10
}

variable "cube_store_image" {
  type        = string
  description = "Docker image repository and tag for Cube Store."
  default     = "cubejs/cubestore:v0.36.0"
}
