import functions_framework
import google.auth
from google.cloud import build_v1
import json
import base64
import os
import subprocess


@functions_framework.cloud_event
def trigger_credential_rotation(cloud_event):
    """
    Cloud Function triggered by Pub/Sub topic to submit credential rotation Cloud Build job.
    Decodes Pub/Sub message and submits a Cloud Build job for credential rotation.
    """
    # Decode Pub/Sub message
    pubsub_message = base64.b64decode(cloud_event.data["message"]["data"]).decode()
    try:
        message_data = json.loads(pubsub_message)
    except json.JSONDecodeError:
        message_data = {}
    
    # Get environment variables
    PROJECT_ID = os.environ.get("GCP_PROJECT", "nexusshield-prod")
    BUILD_CONFIG = message_data.get("buildConfigPath", "cloudbuild/rotate-credentials-cloudbuild.yaml")
    BRANCH = message_data.get("branch", "main")
    
    print(f"[credential-rotation-function] Submitting build for branch: {BRANCH}, config: {BUILD_CONFIG}")
    
    try:
        # Submit build using gcloud command
        result = subprocess.run(
            [
                "gcloud",
                "builds",
                "submit",
                f"--config={BUILD_CONFIG}",
                f"--project={PROJECT_ID}",
                "--async",
            ],
            capture_output=True,
            text=True,
            timeout=30,
        )
        
        if result.returncode == 0:
            print(f"[credential-rotation-function] ✅ Build submitted successfully")
            print(f"[credential-rotation-function] Output: {result.stdout}")
            return ("Build submitted successfully", 200)
        else:
            print(f"[credential-rotation-function] ❌ Build submission failed")
            print(f"[credential-rotation-function] Error: {result.stderr}")
            return (f"Build submission failed: {result.stderr}", 500)
            
    except Exception as e:
        print(f"[credential-rotation-function] ❌ Exception occurred: {str(e)}")
        return (f"Exception: {str(e)}", 500)
