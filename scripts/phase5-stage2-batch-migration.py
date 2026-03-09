#!/usr/bin/env python3
"""
Phase 5 Stage 2 Batch: Credential Action Integration
Migrates a specific batch of workflows to use ephemeral credentials
"""

import re
import yaml
from pathlib import Path
from collections import defaultdict
import sys

# Define batches - selected workflows with actual NON-GITHUB_TOKEN secrets to migrate
BATCHES = {
    'batch1': [
        # Batch 1: Low-complexity, non-critical (1-2 secrets, utility/observability)
        'operational-health-dashboard.yml',  # MINIO_HOST (1)
        'observability-e2e.yml',  # PAGERDUTY_SERVICE_KEY, SLACK_WEBHOOK_URL (2)
        'secret-validator-observability.yml',  # PAGERDUTY_SERVICE_KEY, SLACK_WEBHOOK_URL (2)
        'secrets-health-dashboard.yml',  # SLACK_WEBHOOK_URL (1)
        'secrets-health.yml',  # DEPLOY_SSH_KEY, RUNNER_MGMT_TOKEN (2)
        'rotation_schedule.yml',  # AWS_REGION (1)
        'release.yml',  # PYPI_TOKEN (1)
        'push-image-to-registry.yml',  # REGISTRY_ORG (1)
        'ci-images.yml',  # REGISTRY_HOST, REGISTRY_USERNAME (2)
        'build.yml',  # GPG_KEY_ID, GPG_PRIVATE_KEY (2)
    ],
    'batch2': [
        # Batch 2: Medium-complexity (2-4 secrets, configuration/rotation/credentials)
        'ephemeral-secret-provisioning.yml',  # VAULT_ADDR, VAULT_NAMESPACE (2)
        'secret-rotation-mgmt-token.yml',  # RUNNER_MGMT_TOKEN (1)
        'revoke-runner-mgmt-token.yml',  # GCP_PROJECT_ID, GCP_SERVICE_ACCOUNT_KEY, RUNNER_MGMT_TOKEN (3)
        'revoke-deploy-ssh-key.yml',  # ADMIN_SSH_KEY, DEPLOY_SSH_KEY, GCP_PROJECT_ID (3)
        'revoke-keys.yml',  # EXPOSED_AWS_KEY_IDS, EXPOSED_GCP_SA_EMAIL, EXPOSED_VAULT_ROLE_IDS (3)
        'phase3-automated-deploy.yml',  # GCP_SERVICE_ACCOUNT_EMAIL, GCP_WORKLOAD_IDENTITY_PROVIDER (2)
        'phase3-bootstrap-wip.yml',  # GCP_SERVICE_ACCOUNT_EMAIL, GOOGLE_CREDENTIALS (2)
        'deploy.yml',  # AWS_REGION, GCP_PROJECT_ID, VAULT_ADDR, VAULT_TOKEN (4)
    ],
    'batch3': [
        # Batch 3: High-complexity (4+ secrets, infrastructure/GSM/orchestration)
        'gcp-gsm-breach-recovery.yml',  # GCP creds (4)
        'gcp-gsm-rotation.yml',  # GCP creds (3)
        'gcp-gsm-sync-secrets.yml',  # AWS/GCP/Vault/Slack (8)
        'hands-off-health-deploy.yml',  # AWS/GCP/Vault (5)
        'store-leaked-to-gsm-and-remove.yml',  # GCP (3)
        'store-slack-to-gsm.yml',  # GCP, Slack (4)
        'terraform-phase2-drift-detection.yml',  # TF config (8)
        'terraform-phase2-final-plan-apply.yml',  # TF config (7)
        'terraform-phase2-post-deploy-validation.yml',  # TF config (8)
        'secrets-orchestrator-multi-layer.yml',  # AWS/GCP/Vault (8)
    ],
}

class WorkflowCredentialIntegrator:
    def __init__(self, workflow_dir=".github/workflows", batch='batch1'):
        self.workflow_dir = Path(workflow_dir)
        self.batch = batch
        self.target_workflows = set(BATCHES.get(batch, []))
        self.modified = []
        self.failed = []
        self.stats = defaultdict(int)

    def extract_secrets_from_text(self, text):
        """Extract all secret references (handles ${{ secrets.NAME ...}})"""
        # Match: secrets.NAME where NAME is alphanumeric + underscore
        pattern = r'secrets\.([A-Za-z_][A-Za-z0-9_]*)'
        matches = re.findall(pattern, text)
        # Only keep matches that are in ${{ }} context (double-check)
        return sorted(set(m for m in matches if '${{' in text and 'secrets.' + m in text))

    def migrate_workflow_file(self, filepath):
        """Migrate single workflow file"""
        try:
            # Read raw content
            with open(filepath, 'r') as f:
                content = f.read()
            
            # Extract secrets
            secrets = self.extract_secrets_from_text(content)
            
            if not secrets:
                return 'no_secrets'
            
            # Skip if only GITHUB_TOKEN
            non_auto = [s for s in secrets if s != 'GITHUB_TOKEN']
            if not non_auto:
                return 'github_token_only'
            
            # Parse file for jobs structure
            try:
                workflow = yaml.safe_load(content)
            except:
                return 'yaml_invalid'
            
            if not workflow or 'jobs' not in workflow:
                return 'no_jobs'
            
            # Build credential action YAML strings
            cred_steps = []
            replacements = []
            
            for secret in non_auto:
                step_id = f"'{secret.lower()}'"
                cred_step = f"""      - name: Get Credential [{secret}]
        id: cred_{secret.lower()}
        uses: kushin77/get-ephemeral-credential@v1
        with:
          credential-name: {secret}
          retrieve-from: 'auto'
          cache-ttl: 600
          audit-log: true"""
                
                cred_steps.append(cred_step)
                
                # Plan replacements
                old_ref = f"${{{{ secrets.{secret} }}}}"
                new_ref = f"${{{{ steps.cred_{secret.lower()}.outputs.credential }}}}"
                replacements.append((old_ref, new_ref))
            
            # Build modified content
            modified = content
            
            # Add credential steps before first "run:" command
            run_pattern = re.compile(r'^(\s+)run:', re.MULTILINE)
            match = run_pattern.search(modified)
            
            if match:
                indent = match.group(1)
                insertion_point = match.start()
                cred_block = '\n'.join(cred_steps) + '\n\n'
                modified = modified[:insertion_point] + cred_block + modified[insertion_point:]
            
            # Replace secret references
            for old_ref, new_ref in replacements:
                modified = modified.replace(old_ref, new_ref)
            
            # Validate YAML
            try:
                yaml.safe_load(modified)
            except:
                return 'yaml_invalid_after'
            
            # Write back
            with open(filepath, 'w') as f:
                f.write(modified)
            
            self.modified.append(filepath.name)
            self.stats['modified'] += 1
            return 'migrated'
        
        except Exception as e:
            self.failed.append((filepath.name, str(e)))
            self.stats['failed'] += 1
            return f'error: {str(e)[:30]}'

    def migrate_batch(self):
        """Migrate only workflows in the current batch"""
        print(f"\n{'='*60}")
        print(f"Phase 5 Stage 2: {self.batch.upper()} Workflow Migration")
        print(f"{'='*60}\n")
        
        workflows = sorted(self.workflow_dir.glob("*.yml"))
        batch_workflows = [w for w in workflows if w.name in self.target_workflows]
        
        print(f"Processing {len(batch_workflows)} target workflows:\n")
        
        for wf in batch_workflows:
            result = self.migrate_workflow_file(wf)
            
            status_map = {
                'migrated': '✅',
                'no_secrets': '⏭️',
                'github_token_only': '⏭️',
                'yaml_invalid': '⚠️',
                'no_jobs': '⏭️',
            }
            
            symbol = status_map.get(result, '❌')
            print(f"{symbol} {wf.name}: {result}")
            self.stats[result] += 1
        
        # Check for missing workflows
        found_names = {w.name for w in batch_workflows}
        missing = self.target_workflows - found_names
        if missing:
            print(f"\n⚠️  Not found (skipped): {', '.join(sorted(missing))}")
        
        # Report
        print(f"\n{'='*60}")
        print(f"Summary ({self.batch.upper()})")
        print(f"{'='*60}\n")
        print(f"Target workflows: {len(self.target_workflows)}")
        print(f"Found: {len(batch_workflows)}")
        print(f"Modified: {self.stats['modified']}")
        print(f"Failed: {self.stats['failed']}")
        print(f"Skipped: {len(batch_workflows) - self.stats['modified'] - self.stats['failed']}")
        
        if self.failed:
            print(f"\nFailed workflows:")
            for name, error in self.failed:
                print(f"  - {name}: {error}")
        
        print(f"\n✅ {self.batch.upper()} Migration Complete")
        print(f"Modified workflows: {self.stats['modified']}")
        print(f"Ready for commit and testing\n")
        
        return self.stats['modified'] > 0


if __name__ == '__main__':
    batch = sys.argv[1] if len(sys.argv) > 1 else 'batch1'
    
    if batch not in BATCHES:
        print(f"Unknown batch: {batch}")
        print(f"Available batches: {', '.join(sorted(BATCHES.keys()))}")
        sys.exit(1)
    
    integrator = WorkflowCredentialIntegrator(batch=batch)
    success = integrator.migrate_batch()
    sys.exit(0 if success else 1)
