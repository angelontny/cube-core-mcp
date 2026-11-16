"""Async HTTP Client for Cube Core REST and SQL APIs.

Handles service-to-service GCP ID Token authentication for Cloud Run,
JWT token signing for Cube Core, and NDJSON streaming parsing for /v1/cubesql.
"""

import json
import logging
import time
from typing import Any

import httpx
import jwt
from google.auth.transport.requests import Request
from google.oauth2 import id_token

from cube_fastmcp.config import settings

logger = logging.getLogger("cube_fastmcp.client")


class CubeClientError(Exception):
    """Base exception for Cube Core API failures."""

    def __init__(
        self, message: str, status_code: int | None = None, response_text: str = ""
    ):
        super().__init__(message)
        self.status_code = status_code
        self.response_text = response_text


class CubeClient:
    """Async HTTP client interfacing with Cube Core API on Cloud Run or local container."""

    def __init__(self, base_url: str | None = None, api_secret: str | None = None):
        self.base_url = (base_url or settings.cube_api_url).rstrip("/")
        self.api_secret = api_secret or settings.cube_api_secret
        self._cached_id_token: str | None = None
        self._id_token_expiry: float = 0

    def _get_cube_jwt(self) -> str | None:
        """Generate a signed Cube JWT token if an API secret is configured."""
        if not self.api_secret:
            return None
        now = int(time.time())
        payload = {
            "iat": now,
            "exp": now + 86400,  # 24 hours
        }
        return jwt.encode(payload, self.api_secret, algorithm="HS256")

    def _get_cloud_run_id_token(self) -> str | None:
        """Fetch a GCP ID token for authenticating to Cloud Run services (zero-trust)."""
        if not self.base_url.startswith("https://"):
            return None

        # Return cached token if valid for more than 5 minutes
        now = time.time()
        if self._cached_id_token and now < self._id_token_expiry - 300:
            return self._cached_id_token

        try:
            auth_req = Request()
            token = id_token.fetch_id_token(auth_req, self.base_url)
            self._cached_id_token = token
            self._id_token_expiry = (
                now + 3300
            )  # Google tokens are typically valid for 1 hour
            return token
        except Exception as exc:  # noqa: BLE001
            logger.debug(
                f"Could not fetch Google ID token via ADC (may be running unauthenticated): {exc}"
            )
            return None

    def _build_headers(self) -> dict[str, str]:
        """Construct request headers with Cloud Run ID Token and Cube JWT authorization."""
        headers: dict[str, str] = {
            "Content-Type": "application/json",
            "Accept": "application/json",
        }

        # 1. Cloud Run Zero-Trust Identity Token
        id_tok = self._get_cloud_run_id_token()
        if id_tok:
            headers["Authorization"] = f"Bearer {id_tok}"

        # 2. Cube Core API Secret Token (passed in x-cubejs-token or Authorization if no Cloud Run)
        cube_token = self._get_cube_jwt()
        if cube_token:
            if "Authorization" in headers:
                # Cloud Run uses Authorization header for IAM, pass Cube secret in custom header
                headers["x-cubejs-token"] = cube_token
            else:
                headers["Authorization"] = cube_token

        return headers

    async def get_metadata(self) -> dict[str, Any]:
        """Fetch the semantic schema catalog from GET /cubejs-api/v1/meta."""
        url = f"{self.base_url}/cubejs-api/v1/meta"
        headers = self._build_headers()

        async with httpx.AsyncClient(
            timeout=settings.request_timeout_seconds
        ) as client:
            try:
                response = await client.get(url, headers=headers)
            except httpx.RequestError as exc:
                err_msg = f"{type(exc).__name__}: {exc}" if str(exc) else type(exc).__name__
                raise CubeClientError(
                    f"Network error connecting to Cube Core at {url}: {err_msg}"
                ) from exc

            if response.status_code != 200:
                raise CubeClientError(
                    f"Cube Core returned HTTP {response.status_code} for metadata.",
                    status_code=response.status_code,
                    response_text=response.text,
                )

            return response.json()

    async def load_semantic_query(self, query: dict[str, Any]) -> dict[str, Any]:
        """Execute a structured semantic query via POST /cubejs-api/v1/load."""
        url = f"{self.base_url}/cubejs-api/v1/load"
        headers = self._build_headers()
        body = {"query": query}

        async with httpx.AsyncClient(
            timeout=settings.request_timeout_seconds
        ) as client:
            try:
                response = await client.post(url, headers=headers, json=body)
            except httpx.RequestError as exc:
                err_msg = f"{type(exc).__name__}: {exc}" if str(exc) else type(exc).__name__
                raise CubeClientError(
                    f"Network error executing query against {url}: {err_msg}"
                ) from exc

            if response.status_code != 200:
                raise CubeClientError(
                    f"Query execution failed with HTTP {response.status_code}: {response.text}",
                    status_code=response.status_code,
                    response_text=response.text,
                )

            return response.json()

    async def run_sql_query(
        self, sql: str, timezone: str = "UTC"
    ) -> tuple[list[dict[str, str]], list[list[Any]], dict[str, Any] | None]:
        """Execute an arbitrary SQL query via POST /cubejs-api/v1/cubesql.

        Returns:
            Tuple of (schema, data_rows, used_pre_aggregations)
        """
        url = f"{self.base_url}/cubejs-api/v1/cubesql"
        headers = self._build_headers()
        headers["Accept"] = "application/x-ndjson, application/json"
        body = {"query": sql, "timezone": timezone}

        async with httpx.AsyncClient(
            timeout=settings.request_timeout_seconds
        ) as client:
            try:
                response = await client.post(url, headers=headers, json=body)
            except httpx.RequestError as exc:
                err_msg = f"{type(exc).__name__}: {exc}" if str(exc) else type(exc).__name__
                raise CubeClientError(
                    f"Network error executing SQL against {url}: {err_msg}"
                ) from exc

            if response.status_code != 200:
                raise CubeClientError(
                    f"SQL execution failed with HTTP {response.status_code}: {response.text}",
                    status_code=response.status_code,
                    response_text=response.text,
                )

            # Parse NDJSON response stream
            schema: list[dict[str, str]] = []
            data_rows: list[list[Any]] = []
            used_pre_aggs: dict[str, Any] | None = None

            for line in response.text.splitlines():
                line = line.strip()
                if not line:
                    continue
                try:
                    chunk = json.loads(line)
                    if "schema" in chunk:
                        schema = chunk.get("schema", [])
                        used_pre_aggs = chunk.get("usedPreAggregations")
                    if "data" in chunk:
                        data_rows.extend(chunk.get("data", []))
                except json.JSONDecodeError as err:
                    logger.warning(f"Skipping malformed NDJSON line: {line} ({err})")

            return schema, data_rows, used_pre_aggs

    async def explain_sql_query(self, query: dict[str, Any]) -> dict[str, Any]:
        """Inspect generated SQL and pre-aggregation matches via POST /cubejs-api/v1/sql."""
        url = f"{self.base_url}/cubejs-api/v1/sql"
        headers = self._build_headers()
        body = {"query": query}

        async with httpx.AsyncClient(
            timeout=settings.request_timeout_seconds
        ) as client:
            try:
                response = await client.post(url, headers=headers, json=body)
            except httpx.RequestError as exc:
                err_msg = f"{type(exc).__name__}: {exc}" if str(exc) else type(exc).__name__
                raise CubeClientError(f"Network error contacting {url}: {err_msg}") from exc

            if response.status_code != 200:
                raise CubeClientError(
                    f"SQL explanation failed with HTTP {response.status_code}: {response.text}",
                    status_code=response.status_code,
                    response_text=response.text,
                )

            return response.json()


# Shared singleton client instance
cube_client = CubeClient()
