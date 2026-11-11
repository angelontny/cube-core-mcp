output "instance_name" {
  description = "The name of the Cube Store Compute Engine instance."
  value       = var.enabled ? google_compute_instance.cube_store[0].name : null
}

output "instance_id" {
  description = "The server-assigned unique identifier of the instance."
  value       = var.enabled ? google_compute_instance.cube_store[0].instance_id : null
}

output "internal_ip" {
  description = "The static internal IP address of the Cube Store instance."
  value       = var.enabled ? google_compute_instance.cube_store[0].network_interface[0].network_ip : null
}
