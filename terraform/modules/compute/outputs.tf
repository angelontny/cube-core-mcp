output "instance_name" {
  description = "The base instance name of the Cube Store Managed Instance Group."
  value       = var.enabled ? google_compute_instance_group_manager.cube_store_mig[0].base_instance_name : null
}

output "instance_group" {
  description = "The instance group resource URI of the Cube Store Managed Instance Group."
  value       = var.enabled ? google_compute_instance_group_manager.cube_store_mig[0].instance_group : null
}

output "internal_ip" {
  description = "The static internal IP address of the Cube Store instance preserved across recreations."
  value       = var.enabled ? var.cube_store_private_ip : null
}

output "ready_dependency" {
  description = "Dependency anchor ensuring Cube Store VM and systemd service have initialized."
  value       = var.enabled ? time_sleep.wait_for_cube_store_boot[0].id : null
}
