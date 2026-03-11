#!/usr/bin/env python3
"""
Create uptime checks via Google Cloud Monitoring API with Authorization headers.
Uses GSM secret for auth token.
"""

import json
import os
import sys
from typing import Dict

from google.api_core import retry
from google.cloud import monitoring_v3, secretmanager


class UptimeCheckCreator:
    def __init__(self, project: str):
        self.project = project
        self.client = monitoring_v3.UptimeCheckServiceClient()
        self.secret_client = secretmanager.SecretManagerServiceClient()

    def get_token_from_gsm(self, secret_id: str) -> str:
        """Retrieve the latest token from Google Secret Manager."""
        secret_name = self.secret_client.secret_version_path(
            self.project, secret_id, "latest"
        )
        response = self.secret_client.access_secret_version(request={"name": secret_name})
        return response.payload.data.decode("UTF-8")

    def create_uptime_check(
        self,
        display_name: str,
        host: str,
        path: str,
        headers: Dict[str, str],
        period_seconds: int = 60,
        timeout_seconds: int = 10,
    ) -> str:
        """Create an HTTP uptime check with custom headers."""
        project_name = f"projects/{self.project}"

        http_check = {
            "path": path,
            "port": 443,
            "request_method": monitoring_v3.UptimeCheckConfig.HttpCheck.RequestMethod.GET,
            "use_ssl": True,
            "headers": headers,
        }

        monitored_resource = {
            "type": "uptime_url",
            "labels": {"host": host},
        }

        uptime_check_config = monitoring_v3.UptimeCheckConfig(
            display_name=display_name,
            monitored_resource=monitored_resource,
            http_check=http_check,
            period={"seconds": period_seconds},
            timeout={"seconds": timeout_seconds},
        )

        try:
            config = self.client.create_uptime_check_config(
                name=project_name, uptime_check_config=uptime_check_config
            )
            print(f"Created uptime check: {config.name}")
            return config.name
        except Exception as e:
            if "already exists" not in str(e):
                raise
            print(f"Uptime check '{display_name}' already exists; skipping")
            return None

    def create_checks_for_services(self, token: str) -> None:
        """Create all uptime checks."""
        headers = {"Authorization": f"Bearer {token}"}

        checks = [
            {
                "display_name": "nexus-backend-health",
                "host": "nexus-shield-portal-backend-2tqp6t4txq-uc.a.run.app",
                "path": "/health",
            },
            {
                "display_name": "nexus-backend-status",
                "host": "nexus-shield-portal-backend-2tqp6t4txq-uc.a.run.app",
                "path": "/api/v1/status",
            },
            {
                "display_name": "nexus-frontend",
                "host": "nexus-shield-portal-frontend-2tqp6t4txq-uc.a.run.app",
                "path": "/",
            },
        ]

        for check in checks:
            self.create_uptime_check(
                display_name=check["display_name"],
                host=check["host"],
                path=check["path"],
                headers=headers,
                period_seconds=60,  # API uses 60, 120, 300, 900, 3600
                timeout_seconds=10,
            )


def main():
    project = os.getenv("PROJECT", "nexusshield-prod")
    secret_id = os.getenv("SECRET_ID", "uptime-check-token")

    creator = UptimeCheckCreator(project)
    token = creator.get_token_from_gsm(secret_id)
    creator.create_checks_for_services(token)
    print("[create-uptime-checks] All checks created or already exist")


if __name__ == "__main__":
    main()
