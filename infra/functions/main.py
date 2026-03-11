"""
Uptime Check Proxy - Validates GSM token and returns health status.
Deployed as Cloud Function to proxy uptime checks for services behind org policies.
"""

import os
import json
from google.cloud import secretmanager
from flask import Request, Response


def validate_bearer_token(auth_header: str, expected_token: str) -> bool:
    """Validate Bearer token format and value."""
    if not auth_header:
        return False
    parts = auth_header.split(" ")
    if len(parts) != 2 or parts[0] != "Bearer":
        return False
    return parts[1] == expected_token


def get_uptime_token_from_gsm(project_id: str, secret_name: str = "uptime-check-token") -> str:
    """Retrieve uptime check token from Secret Manager."""
    try:
        client = secretmanager.SecretManagerServiceClient()
        name = f"projects/{project_id}/secrets/{secret_name}/versions/latest"
        response = client.access_secret_version(request={"name": name})
        return response.payload.data.decode("UTF-8")
    except Exception as e:
        print(f"Error retrieving secret: {e}")
        return ""


def uptime_check_proxy(request: Request) -> Response:
    """
    HTTP Cloud Function to validate uptime check bearer token.
    Returns 200 if token is valid, 401 otherwise.
    """
    project_id = os.getenv("GCP_PROJECT", "nexusshield-prod")
    
    # Get the expected token from GSM
    expected_token = get_uptime_token_from_gsm(project_id)
    if not expected_token:
        return Response(
            json.dumps({"error": "Failed to retrieve token from GSM"}),
            status=500,
            mimetype="application/json"
        )
    
    # Extract uptime token: prefer X-Uptime-Token header to allow caller identity token in Authorization
    uptime_header = request.headers.get("X-Uptime-Token", "")
    auth_header = request.headers.get("Authorization", "")

    # Validate token: prefer X-Uptime-Token, fallback to Authorization header for backward compatibility
    token_valid = False
    if uptime_header:
        token_valid = (uptime_header == expected_token)
    else:
        token_valid = validate_bearer_token(auth_header, expected_token)

    if token_valid:
        return Response(
            json.dumps({
                "status": "healthy",
                "message": "Uptime check passed",
                "path": request.path
            }),
            status=200,
            mimetype="application/json"
        )
    else:
        return Response(
            json.dumps({"error": "Unauthorized"}),
            status=401,
            mimetype="application/json"
        )
