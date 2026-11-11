# ------------------------------------------------------------------------------
# Compute Module: Cube Store Standalone Spot VM with Cloud-Init Systemd Service
# ------------------------------------------------------------------------------

# 1. Ephemeral Service Account Key for Cube Store Rust GCS Driver
# The Rust cloud-storage-rs crate requires an explicit service account key file
# (GOOGLE_APPLICATION_CREDENTIALS) to sign GCS requests. Tied to instance lifecycle.
resource "google_service_account_key" "cube_store" {
  count              = var.enabled ? 1 : 0
  service_account_id = var.cube_store_sa_email
}

# 2. Compute Engine Spot VM Instance
# Deployed with static private IP 10.10.0.10, zero external public IP,
# 10 GB minimal boot disk, and backed by Cloud Storage Parquet persistence.
resource "google_compute_instance" "cube_store" {
  count = var.enabled ? 1 : 0

  name         = "cube-store"
  machine_type = var.machine_type
  zone         = var.zone

  tags = ["cube-store-node"]

  # Spot scheduling: 60-91% cost savings with zero persistent storage risk
  scheduling {
    preemptible                 = true
    automatic_restart           = false
    provisioning_model          = "SPOT"
    instance_termination_action = "STOP"
  }

  boot_disk {
    auto_delete = true
    initialize_params {
      image = "projects/cos-cloud/global/images/family/cos-stable"
      type  = "pd-standard"
      size  = var.boot_disk_size_gb
    }
  }

  network_interface {
    subnetwork = var.subnet_id
    network_ip = var.cube_store_private_ip
    # Zero external public IP. Inbound via VPC subnet; outbound via Cloud NAT.
  }

  service_account {
    email  = var.cube_store_sa_email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  # Declarative cloud-init metadata for Container-Optimized OS:
  # Injects the GCS credentials key file securely with 0600 permissions
  # and registers cube-store as a managed systemd service.
  metadata = {
    user-data = <<-EOF
      #cloud-config

      write_files:
        - path: /etc/cube-store/sa-key.json
          permissions: "0600"
          owner: "root"
          encoding: b64
          content: ${google_service_account_key.cube_store[0].private_key}

        - path: /etc/systemd/system/cube-store.service
          permissions: "0644"
          owner: "root"
          content: |
            [Unit]
            Description=Cube Store OLAP Cache Engine
            After=docker.service
            Requires=docker.service

            [Service]
            TimeoutStartSec=0
            Restart=always
            ExecStartPre=-/usr/bin/docker stop %n
            ExecStartPre=-/usr/bin/docker rm %n
            ExecStartPre=/usr/bin/docker pull ${var.cube_store_image}
            ExecStart=/usr/bin/docker run --rm --name %n \
              -p 3030:3030 \
              -p 9999:9999 \
              -v /etc/cube-store/sa-key.json:/etc/cube-store/sa-key.json:ro \
              -e GOOGLE_APPLICATION_CREDENTIALS=/etc/cube-store/sa-key.json \
              -e CUBESTORE_GCP_KEY_FILE=/etc/cube-store/sa-key.json \
              -e CUBESTORE_GCS_BUCKET="${var.cube_store_bucket_name}" \
              -e RUST_BACKTRACE=full \
              ${var.cube_store_image}
            ExecStop=/usr/bin/docker stop %n

            [Install]
            WantedBy=multi-user.target

      runcmd:
        - systemctl daemon-reload
        - systemctl start cube-store.service
    EOF
  }
}
