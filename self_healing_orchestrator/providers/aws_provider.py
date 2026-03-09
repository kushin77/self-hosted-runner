"""AWS Secrets Manager provider implementation.

Uses boto3 library to access AWS Secrets Manager.
Credentials are assumed to be available from AWS SDK standard sources
(environment variables, IAM role, ~/.aws/credentials, etc.).
"""
import os
import logging
from typing import Optional

logger = logging.getLogger(__name__)

try:
    import boto3
    HAS_BOTO3 = True
except ImportError:
    HAS_BOTO3 = False


class AWSSecretsManagerProvider:
    """Use AWS Secrets Manager for secret storage and retrieval."""

    def __init__(self, region: Optional[str] = None):
        self.region = region or os.environ.get("AWS_REGION", "us-east-1")
        
        if not HAS_BOTO3:
            raise ImportError("boto3 library required for AWS Secrets Manager; install with: pip install boto3")
        
        self.client = boto3.client("secretsmanager", region_name=self.region)

    def get_secret(self, name: str) -> str:
        """Retrieve a secret from AWS Secrets Manager.
        
        Args:
            name: Secret name
        
        Returns:
            Secret value as string
        """
        try:
            response = self.client.get_secret_value(SecretId=name)
            if "SecretString" in response:
                return response["SecretString"]
            else:
                return response["SecretBinary"].decode("utf-8")
        except Exception as e:
            logger.exception("Failed to retrieve secret from AWS Secrets Manager: %s", name)
            raise RuntimeError(f"AWS Secrets Manager retrieval failed: {e}")

    def put_secret(self, name: str, value: str) -> None:
        """Store a secret in AWS Secrets Manager."""
        try:
            # Try update first; if secret doesn't exist, create it
            try:
                self.client.update_secret(SecretId=name, SecretString=value)
            except self.client.exceptions.ResourceNotFoundException:
                self.client.create_secret(Name=name, SecretString=value)
        except Exception as e:
            logger.exception("Failed to store secret in AWS Secrets Manager: %s", name)
            raise RuntimeError(f"AWS Secrets Manager storage failed: {e}")

    def rotate_secret(self, name: str) -> str:
        """Rotate a secret in AWS Secrets Manager."""
        # For rotation, try to trigger automatic rotation if configured
        try:
            self.client.rotate_secret(SecretId=name)
        except Exception as e:
            logger.warning("Could not trigger automatic rotation for %s: %s", name, e)
        # Return current value
        return self.get_secret(name)


__all__ = ["AWSSecretsManagerProvider"]
