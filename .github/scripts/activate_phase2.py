#!/usr/bin/env python3
"""
Phase 2 Activation: Directly trigger setup-oidc-infrastructure.yml workflow
Using GitHub API (bypasses terminal issues)
"""

import json
import subprocess
import sys
import time
from datetime import datetime

def run_cmd(cmd):
    """Run shell command"""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
        return result.stdout.strip(), result.returncode
    except:
        return None, 1

def main():
    print("=" * 70)
    print("  PHASE 2 ACTIVATION: OIDC/WIF Infrastructure")
    print("=" * 70)
    print()
    
    # Step 1: Get GitHub token
    print("Step 1: Authenticating with GitHub...")
    token_output, rc = run_cmd("gh auth token")
    if rc != 0 or not token_output:
        print("❌ Failed to get GitHub token")
        print("   Run: gh auth login")
        return 1
    token = token_output
    print("✓ GitHub authentication verified")
    print()
    
    # Step 2: Trigger workflow via GitHub API
    print("Step 2: Triggering Phase 2 workflow...")
    
    import urllib.request
    import urllib.error
    
    repo = "kushin77/self-hosted-runner"
    workflow = "setup-oidc-infrastructure.yml"
    url = f"https://api.github.com/repos/{repo}/actions/workflows/{workflow}/dispatches"
    
    payload = {
        "ref": "main",
        "inputs": {
            "gcp_project_id": "auto-detect",
            "aws_account_id": "auto-detect", 
            "vault_address": "https://vault.example.com:8200",
            "vault_namespace": ""
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
            if response.status == 204:
                print("✓ Workflow dispatch successful (HTTP 204)")
            elif response.status == 202:
                print("✓ Workflow dispatch accepted (HTTP 202)")
            else:
                print(f"⚠ Unexpected status: {response.status}")
    
    except urllib.error.HTTPError as e:
        if e.code == 404:
            print(f"❌ Workflow not found: {workflow}")
            return 1
        else:
            print(f"❌ HTTP Error {e.code}: {e.reason}")
            print(f"   {e.read().decode()}")
            return 1
    except Exception as e:
        print(f"❌ Error: {e}")
        return 1
    
    print()
    
    # Step 3: Wait for workflow to appear
    print("Step 3: Waiting for workflow to start...")
    time.sleep(3)
    
    # Step 4: Get latest run
    print("Step 4: Fetching workflow status...")
    runs_output, rc = run_cmd(f"gh run list --workflow={workflow} --limit=1 --json databaseId,status,updatedAt -q '.[0]'")
    
    if rc == 0 and runs_output:
        try:
            run_data = json.loads(runs_output)
            run_id = run_data.get('databaseId')
            status = run_data.get('status', 'unknown')
            print(f"✓ Workflow found: RUN ID {run_id}")
            print(f"  Status: {status}")
            print()
        except:
            print(f"Workflow triggered (status unavailable)")
            print()
    else:
        print("⚠ Could not fetch run status (workflow may still be queuing)")
        print()
    
    # Step 5: Provide monitoring URL
    print("=" * 70)
    print("  PHASE 2 EXECUTION INITIATED")
    print("=" * 70)
    print()
    print("📊 Monitor Progress:")
    print(f"   Dashboard: https://github.com/{repo}/actions")
    print(f"   Workflow:  https://github.com/{repo}/actions/workflows/{workflow}")
    print()
    print("⏱️  Expected Duration: 3-5 minutes")
    print()
    print("✅ What Phase 2 Does:")
    print("   1. Auto-detects GCP Project ID (if gcloud configured)")
    print("   2. Auto-detects AWS Account ID (if aws CLI configured)")
    print("   3. Sets up GCP Workload Identity Federation")
    print("   4. Sets up AWS OIDC Provider & GitHub Role")
    print("   5. Configures Vault JWT Authentication")
    print("   6. Creates 4 GitHub Repository Secrets:")
    print("      • GCP_WIF_PROVIDER_ID")
    print("      • AWS_ROLE_ARN")
    print("      • VAULT_ADDR")
    print("      • VAULT_JWT_ROLE")
    print()
    print("Verify Success:")
    print("   gh secret list --repo kushin77/self-hosted-runner")
    print()
    print("=" * 70)
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
