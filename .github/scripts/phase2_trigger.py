#!/usr/bin/env python3
"""
Phase 2 Execution Trigger - GitHub Actions Workflow
OIDC/WIF Infrastructure Configuration
"""

import os
import sys
import json
import subprocess
from pathlib import Path

def run_command(cmd, description=""):
    """Execute shell command and return output"""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
        if result.returncode != 0 and description:
            print(f"❌ {description}")
            print(f"   Error: {result.stderr}")
            return None
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        print(f"⏱️  Timeout executing: {description}")
        return None
    except Exception as e:
        print(f"❌ Exception: {e}")
        return None

def get_github_token():
    """Get GitHub token from gh CLI"""
    token = os.environ.get('GITHUB_TOKEN')
    if token:
        return token
    
    # Try to get from gh CLI
    cmd = "gh auth token"
    return run_command(cmd, "Getting GitHub token from gh CLI")

def get_gcp_project():
    """Auto-detect GCP project"""
    return run_command("gcloud config get-value project 2>/dev/null", "Auto-detecting GCP project")

def get_aws_account():
    """Auto-detect AWS account ID"""
    return run_command("aws sts get-caller-identity --query Account --output text 2>/dev/null", "Auto-detecting AWS account")

def trigger_workflow(token, gcp_project, aws_account, vault_addr, vault_ns=""):
    """Trigger Phase 2 workflow via GitHub API"""
    
    import urllib.request
    import urllib.error
    
    repo = "kushin77/self-hosted-runner"
    workflow = "setup-oidc-infrastructure.yml"
    
    url = f"https://api.github.com/repos/{repo}/actions/workflows/{workflow}/dispatches"
    
    payload = {
        "ref": "main",
        "inputs": {
            "gcp_project_id": gcp_project or "YOUR-GCP-PROJECT-ID",
            "aws_account_id": aws_account or "123456789012",
            "vault_address": vault_addr,
            "vault_namespace": vault_ns
        }
    }
    
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28"
    }
    
    try:
        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode('utf-8'),
            headers=headers,
            method='POST'
        )
        
        with urllib.request.urlopen(req, timeout=10) as response:
            if response.status in [202, 204]:
                return True
            else:
                print(f"Unexpected status: {response.status}")
                return False
    
    except urllib.error.HTTPError as e:
        print(f"HTTP Error {e.code}: {e.reason}")
        if e.code == 404:
            print("Workflow or repository not found. Check repo/workflow names.")
        return False
    except Exception as e:
        print(f"Error triggering workflow: {e}")
        return False

def main():
    """Main execution"""
    
    print("═" * 70)
    print("  PHASE 2: OIDC/WIF Configuration - Execution")
    print("═" * 70)
    print()
    
    # Get token
    print("✓ Retrieving GitHub authentication token...")
    token = get_github_token()
    if not token:
        print("❌ Could not get GitHub token. Please run: gh auth login")
        sys.exit(1)
    print("  Token acquired (hidden for security)")
    print()
    
    # Auto-detect cloud credentials
    print("✓ Auto-detecting cloud environment...")
    gcp_project = get_gcp_project()
    aws_account = get_aws_account()
    vault_addr = os.environ.get('VAULT_ADDR', 'https://vault.example.com:8200')
    vault_ns = os.environ.get('VAULT_NAMESPACE', '')
    
    print(f"  GCP Project:   {gcp_project or '(not detected - will use default)'}")
    print(f"  AWS Account:   {aws_account or '(not detected - will use default)'}")
    print(f"  Vault Address: {vault_addr}")
    print(f"  Vault NS:      {vault_ns or '(none)'}")
    print()
    
    # Trigger workflow
    print("═" * 70)
    print("  Triggering Phase 2 Workflow...")
    print("═" * 70)
    print()
    
    if trigger_workflow(token, gcp_project, aws_account, vault_addr, vault_ns):
        print("✅ Workflow triggered successfully!")
        print()
        print("📊 Monitor progress at:")
        print("   https://github.com/kushin77/self-hosted-runner/actions/workflows/setup-oidc-infrastructure.yml")
        print()
        print("⏱️  Expected duration: 3-5 minutes")
        print()
        print("═" * 70)
        print("  PHASE 2 EXECUTION INITIATED")
        print("═" * 70)
        return 0
    else:
        print("❌ Failed to trigger workflow")
        return 1

if __name__ == "__main__":
    sys.exit(main())
