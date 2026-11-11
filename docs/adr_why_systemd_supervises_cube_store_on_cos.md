# Architectural Decision Record: Why Systemd Supervises Cube Store on Container-Optimized OS (COS)

This document details why the **Cube Store** container on Google Compute Engine is deployed as a managed **`systemd` service** via declarative **`cloud-init` (`user-data`)**, rather than executed directly as a detached container (`docker run -d`) inside a traditional startup script (`metadata_startup_script`).

---

## 1. Context & Problem Statement

When deploying containerized workloads on Google Compute Engine, the most naive approach is embedding shell commands inside an instance's startup script:

```bash
#!/bin/bash
# Anti-pattern: Detached Docker execution in a raw startup script
docker run -d --name cube-store -p 3030:3030 -p 9999:9999 \
  -e CUBESTORE_GCS_BUCKET="cube-core-mcp-cube-store-cache" \
  cubejs/cubestore:latest
```

While this works in toy environments, executing containers directly via `docker run -d` inside Container-Optimized OS (COS) causes critical reliability, observability, and lifecycle failures in production and proof-of-concept testing.

---

## 2. Failure Modes of Direct `docker run -d`

### A. Zero Process Supervision and Recovery
* **The Problem**: A raw `docker run -d` is a fire-and-forget invocation. Once the Docker client exits, nothing supervises the running container process from the host operating system.
* **The Failure**: If Cube Store encounters an unhandled exception, runs out of memory (OOM), or crashes due to misconfiguration (such as an invalid image tag or GCS permission denial), the container stops. The VM remains `RUNNING` in Google Cloud Console, billing hourly compute charges, while serving zero traffic. The host OS has no mechanism to restart the failed container.

### B. Startup Race Conditions with the Docker Daemon and Network
* **The Problem**: Google Compute Engine executes `metadata_startup_script` asynchronously during machine boot alongside host system initialization.
* **The Failure**: At the exact millisecond the startup script executes:
  1. The Docker daemon socket (`/var/run/docker.sock`) may still be initializing.
  2. The network interface carrier (`docker0` / `eth0`) and DHCP lease may not yet be bound.
  3. The Cloud NAT egress gateway connection might experience initial route propagation delay.
  If any of these dependencies are unready, the raw `docker run` command exits immediately with an error (e.g., exit code `125`), the script terminates, and the VM never attempts to run the container again.

### C. Execution Semantics: Run-Once vs. Declarative State
* **The Problem**: In GCE, `metadata_startup_script` executes strictly **once** upon instance creation.
* **The Failure**: If you modify environment variables, update the container image tag in Terraform, or restart an interrupted task, GCE does **not** re-run the startup script on the running VM. Conversely, operators have no standard commands (`systemctl restart`, `systemctl status`) to manage or reload the container without full SSH and manual Docker command interventions.

### D. The Observability Black Hole
* **The Problem**: Detached containers (`-d`) write stdout and stderr into local JSON log files inside `/var/lib/docker/containers/`.
* **The Failure**: 
  1. Serial port console output (`gcloud compute instances get-serial-port-output`) shows only the startup script execution, not the container's ongoing runtime logs.
  2. If the container crashes in a reboot loop, serial logs remain empty or display fragmented network state (`docker0: port 1 entered disabled state`).
  3. Container logs are isolated from the host OS logging daemon and do not stream reliably to Google Cloud Logging.

### E. Unclean Shutdown and Spot VM Preemption Hazards
* **The Problem**: Cube Store runs on a **Spot VM** to optimize compute costs. Google Cloud provides a 30-second ACPI shutdown notice (`SIGTERM`) before preempting Spot instances.
* **The Failure**: Detached containers without host process managers are not wired to OS shutdown targets. During preemption or instance stop events, the VM halts abruptly, sending `SIGKILL` to Docker. This prevents Cube Store from executing its graceful shutdown sequence: flushing in-memory pre-aggregation write buffers, persisting pending metadata to Cloud Storage, and closing database connections cleanly.

---

## 3. The Solution: Declarative Cloud-Init Systemd Service

Google Cloud's **Container-Optimized OS (COS)** is a security-hardened Linux distribution where the root filesystem (`/`) is mounted **read-only**, and the host is purpose-built to supervise containerized applications exclusively via **`systemd`**.

We configure the VM using declarative **`cloud-init`** (`user-data` metadata) that writes a dedicated systemd service unit (`/etc/systemd/system/cube-store.service`):

```yaml
#cloud-config

write_files:
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
      ExecStartPre=/usr/bin/docker pull cubejs/cubestore:latest
      ExecStart=/usr/bin/docker run --rm --name %n \
        -p 3030:3030 \
        -p 9999:9999 \
        -e CUBESTORE_GCS_BUCKET="cube-core-mcp-cube-store-cache" \
        cubejs/cubestore:latest
      ExecStop=/usr/bin/docker stop %n

      [Install]
      WantedBy=multi-user.target

runcmd:
  - systemctl daemon-reload
  - systemctl start cube-store.service
```

---

## 4. Architectural Advantages of Systemd Supervision

### 1. Guaranteed Dependency Sequencing
* `After=docker.service` and `Requires=docker.service` ensure that systemd halts container execution until the Docker daemon is fully initialized, healthy, and listening on its UNIX socket.
* Eliminates all race conditions during cold boot.

### 2. Automatic Healing and Crash Recovery
* `Restart=always` instructs systemd to monitor the container PID continuously.
* If Cube Store crashes, runs out of memory, or encounters a transient failure, systemd automatically pauses, triggers cleanup, and restarts the container instantly without human intervention.

### 3. Idempotent Lifecycle (`ExecStartPre` Cleanup)
* `ExecStartPre=-/usr/bin/docker stop %n` and `ExecStartPre=-/usr/bin/docker rm %n`:
  Before starting, systemd ensures any orphaned or exited container with the same name (`cube-store.service`) is removed cleanly. The `-` prefix ensures that if no previous container exists, the pre-command exits safely without failing the unit.
* `ExecStartPre=/usr/bin/docker pull ...`: Guarantees the image layer is verified and pulled before execution starts.

### 4. Foreground Execution and Direct Cloud Logging Integration
* Notice that `ExecStart` runs `docker run` **in the foreground** (without `-d`).
* The container process becomes the direct payload of the systemd unit. All container `stdout` and `stderr` streams flow directly into **`systemd-journald`**.
* In Container-Optimized OS, the built-in Google Cloud Logging agent (`google-fluentbit`) automatically tails `systemd-journald`. Every log line emitted by Cube Store streams directly into **Google Cloud Logging** in real time, queryable from Cloud Console or `gcloud logging read` without requiring an open SSH session.

### 5. Graceful Preemption on Spot VMs
* `ExecStop=/usr/bin/docker stop %n`:
  When GCP sends an ACPI shutdown signal during Spot VM preemption or instance stop, systemd triggers `ExecStop`.
* Docker issues `SIGTERM` to Cube Store, giving the process 10 seconds to flush its cache partitions to GCS, checkpoint metadata, and cleanly disconnect active clients before the machine stops.

---

## 5. Architectural Comparison Matrix

| Operational Capability | Raw `docker run -d` | Systemd Service Unit (`cloud-init`) |
| :--- | :--- | :--- |
| **Process Supervisor** | None (Orphaned client) | Host-level `systemd` init system |
| **Crash Recovery** | None (VM stays up, container stays dead) | `Restart=always` with automatic recovery |
| **Boot Sequencing** | Prone to Docker socket / network race conditions | Strictly ordered via `Requires=docker.service` |
| **Log Routing** | Trapped in `/var/lib/docker/` local files | Streamed to `journald` & Google Cloud Logging |
| **Spot Preemption Handling** | Abrupt `SIGKILL` (risk of corrupted local cache) | Clean `SIGTERM` via `ExecStop` before halt |
| **Admin Operations** | Ad-hoc `docker run / rm` shell scripts | Standard `systemctl restart / status cube-store` |
| **Deployment Standard** | Legacy hack | Official Google Container-Optimized OS pattern |

---

## 6. Summary

Wrapping Cube Store in a `systemd` unit managed by `cloud-init` transforms an ephemeral Docker container into a first-class, supervised operating system service. It ensures high availability, automatic self-healing on failure, centralized Cloud Logging, and clean data persistence during Spot VM preemption.