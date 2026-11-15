# Cross-Cloud Semantic Layer: Execution Plan

This document outlines the compact, step-by-step execution plan for building a serverless, cross-cloud plug-and-play semantic layer using Cube Core, FastMCP, and GCP.

## Phase 1: Infrastructure as Code (Terraform)
* **Storage:** Provision a Google Cloud Storage (GCS) bucket for decoupled Cube Store Parquet storage.
* **Cache Node:** Deploy a single Compute Engine Spot VM (e.g., `e2-medium` with a 30GB PD-Balanced disk) within a Managed Instance Group (target size 1, auto-healing enabled) to run Cube Store in Standalone Mode.
* **Serverless Compute:** Provision two stateless Cloud Run services: one for the Cube Core API and one for the FastMCP Wrapper.
* **Networking:** Configure Direct VPC Egress on the Cloud Run services to allow secure internal routing to the Spot VM’s private IP.
* **Tuning:** Increase Cloud Run concurrency limits and set timeout deadlines to 5 minutes to accommodate LLM processing and BigQuery L1 fallback times.
* **Observability:** Configure Cloud Logging sinks and IAM bindings for the underlying service accounts.

## Phase 2: Semantic Engine & CI/CD
* **Metadata Prep:** Ensure target dbt projects have well-documented metadata (column descriptions and primary keys) in their `manifest.json`.
* **Pipeline Setup:** Create a CI/CD pipeline (e.g., GitHub Actions) triggered by the completion of a dbt Cloud job.
* **Deployment Flow:** Configure the pipeline to fetch the latest `manifest.json`, bake it into the Cube Core Docker image, and deploy the new revision to Cloud Run.

## Phase 3: Custom FastMCP Wrapper (Python)
* **Initialization:** Initialize the FastMCP Python service and lock dependencies using `uv`.
* **Authentication:** Implement Google Workspace OAuth 2.1 validation middleware to secure incoming requests.
* **Translation Layer:** Write logic to convert natural language LLM tool arguments into structured Cube REST API JSON queries (mapping dimensions, measures, and time filters).
* **Context Optimization:** Implement payload compression logic to transform verbose JSON data responses from Cube into token-efficient Markdown tables or CSV strings.
* **Exposure:** Expose the FastMCP wrapper as a remote Server-Sent Events (SSE) endpoint.

## Phase 4: Local Client Proxy Bridge
* **Local Bridge:** Develop a local proxy script or utilize an existing bridge tool (like `mcp-remote`) to connect the local `stdio` stream required by Claude Desktop or Claude Code to the remote Cloud Run SSE endpoint.
* **OAuth Flow:** Configure the proxy to handle the initial Google OAuth flow, explicitly requesting `offline` access to generate a Refresh Token.
* **State Management:** Program the proxy to save the long-lived Refresh Token securely within the user's local operating system keychain.
* **Token Swapping:** Implement silent token swapping in the proxy to intercept LLM requests, exchange expired access tokens for fresh ones using the keychain, and forward the validated HTTP requests to Cloud Run.

## Phase 5: Plug-and-Play Template Rollout
* **Parameterization:** Parameterize all Terraform modules to accept dynamic variables (Project ID, BigQuery datasets, region, VPC network).
* **Auth Documentation:** Document the manual OAuth Consent Screen configuration and Client ID/Secret extraction process for new teams.
* **IAM Documentation:** Document the required cross-project BigQuery IAM roles (`roles/bigquery.dataViewer`, `roles/bigquery.jobUser`) that new teams must grant to the Terraform service account.