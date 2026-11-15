# ADR-0002: Why systemd Supervises Cube Store on Container-Optimized OS

* **Status:** Accepted
* **Date:** 2026-11-11 (Updated 2026-11-15)
* **Deciders:** Infrastructure & Semantic Layer Architecture Team
* **Consulted:** DevOps, Cloud Reliability Engineering
* **Informed:** Core Engineering Team

---

## 1. Context and Problem Statement

When deploying containerized workloads onto Google Compute Engine VMs, a common implementation is passing shell scripts via `metadata_startup_script` that invoke detached containers (`docker run -d`).

On Google Cloud's **Container-Optimized OS (COS)**, however, the root filesystem (`/`) is mounted read-only by design, and `metadata_startup_script` runs asynchronously during cold boot. Running detached containers in startup scripts leads to:
1. **Silent crashes and zero process recovery:** If the container process crashes, the VM continues running in Google Cloud Console while failing to answer queries on port 3030.
2. **Boot race conditions:** The script often triggers before the Docker socket (`/var/run/docker.sock`), local network bridge (`docker0`), or routing paths are active.
3. **Observability black hole:** Container stdout/stderr is written to local JSON files inside `/var/lib/docker/` and never appears in serial console logs or Google Cloud Logging.
4. **Ungraceful Spot VM Preemption:** When Google sends an ACPI shutdown signal during a Spot VM preemption, detached containers receive an immediate `SIGKILL` instead of executing a graceful flush of RocksDB metastore buffers.

---

## 2. Decision Drivers

* **Process Self-Healing:** The host OS must automatically restart Cube Store if it crashes or is killed by the kernel out-of-memory (OOM) killer.
* **Strict Startup Sequencing:** Docker daemon and network initialization must complete before container execution begins.
* **Unified Observability:** Logs must stream directly into Linux `journald` and propagate to Google Cloud Logging.
* **Safe Credential Injection:** The GCS service account JSON key required by the Rust `cloud-storage-rs` driver must be written with `0600` permissions before container invocation.

---

## 3. Considered Options

* **Option 1: Raw `docker run -d` in `metadata_startup_script`**
* **Option 2: Google Cloud VM Instance Container Declaration (`gce-container-declaration`)**
* **Option 3: Declarative `cloud-init` writing a `systemd` Unit File (Selected)**

---

## 4. Evaluation and Decision Outcome

**Chosen Option:** **Option 3: Declarative `cloud-init` writing a `systemd` Unit File (`/etc/systemd/system/cube-store.service`) via VM `metadata { user-data = ... }`**.

### Configuration Blueprint

```yaml
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
      Environment="HOME=/var/lib/cube-store"
      TimeoutStartSec=0
      Restart=always
      ExecStartPre=/bin/mkdir -p /var/lib/cube-store
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
  - systemctl daemon-reload
  - systemctl start cube-store.service
```

---

## 5. Consequences

### Positive Consequences
* **Automated Self-Healing (`Restart=always`):** If Cube Store crashes or exhausts memory, `systemd` immediately initiates a container restart.
* **Deterministic Sequencing:** `After=docker.service` and `Requires=docker.service` eliminate boot-time race conditions.
* **Secure Credential Injection:** `write_files` safely decodes the ephemeral service account key with restrictive permissions (`0600`) before Docker runs.
* **Clean Shutdown Handshake:** When GCP sends an ACPI shutdown signal for Spot preemption, `systemd` issues `ExecStop` (`docker stop`), transmitting a `SIGTERM` to Cube Store and granting it time to flush in-flight RocksDB metadata to GCS.
* **Standard Operational Tooling:** Operators can run standard `systemctl status cube-store`, `journalctl -u cube-store -f`, and `systemctl restart cube-store` commands.

### Negative Consequences / Risks
* Modifications to `user-data` metadata in Terraform force the recreation of the Compute Engine instance.

---

## 6. Related Documents
* [ADR-0001: Why Cube Store Cannot Run on Cloud Run](file:///home/angelo/projects/cube-core-mcp/docs/architecture/adrs/0001_why_cube_store_cannot_run_on_cloud_run.md)
* [ADR-0005: Artifact Registry Image Mirroring vs. Cloud NAT](file:///home/angelo/projects/cube-core-mcp/docs/architecture/adrs/0005_artifact_registry_mirroring_vs_cloud_nat.md)
* [terraform/modules/compute.md](file:///home/angelo/projects/cube-core-mcp/docs/terraform/modules/compute.md)
