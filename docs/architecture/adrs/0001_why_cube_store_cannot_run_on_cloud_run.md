# ADR-0001: Why Cube Store Cannot Run on Google Cloud Run

* **Status:** Accepted
* **Date:** 2026-11-11 (Updated 2026-11-15)
* **Deciders:** Infrastructure & Semantic Layer Architecture Team
* **Consulted:** Cloud Operations, Security
* **Informed:** AI Engineering, Analytics Engineers

---

## 1. Context and Problem Statement

Cube Store is Cube Core's purpose-built, Rust-based OLAP database cache engine. It accelerates analytical queries by materializing multidimensional pre-aggregations into partitioned Apache Parquet chunks stored in Google Cloud Storage, while serving incoming read queries over the MySQL wire protocol (TCP port 3030).

During initial architecture design, we sought to minimize baseline operational costs by evaluating whether the entire stack—including Cube Store—could run as a serverless container on **Google Cloud Run** to exploit automatic scale-to-zero when idle.

---

## 2. Decision Drivers

* **Protocol Support:** Cube Core connects to Cube Store using the MySQL binary wire protocol (TCP 3030) and cluster gossip (TCP 9999).
* **Continuous Background Execution:** Cube Store continuously runs RocksDB background compaction threads, memory cache evictions, and checkpoint syncs.
* **Network Predictability:** Cube Core requires a deterministic, static internal IP address (`10.10.0.10`) for query routing.
* **Local POSIX Disk Access:** RocksDB requires durable, unevictable local POSIX disk storage for write-ahead logs (WAL) and metadata indexes.
* **Cost Efficiency:** Baseline idle costs must remain as close to $0.00/month as possible.

---

## 3. Considered Options

* **Option 1: Google Cloud Run Services**
* **Option 2: Google Cloud Run Jobs**
* **Option 3: Google Cloud Run Worker Pools**
* **Option 4: Compute Engine Spot VM with Container-Optimized OS (Selected)**
* **Option 5: Google Kubernetes Engine (GKE) Autopilot**

---

## 4. Evaluation and Decision Outcome

**Chosen Option:** **Option 4: Compute Engine Spot VM with Container-Optimized OS (COS)**, combined with an automated on/off toggle (`enable_cube_store`) and durable Cloud Storage persistence.

### Detailed Technical Analysis of Alternatives

| Evaluation Criteria | Cloud Run Services | Cloud Run Jobs | Cloud Run Worker Pools | GKE Autopilot | Compute Engine Spot VM (Chosen) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Inbound Wire Protocol** | L7 HTTP/1.1, HTTP/2, gRPC only (MySQL TCP 3030 rejected) | None (Batch process) | None (Pull-based queue consumers only) | Any TCP / UDP via ClusterIP | **Any TCP/UDP port (MySQL 3030 & Gossip 9999)** |
| **Execution Lifecycle** | Request-driven (CPU throttled between requests) | Run-to-completion (Batch tasks) | Continuous daemon | Continuous daemon | **Continuous daemon** |
| **Inbound Query Ingress** | Yes (HTTP only) | No | No | Yes (Internal Service) | **Yes (Direct VPC Subnet)** |
| **Deterministic Addressing** | Dynamic / ephemeral IP per revision | Dynamic / ephemeral | None | Fixed Service ClusterIP | **Static Private IP (`10.10.0.10`)** |
| **POSIX File System** | Ephemeral in-memory tmpfs | Ephemeral tmpfs | Ephemeral tmpfs | Persistent Volume Claim | **10 GB Persistent Boot Disk** |
| **Baseline Idle Cost** | $0.00 / mo | $0.00 / mo | ~$18 - $30 / mo | ~$72.00 / mo (Cluster fee) | **~$0.00 - $7.50 / mo (Spot e2-small)** |

### Why Cloud Run Fails for Cube Store
1. **L7 Ingress Enforcement:** Cloud Run Services front all containers with Google's managed Layer 7 HTTP edge proxy. Incoming MySQL protocol handshakes on port 3030 fail HTTP protocol inspection and are terminated immediately.
2. **CPU Suspension:** Cloud Run terminates CPU allocation when an HTTP request ends, freezing RocksDB background compactions and metastore synchronizations.
3. **No Ingress on Worker Pools or Jobs:** Worker Pools and Jobs do not accept incoming TCP socket connections from external VPC clients.

---

## 5. Consequences

### Positive Consequences
* Cube Store has unrestricted access to low-level POSIX disk I/O, multi-threaded CPU, and custom TCP ports (3030, 9999).
* Spot VM scheduling provides a 60–91% discount over standard Compute Engine rates (`~$0.010/hour` for `e2-small`).
* Parquet persistence is completely decoupled to Google Cloud Storage (`gs://${PROJECT_ID}-cube-store-cache`). If the VM is preempted, zero data is lost.
* Full scale-to-zero is supported through the Terraform toggle (`enable_cube_store = false`), reducing baseline idle cost to $0.00/month.

### Negative Consequences / Risks
* Spot VMs can be preempted by Google Cloud when capacity is needed elsewhere.
* Requires process supervision via `systemd` and cloud-init metadata to ensure automated startup.

---

## 6. Related Documents
* [ADR-0002: Why systemd Supervises Cube Store on COS](file:///home/angelo/projects/cube-core-mcp/docs/architecture/adrs/0002_why_systemd_supervises_cube_store_on_cos.md)
* [ADR-0004: Multi-Container Cloud Run Pod vs. Separate Services](file:///home/angelo/projects/cube-core-mcp/docs/architecture/adrs/0004_multi_container_pod_vs_separate_services.md)
* [C4 Architecture & Design Context](file:///home/angelo/projects/cube-core-mcp/docs/architecture/c4_architecture_and_design_context.md)
