"""Configuration management for Cube FastMCP service using Pydantic Settings."""

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # Cube Core Connection
    cube_api_url: str = Field(
        default="http://localhost:4000",
        description="Base URL for the Cube Core API service (e.g. Cloud Run service URL).",
    )
    cube_api_secret: str = Field(
        default="",
        description="JWT secret configured in CUBEJS_API_SECRET on Cube Core.",
    )

    # Google OAuth 2.0 (for securing FastMCP endpoint via GoogleProvider)
    google_client_id: str | None = Field(
        default=None,
        description="Google OAuth 2.0 Web Application Client ID.",
    )
    google_client_secret: str | None = Field(
        default=None,
        description="Google OAuth 2.0 Client Secret.",
    )
    fastmcp_public_url: str = Field(
        default="http://localhost:8080",
        description="Public base URL for FastMCP server (e.g. Cloud Run service URL for OAuth).",
    )
    google_auth_enabled: bool = Field(
        default=False,
        description="Whether to enforce Google OAuth authentication on the MCP server.",
    )

    # Server Runtime Configuration
    host: str = Field(
        default="0.0.0.0",
        description="Host interface to bind FastMCP server.",
    )
    port: int = Field(
        default=8080,
        description="Port for Cloud Run or local execution.",
    )
    log_level: str = Field(
        default="INFO",
        description="Logging verbosity level.",
    )
    request_timeout_seconds: float = Field(
        default=120.0,
        description="Timeout for HTTP requests to Cube Core API.",
    )


settings = Settings()
