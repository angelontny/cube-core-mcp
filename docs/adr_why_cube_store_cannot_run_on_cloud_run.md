# Architectural Decision Record: Why Cube Store Cannot Run on Google Cloud Run

This document details the technical and networking reasons why **Cube Store** is deployed on a dedicated **Compute Engine Spot VM** rather than **Google Cloud Run** (Services, Jobs, or Worker Pools).

---

## 1. Problem Statement

During infrastructure design and cost optimization for this proof-of-concept, we evaluated whether the entire stack—including the OLAP cache engine (**Cube Store**)—could run entirely serverless on **Google Cloud Run** to take advantage of automatic scaling to zero when inactive.

---

## 2. Technical Evaluation of Cloud Run Workload Types

Google Cloud Run provides three workload execution paradigms: **Cloud Run Services**, **Cloud Run Jobs**, and **Cloud Run Worker Pools**. Each was evaluated against the operational requirements of Cube Store:

### A. Cloud Run Services (Web Applications & APIs)
* **Design Purpose:** Stateless containers handling incoming HTTP/1.1, HTTP/2, WebSockets, or gRPC traffic.
* **Why Cube Store Fails Here:**
  1. **Strict Protocol Inspection:** Cloud Run Services front containers with Google's managed Layer 7 HTTP edge proxy. All incoming requests must be valid HTTP or gRPC. Cube Store communicates via the **MySQL binary wire protocol** (TCP port `3030`). When Cube API attempts to initiate a MySQL handshake, Google's proxy terminates or drops the connection because it is not HTTP.
  2. **CPU Throttling & Metastore Freezes:** By default, Cloud Run suspends container CPU when no active HTTP request is being processed. Even if CPU is kept allocated (`--no-cpu-throttling`), the container cannot listen on raw TCP database ports.
  3. **Ephemeral Private Networking:** Cloud Run instances receive unpredictable, dynamic IP addresses that cycle during scaling or revision deploys. Cube API requires a deterministic, static target address (like our reserved `10.10.0.10`).

### B. Cloud Run Jobs (Batch & Run-to-Completion)
* **Design Purpose:** Containerized tasks that execute a batch script, process records, and exit (e.g., nightly invoice generation, dbt runs).
* **Why Cube Store Fails Here:**
  1. Cube Store is an **always-listening daemon**, not a batch script. A database cannot exit upon startup; if the container completes and exits, the cache is unreachable.
* **Appropriate Project Use Case:** Cloud Run Jobs *are* an excellent fit for the **Cube Refresh Worker** or running `dbt run` on schedule.

### C. Cloud Run Worker Pools (Continuous Background Consumers)
* **Design Purpose:** Continuous background workloads consuming pull-based event queues (Apache Kafka, RabbitMQ, Google Cloud Pub/Sub subscriptions).
* **Why Cube Store Fails Here:**
  1. **Zero Inbound Ingress:** Worker Pools have **no inbound network endpoint**; they are strictly pull-based consumers.
  2. Cube Store cannot act as a pull-only worker; it must actively listen for incoming query requests from the Cube API Server on port `3030`.

---

## 3. Comparison Matrix

| Capability / Requirement | Cube Store Need | Cloud Run Services | Cloud Run Jobs | Cloud Run Worker Pools | Compute Engine Spot VM |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Inbound Protocol** | Raw TCP / MySQL (`3030`) | HTTP / gRPC only | None (Batch) | None (Pull only) | **Any TCP / UDP port** |
| **Lifecycle** | Continuous daemon | Request-driven / Sleep | Run to completion | Continuous daemon | **Continuous daemon** |
| **Inbound Query Ingress** | Yes (from Cube API) | Yes (HTTP only) | No | No | **Yes (Internal VPC)** |
| **Fixed Internal Address** | Yes (`10.10.0.10`) | Dynamic / Ephemeral | Dynamic | None | **Static Private IP** |
| **Local Disk Write Access** | Standard POSIX storage | In-memory tmpfs / volume | In-memory tmpfs | In-memory tmpfs | **10 GB Persistent Boot Disk** |
| **Result** | | **Incompatible** | **Incompatible** | **Incompatible** | **Architectural Fit** |

---

## 4. The Solution: Compute Engine Spot VM with On/Off Toggle

To achieve serverless-like cost efficiency while satisfying the database requirements of Cube Store:
1. **Spot Capacity Discount:** Deployed on an `e2-small` Compute Engine Spot instance in `asia-south1-c`, reducing compute pricing by ~60-91% to **~$0.010 per hour**.
2. **Minimal Boot Disk:** Sized to the GCP API minimum of **10 GB** standard persistent disk (~$0.40/month).
3. **Decoupled Durability:** Cube Store streams all pre-aggregated Parquet data to **Google Cloud Storage** (`cube-core-mcp-cube-store-cache`). Preemptions or shutdowns cause zero data loss.
4. **Master On/Off Toggle (`enable_cube_store`):**
   * When working: `enable_cube_store = true` (instance is created with reserved IP `10.10.0.10`).
   * When idle: `enable_cube_store = false` (instance is destroyed, dropping compute costs to **$0.00**).
   * Or paused instantly via CLI: `gcloud compute instances stop cube-store --zone=asia-south1-c`.

---

## 5. Architectural Role Division

This decision reinforces the clean hybrid architecture of this project:
* **Stateless Web Layer (Cloud Run v2)**: Cube Core API Server, Refresh Worker, and FastMCP (HTTP/REST, Server-Sent Events, OAuth, scale-to-zero).
* **Stateful Cache Engine (Compute Engine Spot VM)**: Cube Store Standalone (MySQL wire protocol on port `3030`, internal metastore on port `9999`, static internal IP).
* **Durable Persistence (Google Cloud Storage & BigQuery)**: Authoritative data warehouse tables and cached Parquet pre-aggregations.
