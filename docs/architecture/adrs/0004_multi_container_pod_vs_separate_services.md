# ADR-0004: Multi-Container Cloud Run Pod vs. Separate Independent Services

* **Status:** Accepted
* **Date:** 2026-11-14 (Updated 2026-11-15)
* **Deciders:** Cloud Infrastructure & MCP Platform Architecture Team
* **Consulted:** Security, Core Backend Engineering
* **Informed:** All Engineering Teams

---

## 1. Context and Problem Statement

The system requires two application workloads:
1. **Cube Core API:** A Node.js container compiling semantic models, querying BigQuery, and caching pre-aggregations in Cube Store.
2. **FastMCP Server:** A Python container implementing the Model Context Protocol (MCP), validating Google OAuth 2.0 tokens, and formatting JSON responses into token-efficient Markdown tables.

Initially, these workloads were envisioned as two separate, independently deployed Cloud Run services: `cube-api` (private ingress) and `fastmcp-api` (public ingress). We evaluated whether to keep them as two microservices or unify them into a single **Google Cloud Run v2 Multi-Container Pod** (FastMCP ingress container co-located with a Cube Core sidecar container).

---

## 2. Decision Drivers

* **End-to-End Query Latency:** AI assistant tool calls require rapid responses; unnecessary network serialization and transit hops must be eliminated.
* **Cascading Cold-Start Penalty:** If FastMCP scales from zero on an incoming request, and then calls a separate Cube Core service that is also at zero, the user suffers double cold-start latency.
* **VPC Networking Overhead:** Every independent Cloud Run service requiring private network connectivity must configure Direct VPC Egress interfaces.
* **Authentication Complexity:** Service-to-service communication between independent Cloud Run services requires continuous Google OIDC ID token minting via the GCP metadata server.

---

## 3. Considered Options

* **Option 1: Two Separate Cloud Run Services (Private `cube-api` + Public `fastmcp-api`)**
* **Option 2: Combined Monolithic Container (Single Dockerfile running Python and Node.js via supervisord)**
* **Option 3: Cloud Run v2 Multi-Container Pod (FastMCP Ingress + Cube Core Sidecar) (Selected)**

---

## 4. Evaluation and Decision Outcome

**Chosen Option:** **Option 3: Cloud Run v2 Multi-Container Pod**.

### Detailed Comparison

| Evaluation Dimension | Option 1: Separate Cloud Run Services | Option 2: Monolithic Container | Option 3: Multi-Container Pod (Chosen) |
| :--- | :--- | :--- | :--- |
| **Inter-Service Communication** | Remote HTTPS over Google front-end | Local loopback (`127.0.0.1`) | **Local loopback (`127.0.0.1:4000`)** |
| **Inter-Service Latency** | 40ms – 120ms network overhead per call | < 1ms | **< 1ms memory/loopback transit** |
| **Cold-Start Behavior** | **Cascading:** FastMCP cold start (3s) + Cube Core cold start (4s) = ~7s | Single cold start (~5s) | **Synchronized cold start (~4s total)** |
| **Inter-Service Auth** | Google OIDC ID Token minting (`roles/run.invoker`) | Shared memory / none | **Signed HS256 JWT via local loopback** |
| **Direct VPC Egress** | Configured and managed on 2 services | Configured on 1 service | **Configured on 1 shared pod interface** |
| **Docker Hygiene** | 2 lean images | 1 bloated image (Node.js + Python + supervisors) | **2 lean, decoupled, specialized images** |
| **Lifecycle Dependencies** | No built-in ordering | Process manager (supervisord) | **Native `depends_on = ["cube-core"]` in Cloud Run v2** |

### Implementation Blueprint
In [terraform/modules/cloud_run/main.tf](file:///home/angelo/projects/cube-core-mcp/terraform/modules/cloud_run/main.tf):
1. **Sidecar Container (`cube-core`):**
   * Listens on internal port 4000 (not exposed to the public internet).
   * Governed by startup TCP probe on port 4000.
2. **Ingress Container (`fastmcp`):**
   * Listens on external port 8080.
   * Declares `depends_on = ["cube-core"]` so Cloud Run waits for Cube Core before routing MCP traffic.
   * Connects to Cube Core via `CUBE_API_URL=http://127.0.0.1:4000`.
3. **Shared Direct VPC Egress:**
   * Declared at the pod template level (`vpc_access`), allowing Cube Core to query the Spot VM (`10.10.0.10:3030`) over private RFC 1918 addresses without duplicate VPC connectors.

---

## 5. Consequences

### Positive Consequences
* **Sub-Millisecond Inter-Service Transport:** High-volume metadata catalogs and query results pass over `127.0.0.1` without transit encryption or public gateway hops.
* **Elimination of Cascading Cold Starts:** Both containers boot concurrently within the same microVM sandbox; when the instance is ready, both runtimes are warm.
* **Single Attack Surface:** Only port 8080 is exposed externally. The Cube Core REST and SQL APIs cannot be addressed from outside the Cloud Run instance.
* **Simplified IAM:** Eliminates the need to grant `roles/run.invoker` across services.

### Negative Consequences / Risks
* Resource limits (CPU and Memory) must be budgeted across both containers in the Cloud Run service template (e.g., 1 vCPU / 2 GiB for Cube Core, 1 vCPU / 1 GiB for FastMCP).

---

## 6. Related Documents
* [ADR-0001: Why Cube Store Cannot Run on Cloud Run](file:///home/angelo/projects/cube-core-mcp/docs/architecture/adrs/0001_why_cube_store_cannot_run_on_cloud_run.md)
* [ADR-0007: FastMCP Streamable HTTP / OAuth](file:///home/angelo/projects/cube-core-mcp/docs/architecture/adrs/0007_fastmcp_streamable_http_oauth_rfc6750.md)
* [C4 Architecture & Design Context](file:///home/angelo/projects/cube-core-mcp/docs/architecture/c4_architecture_and_design_context.md)
