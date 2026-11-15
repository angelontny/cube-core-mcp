# ------------------------------------------------------------------------------
# Compute Module: Cube Store Standalone Spot VM with Cloud-Init Systemd Service
# ------------------------------------------------------------------------------

# 1. Ephemeral Service Account Key Stored Securely in Secret Manager
# The Rust cloud-storage-rs crate requires an explicit service account key file
# (GOOGLE_APPLICATION_CREDENTIALS) to sign GCS requests. Stored in Secret Manager
# and fetched at boot via VM ADC to keep it out of instance metadata.
resource "google_service_account_key" "cube_store" {
  count              = var.enabled ? 1 : 0
  service_account_id = var.cube_store_sa_email
}

resource "google_secret_manager_secret" "cube_store_sa_key" {
  count     = var.enabled ? 1 : 0
  secret_id = "cube-store-gcs-sa-key"

  replication {
    auto {}
  }

  labels = {
    environment = var.environment
    purpose     = "cube-store-gcs"
  }
}

resource "google_secret_manager_secret_version" "cube_store_sa_key" {
  count       = var.enabled ? 1 : 0
  secret      = google_secret_manager_secret.cube_store_sa_key[0].id
  secret_data = google_service_account_key.cube_store[0].private_key
}

# 2. Grant VM Service Account Access to Retrieve the Key from Secret Manager
resource "google_secret_manager_secret_iam_member" "cube_store_sa_key_accessor" {
  count     = var.enabled ? 1 : 0
  secret_id = google_secret_manager_secret.cube_store_sa_key[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.cube_store_sa_email}"
}

# 3. Compute Engine Instance Template for Cube Store Cache Node
# Configured with Container-Optimized OS, Spot scheduling, and cloud-init systemd service.
resource "google_compute_instance_template" "cube_store" {
  count = var.enabled ? 1 : 0

  name_prefix  = "cube-store-"
  machine_type = var.machine_type
  region       = var.region

  tags = ["cube-store-node"]

  # Spot scheduling: 60-91% cost savings with zero persistent storage risk
  scheduling {
    preemptible                 = true
    automatic_restart           = false
    provisioning_model          = "SPOT"
    instance_termination_action = "STOP"
  }

  disk {
    auto_delete  = true
    boot         = true
    source_image = "projects/cos-cloud/global/images/family/cos-stable"
    type         = "pd-standard"
    disk_size_gb = var.boot_disk_size_gb
  }

  network_interface {
    subnetwork = var.subnet_id
    # No public IP; internal IP dynamically assigned or preserved via stateful MIG.
  }

  service_account {
    email  = var.cube_store_sa_email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  # Declarative cloud-init metadata for Container-Optimized OS:
  # Fetches the GCS credentials key dynamically from Secret Manager at boot
  # and registers cube-store as a managed systemd service.
  metadata = {
    user-data = <<-EOF
      #cloud-config

      write_files:
        - path: /etc/cube-store/fetch-sa-key.sh
          permissions: "0700"
          owner: "root"
          content: |
            #!/bin/bash
            set -euo pipefail
            mkdir -p /etc/cube-store /var/lib/cube-store
            chmod 0700 /etc/cube-store
            TOKEN=$$(curl -s -f -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" | sed -n 's/.*"access_token": *"*\([^"]*\)"*.*/\1/p')
            if [[ -z "$$TOKEN" ]]; then
              echo "Error: Failed to obtain metadata access token" >&2
              exit 1
            fi
            PAYLOAD=$$(curl -s -f -H "Authorization: Bearer $$TOKEN" "https://secretmanager.googleapis.com/v1/projects/${var.project_id}/secrets/${google_secret_manager_secret.cube_store_sa_key[0].secret_id}/versions/latest:access" | sed -n 's/.*"data": *"*\([^"]*\)"*.*/\1/p')
            if [[ -z "$$PAYLOAD" ]]; then
              echo "Error: Failed to fetch secret payload from Secret Manager" >&2
              exit 1
            fi
            echo "$$PAYLOAD" | base64 -d > /etc/cube-store/sa-key.json
            chmod 0600 /etc/cube-store/sa-key.json

        - path: /etc/systemd/system/cube-store.service
          permissions: "0644"
          owner: "root"
          content: |
            [Unit]
            Description=Cube Store OLAP Cache Engine
            After=docker.service
            Requires=docker.service

            [Service]
            Environment="HOME=/var/lib/cube-store"
            TimeoutStartSec=0
            Restart=always
            ExecStartPre=/bin/bash /etc/cube-store/fetch-sa-key.sh
            ExecStartPre=-/usr/bin/docker stop %n
            ExecStartPre=-/usr/bin/docker rm %n
            ExecStartPre=/usr/bin/docker-credential-gcr configure-docker --registries=${var.region}-docker.pkg.dev
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
        - mkdir -p /var/lib/cube-store
        - /bin/bash /etc/cube-store/fetch-sa-key.sh
        - systemctl daemon-reload
        - systemctl restart cube-store.service
    EOF
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    google_secret_manager_secret_version.cube_store_sa_key,
    google_secret_manager_secret_iam_member.cube_store_sa_key_accessor
  ]
}

# 4. TCP Health Check on Cube Store MySQL Wire Protocol Port (3030)
resource "google_compute_health_check" "cube_store" {
  count = var.enabled ? 1 : 0

  name                = "cube-store-tcp-health-check"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  tcp_health_check {
    port = "3030"
  }
}

# 5. Zonal Managed Instance Group (MIG) with Auto-Healing and Auto-Restart
# Target size 1: Guarantees that when Google preempts the Spot VM, the MIG
# automatically recreates a fresh instance without manual operator intervention.
resource "google_compute_instance_group_manager" "cube_store_mig" {
  count = var.enabled ? 1 : 0

  name               = "cube-store-mig"
  base_instance_name = "cube-store"
  zone               = var.zone
  target_size        = 1

  version {
    instance_template = google_compute_instance_template.cube_store[0].id
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.cube_store[0].id
    initial_delay_sec = 120
  }

  update_policy {
    type                  = "OPPORTUNISTIC"
    minimal_action        = "REPLACE"
    max_unavailable_fixed = 1
  }

  stateful_internal_ip {
    interface_name = "nic0"
  }
}

# 6. Stateful Per-Instance Config
# Pins the reserved static internal IP address (10.10.0.10) to the managed instance
# across preemptions, recreations, and auto-healing events.
resource "google_compute_per_instance_config" "cube_store" {
  count = var.enabled ? 1 : 0

  zone                   = var.zone
  instance_group_manager = google_compute_instance_group_manager.cube_store_mig[0].name
  name                   = "cube-store-0"

  preserved_state {
    internal_ip {
      interface_name = "nic0"
      ip_address {
        address = var.cube_store_private_ip
      }
    }
  }
}
