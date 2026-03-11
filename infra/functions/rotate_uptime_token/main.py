import base64
import os
import json
import secrets
from google.cloud import secretmanager
from googleapiclient import discovery
from google.auth import default

PROJECT = os.environ.get('GCP_PROJECT', os.environ.get('GOOGLE_CLOUD_PROJECT'))
TARGET_SERVICES = os.environ.get('ROTATE_TARGET_SERVICES', 'nexus-shield-portal-backend,nexus-shield-portal-frontend').split(',')
SECRET_NAME = os.environ.get('UPTIME_SECRET_NAME', 'uptime-check-token')


def generate_token(length=48):
    return secrets.token_urlsafe(length)[:48]


def add_secret_version(project_id, secret_id, payload):
    client = secretmanager.SecretManagerServiceClient()
    parent = f"projects/{project_id}/secrets/{secret_id}"
    response = client.add_secret_version(request={"parent": parent, "payload": {"data": payload.encode('utf-8')}})
    return response.name


def update_cloud_run_service(project_id, region, service_name):
    # Patch the service to reference the latest secret version for UPTIME_CHECK_TOKEN
    # This will create a new revision with the same spec but secret reference set to latest
    credentials, _ = default()
    run = discovery.build('run', 'v1', credentials=credentials, cache_discovery=False)
    service_full = f"projects/{project_id}/locations/{region}/services/{service_name}"
    # Get existing service
    service = run.projects().locations().services().get(name=service_full).execute()
    # Modify revision template env to include secret ref
    spec = service.setdefault('spec', {})
    template = spec.setdefault('template', {})
    spec_containers = template.setdefault('spec', {}).setdefault('containers', [])
    if not spec_containers:
        raise RuntimeError('No containers found in Cloud Run service spec')
    env = spec_containers[0].setdefault('env', [])
    # Set or replace UPTIME_CHECK_TOKEN env var to valueFrom.secretKeyRef
    found = False
    for e in env:
        if e.get('name') == 'UPTIME_CHECK_TOKEN':
            e.pop('value', None)
            e['valueFrom'] = {'secretKeyRef': {'secret': SECRET_NAME, 'version': 'latest'}}
            found = True
            break
    if not found:
        env.append({'name': 'UPTIME_CHECK_TOKEN', 'valueFrom': {'secretKeyRef': {'secret': SECRET_NAME, 'version': 'latest'}}})

    # Patch the service
    body = {'spec': service['spec']}
    request = run.projects().locations().services().patch(name=service_full, body=body)
    resp = request.execute()
    return resp


def rotate(event, context):
    """Pub/Sub-triggered Cloud Function entrypoint."""
    region = os.environ.get('FUNCTION_REGION', 'us-central1')
    project_id = PROJECT
    token = generate_token()
    add_name = add_secret_version(project_id, SECRET_NAME, token)

    results = {'secret_version': add_name, 'service_updates': []}
    for svc in TARGET_SERVICES:
        svc = svc.strip()
        if not svc:
            continue
        try:
            resp = update_cloud_run_service(project_id, region, svc)
            results['service_updates'].append({'service': svc, 'status': 'patched'})
        except Exception as e:
            results['service_updates'].append({'service': svc, 'error': str(e)})

    print(json.dumps(results))
    return results
