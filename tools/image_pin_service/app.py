from flask import Flask, request, jsonify
import google.auth
from googleapiclient.discovery import build
import os

app = Flask(__name__)

# Environment:
# - PROJECT_ID: GCP project
# - LOCATION: region (e.g., us-central1)

PROJECT_ID = os.environ.get('PROJECT_ID')
LOCATION = os.environ.get('LOCATION', 'us-central1')


def get_clients():
    creds, _ = google.auth.default()
    ar = build('artifactregistry', 'v1', credentials=creds, cache_discovery=False)
    run = build('run', 'v1', credentials=creds, cache_discovery=False)
    return ar, run


def patch_cloud_run_service(service_name, new_image):
    _, run = get_clients()
    name = f'projects/{PROJECT_ID}/locations/{LOCATION}/services/{service_name}'
    svc = run.projects().locations().services().get(name=name).execute()
    try:
        containers = svc['spec']['template']['spec']['containers']
        containers[0]['image'] = new_image
    except Exception:
        return False, 'cannot patch container image'
    updated = run.projects().locations().services().replaceService(name=name, body=svc).execute()
    return True, updated


@app.route('/pin', methods=['POST'])
def pin():
    data = request.get_json() or {}
    repository = data.get('repository')
    image_name = data.get('image_name')
    service_name = data.get('service_name')
    tag = data.get('tag', 'latest')
    if not (repository and image_name and service_name):
        return jsonify({'error': 'missing repository, image_name, or service_name'}), 400

    digest = data.get('digest')
    if digest:
        new_image = f'us-central1-docker.pkg.dev/{PROJECT_ID}/{repository}/{image_name}@{digest}'
    else:
        new_image = f'us-central1-docker.pkg.dev/{PROJECT_ID}/{repository}/{image_name}:{tag}'

    ok, resp = patch_cloud_run_service(service_name, new_image)
    if not ok:
        return jsonify({'error': resp}), 500
    return jsonify({'status': 'pinned', 'service': service_name, 'image': new_image}), 200


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
