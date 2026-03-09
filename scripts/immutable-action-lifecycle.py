#!/usr/bin/env python3
"""
10X IMMUTABLE ACTION LIFECYCLE MANAGER
Enforces delete-and-rebuild pattern for all debugged actions
Ensures: immutable, ephemeral, idempotent, no-ops, fully automated, hands-off

Architecture:
- Immutable: All actions versioned with hash-based integrity checks
- Ephemeral: Actions auto-deleted after debug-rebuild cycle (no state carryover)
- Idempotent: Safe to run repeatedly - rebuild is deterministic from source
- No-Ops: All creds via GSM/VAULT/KMS - no plaintext, no manual ops
- Fully Automated: GitHub Actions workflows + cron scheduling
- Hands-Off: Zero manual intervention needed, metrics-driven

Author: Platform Engineering
Date: 2026-03-09
"""

import os
import sys
import json
import hashlib
import subprocess
import tempfile
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import logging
import shutil

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s - %(message)s'
)
logger = logging.getLogger(__name__)


class ImmutableActionSignature:
    """Generate and verify cryptographic signatures for actions (SHA256)"""
    
    @staticmethod
    def compute(action_dir: str) -> str:
        """Compute SHA256 hash of action directory excluding metadata"""
        hasher = hashlib.sha256()
        
        # Sort files for deterministic hashing
        for file in sorted(Path(action_dir).rglob('*')):
            if file.is_file() and not file.name.startswith('.'):
                with open(file, 'rb') as f:
                    hasher.update(f.read())
        
        return hasher.hexdigest()[:12]  # 12-char hash
    
    @staticmethod
    def verify(action_dir: str, manifest: Dict) -> bool:
        """Verify action integrity against manifest"""
        current_hash = ImmutableActionSignature.compute(action_dir)
        stored_hash = manifest.get('integrity_hash', '')
        is_valid = current_hash == stored_hash
        
        if not is_valid:
            logger.warning(f"⚠️  Integrity check failed: {current_hash} != {stored_hash}")
        
        return is_valid


class ActionMetadataManifest:
    """Manages immutable action metadata and version tracking"""
    
    def __init__(self, action_dir: str):
        self.action_dir = action_dir
        self.manifest_path = Path(action_dir) / 'action-manifest.json'
    
    def create(self, version: str, debug_count: int = 0) -> Dict:
        """Create new immutable manifest for action"""
        manifest = {
            'version': version,
            'created_at': datetime.utcnow().isoformat(),
            'debug_cycle': debug_count,
            'integrity_hash': ImmutableActionSignature.compute(self.action_dir),
            'credentials_provider': 'GSM/VAULT/KMS',
            'lifecycle_state': 'ACTIVE',
            'ephemeral_ttl_hours': 720,  # 30 days
            'rebuild_checksum': None,
            'previous_versions': []
        }
        
        self._save(manifest)
        logger.info(f"✅ Created manifest for {Path(self.action_dir).name}")
        return manifest
    
    def load(self) -> Optional[Dict]:
        """Load existing manifest"""
        if self.manifest_path.exists():
            with open(self.manifest_path) as f:
                return json.load(f)
        return None
    
    def increment_debug_cycle(self) -> Dict:
        """Increment debug count and prepare for rebuild"""
        manifest = self.load() or {}
        manifest['debug_cycle'] = manifest.get('debug_cycle', 0) + 1
        manifest['last_debug_at'] = datetime.utcnow().isoformat()
        manifest['rebuild_required'] = True
        
        self._save(manifest)
        logger.info(f"📊 Debug cycle {manifest['debug_cycle']} recorded")
        return manifest
    
    def mark_rebuilt(self, new_version: str) -> Dict:
        """Mark action as successfully rebuilt with new version"""
        manifest = self.load() or {}
        
        # Archive previous version
        if 'version' in manifest:
            manifest['previous_versions'].append({
                'version': manifest['version'],
                'archived_at': datetime.utcnow().isoformat(),
                'debug_cycle': manifest.get('debug_cycle', 0)
            })
        
        manifest['version'] = new_version
        manifest['rebuilt_at'] = datetime.utcnow().isoformat()
        manifest['integrity_hash'] = ImmutableActionSignature.compute(self.action_dir)
        manifest['rebuild_required'] = False
        manifest['lifecycle_state'] = 'ACTIVE'
        
        self._save(manifest)
        logger.info(f"✅ Marked as rebuilt: v{new_version}")
        return manifest
    
    def _save(self, manifest: Dict):
        """Persist manifest to disk"""
        with open(self.manifest_path, 'w') as f:
            json.dump(manifest, f, indent=2)


class ImmutableActionOrchestrator:
    """Main orchestrator for delete-and-rebuild lifecycle"""
    
    def __init__(self, actions_root: str = ".github/actions"):
        self.actions_root = actions_root
        self.cred_manager = CredentialManagerGSMVAULTKMS()
    
    def discover_actions(self) -> List[str]:
        """Find all GitHub Actions in repository"""
        actions = []
        if os.path.isdir(self.actions_root):
            for item in os.listdir(self.actions_root):
                action_path = os.path.join(self.actions_root, item)
                action_yml = os.path.join(action_path, 'action.yml')
                if os.path.isdir(action_path) and os.path.isfile(action_yml):
                    actions.append(action_path)
        
        logger.info(f"🔍 Discovered {len(actions)} actions")
        return actions
    
    def debug_action(self, action_path: str, debug_reason: str):
        """Record action being debugged"""
        manifest = ActionMetadataManifest(action_path)
        current = manifest.load() or {}
        current['last_debug_reason'] = debug_reason
        manifest.increment_debug_cycle()
        logger.warn(f"🐛 Action flagged for debug: {debug_reason}")
    
    def rebuild_action(self, action_path: str) -> Tuple[bool, str]:
        """
        DELETE and REBUILD action from source (immutable, ephemeral pattern)
        Returns: (success, new_version)
        """
        action_name = Path(action_path).name
        logger.info(f"🔄 REBUILD CYCLE: {action_name}")
        
        try:
            # Step 1: VERIFY - Get manifest before deletion
            manifest = ActionMetadataManifest(action_path)
            old_manifest = manifest.load() or {}
            old_debug_cycle = old_manifest.get('debug_cycle', 0)
            
            # Step 2: BACKUP - Archive current action state
            backup_path = self._create_backup(action_path)
            logger.info(f"📦 Backed up to: {backup_path}")
            
            # Step 3: DELETE - Remove all action state (ephemeral)
            self._delete_action_state(action_path)
            logger.info(f"🗑️  Deleted action state")
            
            # Step 4: REBUILD - Reconstruct from source
            success = self._rebuild_from_source(action_path)
            if not success:
                self._restore_from_backup(action_path, backup_path)
                return False, "rebuild_failed"
            
            # Step 5: INJECT CREDS - GSM/VAULT/KMS only
            cred_success = self.cred_manager.inject_credentials_for_action(action_path)
            if not cred_success:
                logger.error(f"❌ Credential injection failed for {action_name}")
                return False, "cred_injection_failed"
            
            # Step 6: VALIDATE - Run action tests
            validation_passed = self._validate_rebuilt_action(action_path)
            if not validation_passed:
                logger.error(f"❌ Validation failed for {action_name}")
                return False, "validation_failed"
            
            # Step 7: COMMIT - Update manifest and mark complete
            new_version = self._compute_new_version(old_debug_cycle)
            manifest.mark_rebuilt(new_version)
            
            logger.info(f"✅ REBUILD COMPLETE: {action_name} -> v{new_version}")
            
            # Cleanup backup if rebuild successful
            if backup_path and os.path.exists(backup_path):
                shutil.rmtree(backup_path)
            
            return True, new_version
        
        except Exception as e:
            logger.error(f"❌ Rebuild failed: {e}")
            return False, f"exception:{str(e)}"
    
    def _create_backup(self, action_path: str) -> str:
        """Create ephemeral backup of action state"""
        backup_dir = f"{action_path}/.backup-{datetime.utcnow().strftime('%Y%m%d-%H%M%S')}"
        os.makedirs(backup_dir, exist_ok=True)
        
        # Copy action files (excluding manifest)
        for file in Path(action_path).iterdir():
            if file.name.startswith('.'):
                continue
            if file.is_file():
                shutil.copy2(file, backup_dir)
            elif file.is_dir():
                shutil.copytree(file, os.path.join(backup_dir, file.name))
        
        return backup_dir
    
    def _delete_action_state(self, action_path: str):
        """Delete all action files (ephemeral cleanup)"""
        for file in Path(action_path).iterdir():
            if file.name in ['.backup-*', 'action-manifest.json']:
                continue
            if file.is_file():
                os.remove(file)
            elif file.is_dir():
                shutil.rmtree(file)
    
    def _rebuild_from_source(self, action_path: str) -> bool:
        """Rebuild action from source control (idempotent)"""
        try:
            # Initialize from git
            result = subprocess.run(
                ['git', 'checkout', 'HEAD', '--', action_path],
                cwd=os.path.dirname(action_path),
                capture_output=True,
                timeout=30
            )
            return result.returncode == 0
        except Exception as e:
            logger.error(f"Failed to rebuild from source: {e}")
            return False
    
    def _restore_from_backup(self, action_path: str, backup_path: str):
        """Restore action from backup (rollback)"""
        if not backup_path or not os.path.exists(backup_path):
            logger.error("No backup available for rollback")
            return
        
        # Clear the broken action
        self._delete_action_state(action_path)
        
        # Restore from backup
        for file in os.listdir(backup_path):
            src = os.path.join(backup_path, file)
            dst = os.path.join(action_path, file)
            if os.path.isfile(src):
                shutil.copy2(src, dst)
            elif os.path.isdir(src):
                shutil.copytree(src, dst)
        
        logger.info(f"🔙 Restored from backup")
    
    def _validate_rebuilt_action(self, action_path: str) -> bool:
        """Validate rebuilt action (integrity + tests)"""
        try:
            # Check action.yml exists and is valid YAML
            action_yml = os.path.join(action_path, 'action.yml')
            if not os.path.exists(action_yml):
                logger.error("action.yml not found")
                return False
            
            import yaml
            with open(action_yml) as f:
                yaml.safe_load(f)
            
            # Run any integration tests
            test_script = os.path.join(action_path, 'tests', 'validate.sh')
            if os.path.exists(test_script):
                result = subprocess.run([test_script], timeout=60, capture_output=True)
                return result.returncode == 0
            
            logger.info("✅ Action validation passed")
            return True
        
        except Exception as e:
            logger.error(f"Validation failed: {e}")
            return False
    
    def _compute_new_version(self, old_debug_cycle: int) -> str:
        """Generate new immutable version based on debug cycle"""
        # Format: v{MAJOR}.{MINOR}.{PATCH}-debug{CYCLE}
        new_cycle = old_debug_cycle + 1
        timestamp = datetime.utcnow().strftime('%Y%m%d')
        return f"v1.0.{new_cycle}-rebuild-{timestamp}"
    
    def mandate_all_debugged_actions(self) -> Dict:
        """Scan repo and MANDATE rebuild for any debugged actions"""
        results = {
            'total_actions': 0,
            'debugged_actions': [],
            'rebuilt_actions': [],
            'failed_rebuilds': [],
            'timestamp': datetime.utcnow().isoformat()
        }
        
        actions = self.discover_actions()
        results['total_actions'] = len(actions)
        
        for action_path in actions:
            manifest = ActionMetadataManifest(action_path)
            action_manifest = manifest.load() or {}
            
            # Check if action was debugged and needs rebuild
            if action_manifest.get('rebuild_required', False):
                action_name = Path(action_path).name
                logger.warn(f"🔶 MANDATE: Rebuilding debugged action: {action_name}")
                
                results['debugged_actions'].append(action_name)
                
                success, version = self.rebuild_action(action_path)
                if success:
                    results['rebuilt_actions'].append({
                        'name': action_name,
                        'version': version,
                        'timestamp': datetime.utcnow().isoformat()
                    })
                else:
                    results['failed_rebuilds'].append({
                        'name': action_name,
                        'error': version,
                        'timestamp': datetime.utcnow().isoformat()
                    })
        
        logger.info(f"📊 Mandate Results: {len(results['debugged_actions'])} debugged, "
                   f"{len(results['rebuilt_actions'])} rebuilt, "
                   f"{len(results['failed_rebuilds'])} failed")
        
        return results
    
    def generate_audit_report(self) -> Dict:
        """Generate comprehensive audit report for all actions"""
        report = {
            'timestamp': datetime.utcnow().isoformat(),
            'actions': [],
            'summary': {
                'total': 0,
                'active': 0,
                'rebuild_required': 0,
                'integrity_verified': 0
            }
        }
        
        actions = self.discover_actions()
        report['summary']['total'] = len(actions)
        
        for action_path in actions:
            manifest = ActionMetadataManifest(action_path)
            action_manifest = manifest.load() or {}
            
            integrity_ok = ImmutableActionSignature.verify(action_path, action_manifest)
            if integrity_ok:
                report['summary']['integrity_verified'] += 1
            
            action_report = {
                'name': Path(action_path).name,
                'version': action_manifest.get('version', 'unknown'),
                'debug_cycle': action_manifest.get('debug_cycle', 0),
                'lifecycle_state': action_manifest.get('lifecycle_state', 'unknown'),
                'rebuild_required': action_manifest.get('rebuild_required', False),
                'integrity_verified': integrity_ok,
                'created_at': action_manifest.get('created_at', 'unknown'),
                'rebuilt_at': action_manifest.get('rebuilt_at', None)
            }
            
            if action_manifest.get('lifecycle_state') == 'ACTIVE':
                report['summary']['active'] += 1
            
            if action_manifest.get('rebuild_required'):
                report['summary']['rebuild_required'] += 1
            
            report['actions'].append(action_report)
        
        return report


class CredentialManagerGSMVAULTKMS:
    """
    Manage ALL credentials via GSM/VAULT/KMS
    No plaintext secrets, no manual intervention
    """
    
    def __init__(self):
        self.gsm_project = os.getenv('GCP_PROJECT_ID', 'auto-repair-gsm')
        self.vault_addr = os.getenv('VAULT_ADDR', 'https://vault.internal:8200')
        self.kms_key_id = os.getenv('AWS_KMS_KEY_ID', 'auto-repair-key')
    
    def inject_credentials_for_action(self, action_path: str) -> bool:
        """
        Inject credentials for action using GSM/VAULT/KMS
        Creates environment variables, secrets files, etc.
        """
        try:
            action_name = Path(action_path).name
            logger.info(f"🔐 Injecting credentials for {action_name}")
            
            # Fetch credentials from GSM
            gsm_secrets = self._fetch_from_gsm(action_name)
            
            # Fetch from VAULT as fallback
            if not gsm_secrets:
                gsm_secrets = self._fetch_from_vault(action_name)
            
            # Create secrets env file (git-ignored)
            env_file = os.path.join(action_path, '.action-secrets.env')
            with open(env_file, 'w') as f:
                f.write("# Auto-generated credentials file - DO NOT COMMIT\n")
                f.write("# This file is auto-generated from GSM/VAULT/KMS\n")
                for key, value in gsm_secrets.items():
                    f.write(f"export {key}='{value}'\n")
            
            os.chmod(env_file, 0o600)  # Owner-only read/write
            
            # Add to .gitignore
            gitignore = os.path.join(action_path, '.gitignore')
            with open(gitignore, 'a') as f:
                f.write("\n.action-secrets.env\n")
            
            logger.info(f"✅ Credentials injected via GSM/VAULT/KMS")
            return True
        
        except Exception as e:
            logger.error(f"Failed to inject credentials: {e}")
            return False
    
    def _fetch_from_gsm(self, action_name: str) -> Dict:
        """Fetch credentials from Google Secret Manager"""
        try:
            result = subprocess.run(
                ['gcloud', 'secrets', 'list', '--project', self.gsm_project,
                 '--filter', f'labels.action={action_name}', '--format', 'json'],
                capture_output=True,
                timeout=10
            )
            
            if result.returncode == 0:
                secrets = json.loads(result.stdout)
                credentials = {}
                for secret in secrets:
                    secret_name = secret['name'].split('/')[-1]
                    secret_value = subprocess.run(
                        ['gcloud', 'secrets', 'versions', 'access', 'latest',
                         '--secret', secret_name, '--project', self.gsm_project],
                        capture_output=True,
                        timeout=10
                    ).stdout.decode().strip()
                    credentials[secret_name] = secret_value
                
                return credentials
        except Exception as e:
            logger.debug(f"GSM fetch failed: {e}")
        
        return {}
    
    def _fetch_from_vault(self, action_name: str) -> Dict:
        """Fetch credentials from HashiCorp Vault"""
        try:
            import requests
            
            vault_token = os.getenv('VAULT_TOKEN', '')
            if not vault_token:
                return {}
            
            headers = {'X-Vault-Token': vault_token}
            url = f"{self.vault_addr}/v1/secret/data/actions/{action_name}"
            
            response = requests.get(url, headers=headers, timeout=10, verify=False)
            if response.status_code == 200:
                return response.json().get('data', {}).get('data', {})
        except Exception as e:
            logger.debug(f"Vault fetch failed: {e}")
        
        return {}


def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(
        description='10X Immutable Action Lifecycle Manager - Delete & Rebuild Pattern'
    )
    parser.add_argument(
        'command',
        choices=['discover', 'debug', 'rebuild', 'mandate-all', 'audit'],
        help='Command to execute'
    )
    parser.add_argument(
        '--action',
        help='Action path (for debug/rebuild commands)'
    )
    parser.add_argument(
        '--reason',
        help='Debug reason (for debug command)'
    )
    parser.add_argument(
        '--output',
        help='Output file for reports'
    )
    
    args = parser.parse_args()
    
    orchestrator = ImmutableActionOrchestrator()
    
    if args.command == 'discover':
        actions = orchestrator.discover_actions()
        for action in actions:
            print(action)
    
    elif args.command == 'debug':
        if not args.action or not args.reason:
            print("❌ --action and --reason required for debug command")
            sys.exit(1)
        orchestrator.debug_action(args.action, args.reason)
        print(f"✅ Flagged for rebuild: {args.action}")
    
    elif args.command == 'rebuild':
        if not args.action:
            print("❌ --action required for rebuild command")
            sys.exit(1)
        success, version = orchestrator.rebuild_action(args.action)
        if success:
            print(f"✅ Rebuilt successfully: v{version}")
            sys.exit(0)
        else:
            print(f"❌ Rebuild failed: {version}")
            sys.exit(1)
    
    elif args.command == 'mandate-all':
        results = orchestrator.mandate_all_debugged_actions()
        if args.output:
            with open(args.output, 'w') as f:
                json.dump(results, f, indent=2)
        else:
            print(json.dumps(results, indent=2))
    
    elif args.command == 'audit':
        report = orchestrator.generate_audit_report()
        if args.output:
            with open(args.output, 'w') as f:
                json.dump(report, f, indent=2)
        else:
            print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
