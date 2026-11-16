output "network_id" {
  description = "The ID of the custom VPC network."
  value       = google_compute_network.vpc.id
}

output "network_name" {
  description = "The name of the custom VPC network."
  value       = google_compute_network.vpc.name
}

output "subnet_id" {
  description = "The ID of the regional subnet."
  value       = google_compute_subnetwork.subnet.id
}

output "subnet_name" {
  description = "The name of the regional subnet."
  value       = google_compute_subnetwork.subnet.name
}

output "cube_store_internal_ip" {
  description = "The reserved internal IP address for the Cube Store cache node."
  value       = google_compute_address.cube_store_internal_ip.address
}

output "cube_store_internal_ip_address_id" {
  description = "The resource ID of the reserved internal IP address for Cube Store."
  value       = google_compute_address.cube_store_internal_ip.id
}
