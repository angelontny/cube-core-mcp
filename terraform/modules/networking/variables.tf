variable "project_id" {
  type        = string
  description = "The GCP Project ID where networking resources will be provisioned."
}

variable "region" {
  type        = string
  description = "The primary GCP region for regional networking resources (subnet, NAT, router)."
}

variable "environment" {
  type        = string
  description = "Deployment environment name (dev, staging, prod)."
  default     = "dev"
}

variable "subnet_cidr" {
  type        = string
  description = "CIDR range for the private Cube subnet."
  default     = "10.10.0.0/24"
}

variable "cube_store_private_ip" {
  type        = string
  description = "Static internal IP address reserved for the Cube Store cache node."
  default     = "10.10.0.10"
}

variable "services_dependency" {
  type        = any
  description = "Dependency trigger ensuring GCP APIs and propagation timers have resolved."
  default     = null
}
