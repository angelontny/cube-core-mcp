# Enable the required APIs declaratively
resource "google_project_service" "enabled_services" {
  for_each = toset(var.gcp_services)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# Explicit wait buffer to allow Google's control plane to propagate
# before downstream resources attempt provisioning.
resource "time_sleep" "wait_for_services" {
  depends_on = [google_project_service.enabled_services]

  create_duration = "90s"
}
