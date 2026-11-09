provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Note: The Google provider automatically injects the attribution label
  # `goog-terraform-provisioned = "true"` on all supported resources.
  default_labels = {
    environment = var.environment
    project     = var.project_id
  }
}
