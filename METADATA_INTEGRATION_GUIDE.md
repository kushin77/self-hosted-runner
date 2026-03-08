# Metadata System Integration Guide

Complete guide for integrating the metadata governance system with various platforms and tools.

---

## Table of Contents

1. [GitHub Actions](#github-actions)
2. [GitLab CI](#gitlab-ci)
3. [Jenkins](#jenkins)
4. [Webhooks & APIs](#webhooks--apis)
5. [Slack Integration](#slack-integration)
6. [Monitoring & Alerting](#monitoring--alerting)
7. [Cloud Storage](#cloud-storage)
8. [Database Integration](#database-integration)

---

## GitHub Actions

### Built-in Integration

The system includes a complete GitHub Actions workflow:

**File:** `.github/workflows/metadata-sync.yml`

```yaml
name: Metadata Validation and Sync
on:
  push:
    paths:
      - 'metadata/**'
      - '.github/workflows/**'
      - 'scripts/**'
  schedule:
    - cron: '0 2 * * *'
```

### Setup Instructions

#### 1. Enable Workflow

The workflow is already configured but requires:

```bash
# 1. Ensure scripts are executable
chmod +x scripts/{manage,validate,visualize,audit}-metadata.sh

# 2. Push to main branch
git add .github/workflows/metadata-sync.yml
git commit -m "enable: metadata sync workflow"
git push origin main

# 3. Go to Actions tab to verify it runs
```

#### 2. Custom Event Triggers

Trigger validation on specific events:

```yaml
# trigger on workflow file changes
on:
  push:
    paths:
      - '.github/workflows/**'
      - 'metadata/**'
  pull_request:
    paths:
      - 'metadata/**'
  workflow_dispatch:

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: ./scripts/validate-metadata.sh
```

#### 3. Conditional Checks

Make validation required:

```yaml
# In repository settings: Settings > Branch protection rules
# Add status check: "Metadata Validation"
# Settings:
# - Require status checks to pass before merging
# - Include administrators
```

#### 4. Artifact Collection

Automatically collect reports:

```yaml
- name: Upload metadata reports
  if: always()
  uses: actions/upload-artifact@v3
  with:
    name: metadata-reports
    path: dependency-reports/
    retention-days: 30
```

#### 5. Integration with Other Workflows

Use metadata in other workflows:

```yaml
# In other workflows
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      # Get risk level of this workflow
      - name: Check deployment risk
        run: |
          RISK=$(jq -r '.workflows[] | select(.id == "production-deploy") | .risk_level' metadata/items.json)
          if [[ "$RISK" == "CRITICAL" ]]; then
            echo "::warning::Running critical workflow, extra caution required"
          fi
          
      # Check dependencies before deployment
      - name: Verify dependencies
        run: |
          jq -r '.dependencies[] | select(.from == "production-deploy")' metadata/dependencies.json
```

---

## GitLab CI

### Setup for GitLab

#### 1. Create GitLab CI Job

```yaml
# .gitlab-ci.yml
metadata_validation:
  stage: validate
  image: ubuntu:latest
  before_script:
    - apt-get update && apt-get install -y jq
  script:
    - ./scripts/validate-metadata.sh
    - ./scripts/audit-metadata.sh verify-compliance
  artifacts:
    reports:
      dotenv: metadata-status.env
    paths:
      - dependency-reports/
    expire_in: 30 days
  only:
    - merge_requests
    - main
  allow_failure: false

metadata_sync:
  stage: deploy
  image: ubuntu:latest
  before_script:
    - apt-get update && apt-get install -y jq git
  script:
    - git config --local user.email "ci@company.com"
    - git config --local user.name "CI System"
    - |
      jq '.last_updated = "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"' metadata/items.json > metadata/items.json.tmp
      mv metadata/items.json.tmp metadata/items.json
    - git add metadata/
    - git diff --quiet && git diff --staged --quiet || git commit -m "chore: sync metadata timestamps"
    - git push https://oauth2:${CI_JOB_TOKEN}@${CI_SERVER_HOST}/${CI_PROJECT_PATH}.git HEAD:${CI_COMMIT_REF_NAME}
  only:
    - main
  when: on_success
```

#### 2. GitLab Container Registry Integration

```yaml
# Publish metadata reports to container registry
publish_metadata:
  stage: deploy
  image: alpine:latest
  script:
    - apk add --no-cache git
    - git clone https://${CI_DEPLOY_USER}:${CI_DEPLOY_PASSWORD}@${CI_SERVER_HOST}/metadata.git
    - cp dependency-reports/* metadata/
    - cd metadata
    - git add . && git commit -m "Update metadata reports [skip ci]" || true
    - git push
  only:
    - main
```

---

## Jenkins

### Jenkins Declarative Pipeline

```groovy
pipeline {
    agent any
    
    environment {
        WORKSPACE_DIR = "${WORKSPACE}"
    }
    
    stages {
        stage('Validate Metadata') {
            steps {
                sh './scripts/validate-metadata.sh'
            }
        }
        
        stage('Check Compliance') {
            steps {
                catchError(buildResult: 'UNSTABLE') {
                    sh './scripts/audit-metadata.sh verify-compliance'
                }
            }
        }
        
        stage('Detect Anomalies') {
            steps {
                sh './scripts/audit-metadata.sh detect-anomalies'
            }
        }
        
        stage('Generate Reports') {
            steps {
                sh './scripts/visualize-dependencies.sh'
            }
        }
    }
    
    post {
        always {
            // Archive reports
            archiveArtifacts artifacts: 'dependency-reports/**', allowEmptyArchive: true
            
            // Publish HTML
            publishHTML([
                reportDir: 'dependency-reports',
                reportFiles: 'dependencies.html',
                reportName: 'Metadata Report'
            ])
        }
        
        failure {
            // Create issue on failure
            sh '''
                ISSUE_TITLE="Metadata validation failed in build ${BUILD_NUMBER}"
                ISSUE_BODY="Automated metadata validation detected issues.
                Check build logs: ${BUILD_URL}"
                
                # Post to issue tracker
                # curl -X POST https://github.com/repo/issues ...
            '''
        }
    }
}
```

### Jenkins Scripted Pipeline

```groovy
node {
    try {
        stage('Checkout') {
            checkout scm
        }
        
        stage('Metadata Validation') {
            sh './scripts/manage-metadata.sh list workflows'
            sh './scripts/validate-metadata.sh'
        }
        
        stage('Build') {
            // Your build steps
            echo "Building..."
        }
        
        stage('Generate Reports') {
            sh './scripts/visualize-dependencies.sh'
            sh './scripts/audit-metadata.sh generate-report'
        }
    } catch (Exception e) {
        currentBuild.result = 'FAILURE'
        echo "Build failed: ${e.message}"
    }
}
```

---

## Webhooks & APIs

### GitHub Webhook Integration

Trigger metadata sync on external events:

```python
# webhook_handler.py
from flask import Flask, request, jsonify
import subprocess
import hmac
import hashlib

app = Flask(__name__)
WEBHOOK_SECRET = os.getenv('WEBHOOK_SECRET')

@app.route('/webhook/metadata', methods=['POST'])
def handle_webhook():
    # Verify signature
    signature = request.headers.get('X-Hub-Signature-256')
    payload = request.get_data()
    
    expected_sig = 'sha256=' + hmac.new(
        WEBHOOK_SECRET.encode(),
        payload,
        hashlib.sha256
    ).hexdigest()
    
    if not hmac.compare_digest(signature, expected_sig):
        return jsonify({'error': 'Unauthorized'}), 401
    
    event = request.json
    
    if event.get('action') == 'opened':
        # Run validation for new PRs
        result = subprocess.run(
            ['./scripts/validate-metadata.sh'],
            capture_output=True,
            text=True
        )
        
        # Post comment to PR
        pr_number = event['pull_request']['number']
        # ... post results as PR comment
    
    return jsonify({'status': 'ok'}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
```

### RESTful API

```python
# api.py
from flask import Flask, jsonify, request
import json

app = Flask(__name__)

@app.route('/api/metadata/items', methods=['GET'])
def get_items():
    """Get all metadata items"""
    with open('metadata/items.json') as f:
        data = json.load(f)
    return jsonify(data)

@app.route('/api/metadata/workflows', methods=['GET'])
def get_workflows():
    """Get workflows with optional filtering"""
    with open('metadata/items.json') as f:
        data = json.load(f)
    
    risk_level = request.args.get('risk_level')
    owner = request.args.get('owner')
    
    workflows = data['workflows']
    
    if risk_level:
        workflows = [w for w in workflows if w.get('risk_level') == risk_level]
    if owner:
        workflows = [w for w in workflows if w.get('owner') == owner]
    
    return jsonify(workflows)

@app.route('/api/metadata/dependencies/<item_id>', methods=['GET'])
def get_dependencies(item_id):
    """Get dependencies for an item"""
    with open('metadata/dependencies.json') as f:
        deps = json.load(f)
    
    item_deps = [d for d in deps['dependencies'] if d['from'] == item_id]
    return jsonify(item_deps)

@app.route('/api/metadata/validate', methods=['POST'])
def validate():
    """Validate metadata"""
    result = subprocess.run(
        ['./scripts/validate-metadata.sh'],
        capture_output=True,
        text=True
    )
    return jsonify({
        'valid': result.returncode == 0,
        'output': result.stdout,
        'errors': result.stderr
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001)
```

---

## Slack Integration

### Slack Bot Commands

```python
# slack_bot.py
from slack_bolt import App
from slack_bolt.adapter.flask import SlackRequestHandler
from flask import Flask
import subprocess
import json

app_flask = Flask(__name__)
app = App(token=os.getenv('SLACK_BOT_TOKEN'), 
          signing_secret=os.getenv('SLACK_SIGNING_SECRET'))

@app.command("/metadata")
def handle_metadata_command(ack, body, respond):
    ack()
    
    command = body.get('text', '').split()[0] if body.get('text') else 'help'
    
    if command == 'list':
        result = subprocess.run(
            ['./scripts/manage-metadata.sh', 'list', 'workflows'],
            capture_output=True,
            text=True
        )
        respond(f"```{result.stdout}```")
    
    elif command == 'status':
        result = subprocess.run(
            ['./scripts/audit-metadata.sh', 'verify-compliance'],
            capture_output=True,
            text=True
        )
        status = "✅ Compliant" if result.returncode == 0 else "❌ Non-compliant"
        respond(f"Compliance Status: {status}\n```{result.stdout}```")
    
    elif command == 'help':
        respond("""
Metadata Governance Bot Commands:
/metadata list - List all workflows
/metadata status - Check compliance
/metadata search <term> - Search items
/metadata report - Generate report
        """)

@app.message("metadata")
def handle_metadata_message(message, say):
    # Handle mentions in channel
    say("Processing metadata request...")

handler = SlackRequestHandler(app)

@app_flask.route("/slack/events", methods=["POST"])
def slack_events():
    return handler.handle(request)
```

### Slack Notifications

```bash
#!/bin/bash
# slack_notify.sh - Send metadata updates to Slack

SLACK_WEBHOOK="${SLACK_WEBHOOK_URL}"

send_notification() {
    local title="$1"
    local message="$2"
    local color="$3"
    
    curl -X POST "$SLACK_WEBHOOK" \
        -H 'Content-Type: application/json' \
        -d '{
            "attachments": [{
                "title": "'$title'",
                "text": "'$message'",
                "color": "'$color'",
                "ts": '$(date +%s)'
            }]
        }'
}

# On validation failure
if ! ./scripts/validate-metadata.sh; then
    send_notification \
        "Metadata Validation Failed" \
        "Automated validation detected issues. Check logs for details." \
        "danger"
fi

# On compliance violation
if ! ./scripts/audit-metadata.sh verify-compliance; then
    send_notification \
        "Compliance Violation" \
        "Metadata compliance check failed. Review required." \
        "warning"
fi

# On successful audit
if ./scripts/audit-metadata.sh verify-compliance; then
    send_notification \
        "Compliance Verified" \
        "All metadata compliance checks passed." \
        "good"
fi
```

---

## Monitoring & Alerting

### Prometheus Metrics

```python
# metrics_exporter.py
from prometheus_client import Counter, Gauge, start_http_server
import subprocess
import json
import time

# Metrics
workflows_total = Gauge('metadata_workflows_total', 'Total workflows')
scripts_total = Gauge('metadata_scripts_total', 'Total scripts')
secrets_total = Gauge('metadata_secrets_total', 'Total secrets')
critical_items = Gauge('metadata_critical_items_total', 'Critical risk items')
validation_failures = Counter('metadata_validation_failures_total', 'Validation failures')
compliance_violations = Gauge('metadata_compliance_violations', 'Compliance violations')

def collect_metrics():
    with open('metadata/items.json') as f:
        items = json.load(f)
    
    workflows_total.set(len(items.get('workflows', [])))
    scripts_total.set(len(items.get('scripts', [])))
    secrets_total.set(len(items.get('secrets', [])))
    
    critical_count = sum(1 for w in items.get('workflows', []) 
                         if w.get('risk_level') == 'CRITICAL')
    critical_items.set(critical_count)
    
    compliance = json.load(open('metadata/compliance.json'))
    compliance_violations.set(compliance.get('violation_count', 0))

if __name__ == '__main__':
    start_http_server(8000)
    while True:
        collect_metrics()
        time.sleep(60)
```

### Grafana Dashboard

```json
{
  "dashboard": {
    "title": "Metadata Governance",
    "panels": [
      {
        "title": "Total Items",
        "targets": [
          {"expr": "metadata_workflows_total"},
          {"expr": "metadata_scripts_total"},
          {"expr": "metadata_secrets_total"}
        ]
      },
      {
        "title": "Critical Items",
        "targets": [
          {"expr": "metadata_critical_items_total"}
        ]
      },
      {
        "title": "Compliance Status",
        "targets": [
          {"expr": "metadata_compliance_violations"}
        ]
      }
    ]
  }
}
```

---

## Cloud Storage

### AWS S3 Integration

```bash
#!/bin/bash
# s3_backup.sh - Backup metadata to S3

BUCKET="metadata-backups"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)

# Backup metadata files
aws s3 cp metadata/ s3://$BUCKET/backup_$TIMESTAMP/ --recursive

# Backup dependency reports
aws s3 cp dependency-reports/ s3://$BUCKET/reports_$TIMESTAMP/ --recursive

# Clean old backups (keep last 30 days)
aws s3 ls s3://$BUCKET/ | while read -r line; do
    createdate=$(echo $line | awk {'print $1" "$2'})
    createdate=$(date -d "$createdate" +%s)
    olderolddate=$(date --date "30 days ago" +%s)
    
    if [[ $createdate -lt $olderolddate ]]; then
        bucket=$(echo $line | awk {'print $4'})
        aws s3 rm s3://$BUCKET/$bucket --recursive
    fi
done
```

### Google Cloud Storage

```bash
#!/bin/bash
# gcs_sync.sh - Sync to GCS

BUCKET="metadata-governance"
PROJECT_ID="my-project"

# Set up authentication
gcloud auth activate-service-account --key-file=$GOOGLE_APPLICATION_CREDENTIALS
gcloud config set project $PROJECT_ID

# Sync metadata
gsutil -m cp -r metadata/* gs://$BUCKET/metadata/

# Sync reports
gsutil -m cp -r dependency-reports/* gs://$BUCKET/reports/

# Set retention
gsutil lifecycle set - gs://$BUCKET/ << 'EOF'
{
  "lifecycle": [
    {
      "action": {"type": "Delete"},
      "condition": {"age": 90}
    }
  ]
}
EOF
```

### Azure Blob Storage

```bash
#!/bin/bash
# azure_sync.sh - Sync to Azure

CONTAINER="metadata"
STORAGE_ACCOUNT="mystorageaccount"

az storage blob upload-batch \
    -d $CONTAINER/metadata \
    -s metadata/ \
    --account-name $STORAGE_ACCOUNT

az storage blob upload-batch \
    -d $CONTAINER/reports \
    -s dependency-reports/ \
    --account-name $STORAGE_ACCOUNT
```

---

## Database Integration

### Store Metadata in PostgreSQL

```sql
-- Create schema
CREATE TABLE metadata_workflows (
    id VARCHAR(255) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    path VARCHAR(255) NOT NULL,
    owner VARCHAR(255) NOT NULL,
    risk_level VARCHAR(50),
    created_at TIMESTAMP,
    last_modified TIMESTAMP
);

CREATE TABLE metadata_dependencies (
    id SERIAL PRIMARY KEY,
    from_id VARCHAR(255),
    to_id VARCHAR(255),
    type VARCHAR(50),
    created_at TIMESTAMP,
    FOREIGN KEY(from_id) REFERENCES metadata_workflows(id),
    FOREIGN KEY(to_id) REFERENCES metadata_workflows(id)
);

CREATE TABLE metadata_audit (
    id SERIAL PRIMARY KEY,
    action VARCHAR(50),
    item_id VARCHAR(255),
    user_id VARCHAR(255),
    timestamp TIMESTAMP,
    details JSONB
);
```

```python
# db_sync.py
import psycopg2
import json
from datetime import datetime

def sync_to_database():
    conn = psycopg2.connect(
        host="localhost",
        database="metadata",
        user="metadata_user",
        password=os.getenv('DB_PASSWORD')
    )
    
    cursor = conn.cursor()
    
    with open('metadata/items.json') as f:
        items = json.load(f)
    
    # Insert workflows
    for workflow in items.get('workflows', []):
        cursor.execute('''
            INSERT INTO metadata_workflows 
            (id, name, path, owner, risk_level, created_at, last_modified)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (id) DO UPDATE SET
                last_modified = EXCLUDED.last_modified
        ''', (
            workflow['id'],
            workflow['name'],
            workflow['path'],
            workflow['owner'],
            workflow['risk_level'],
            workflow['created'],
            workflow['last_modified']
        ))
    
    conn.commit()
    cursor.close()
    conn.close()
```

---

## Best Practices for Integration

### 1. Authentication & Security

```bash
# Use environment variables for secrets
export SLACK_BOT_TOKEN="xoxb-..."
export WEBHOOK_SECRET="secret-..."
export DB_PASSWORD="secure-password"

# Never commit credentials
echo "*.env" >> .gitignore
```

### 2. Error Handling

```bash
#!/bin/bash
set -euo pipefail

trap 'echo "Error on line $LINENO"; send_alert "Metadata sync failed"' ERR

./scripts/validate-metadata.sh || {
    send_alert "Metadata validation failed"
    exit 1
}
```

### 3. Logging & Audit Trail

```bash
# Log all integrations
LOG_FILE="logs/metadata-integrations.log"

log_event() {
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local message="$1"
    echo "[$timestamp] $message" >> "$LOG_FILE"
}

log_event "Integration started: $INTEGRATION_NAME"
log_event "Items processed: $ITEM_COUNT"
log_event "Integration completed: Status OK"
```

### 4. Retry Logic

```bash
# Implement retries for external integrations
retry_command() {
    local max_attempts=3
    local timeout=5
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if eval "$@"; then
            return 0
        fi
        
        echo "Attempt $attempt failed. Retrying in ${timeout}s..."
        sleep $timeout
        ((attempt++))
        timeout=$((timeout * 2))
    done
    
    return 1
}

# Usage
retry_command "curl -X POST $WEBHOOK_URL ..."
```

---

**Last Updated:** March 8, 2026  
**Version:** 1.0.0  
**Maintained By:** Platform Team
