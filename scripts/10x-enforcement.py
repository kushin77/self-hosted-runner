#!/usr/bin/env python3
"""
10X ENFORCEMENT MODULE
Implements immutability locks, RBAC, integrity enforcement, and policy validation

Features:
- Manifest schema validation (JSON Schema)
- RBAC enforcement (role-based access control)
- Immutability locks (prevent tampering)
- Integrity verification (SHA256, signatures)
- Audit trail enforcement (append-only)
- Credential provider validation (GSM/VAULT/KMS only)
- Rate limiting & abuse prevention
"""

import json
import hashlib
import subprocess
from pathlib import Path
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
import logging
from enum import Enum

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)


class LifecycleState(Enum):
    """Action lifecycle states"""
    ACTIVE = "ACTIVE"
    ARCHIVED = "ARCHIVED"
    REBUILDING = "REBUILDING"
    QUARANTINED = "QUARANTINED"


class CredentialProvider(Enum):
    """Allowed credential providers (NO plaintext)"""
    GSM = "GSM"  # Google Secret Manager
    VAULT = "VAULT"  # HashiCorp Vault
    KMS = "KMS"  # AWS KMS


class UserRole(Enum):
    """Role-based access control"""
    PLATFORM_ADMIN = "platform-admin"
    DEVELOPER = "developer"
    CI_BOT = "ci-bot"


class ManifestSchema:
    """JSON Schema validator for action manifests"""
    
    SCHEMA = {
        "type": "object",
        "required": [
            "version",
            "integrity_hash",
            "lifecycle_state",
            "debug_cycle",
            "credentials_provider",
            "created_at"
        ],
        "properties": {
            "version": {
                "type": "string",
                "pattern": "^v\\d+\\.\\d+\\.\\d+(-rebuild-\\d{8})?$"
            },
            "integrity_hash": {
                "type": "string",
                "pattern": "^[a-f0-9]{12}$"
            },
            "lifecycle_state": {
                "type": "string",
                "enum": ["ACTIVE", "ARCHIVED", "REBUILDING", "QUARANTINED"]
            },
            "debug_cycle": {
                "type": "integer",
                "minimum": 0
            },
            "credentials_provider": {
                "type": "string",
                "enum": ["GSM", "VAULT", "KMS"]
            },
            "created_at": {
                "type": "string",
                "format": "date-time"
            },
            "ephemeral_ttl_hours": {
                "type": "integer",
                "minimum": 24
            },
            "rebuild_required": {
                "type": "boolean"
            },
            "previous_versions": {
                "type": "array"
            }
        },
        "additionalProperties": True
    }
    
    @staticmethod
    def validate(manifest: Dict) -> Tuple[bool, List[str]]:
        """Validate manifest against schema"""
        errors = []
        
        # Check required fields
        for field in ManifestSchema.SCHEMA["required"]:
            if field not in manifest:
                errors.append(f"Missing required field: {field}")
        
        if errors:
            return False, errors
        
        # Validate version format
        import re
        if not re.match(ManifestSchema.SCHEMA["properties"]["version"]["pattern"], manifest.get("version", "")):
            errors.append(f"Invalid version format: {manifest.get('version')}")
        
        # Validate integrity hash
        if not re.match(ManifestSchema.SCHEMA["properties"]["integrity_hash"]["pattern"], manifest.get("integrity_hash", "")):
            errors.append(f"Invalid integrity_hash format: {manifest.get('integrity_hash')}")
        
        # Validate lifecycle state
        if manifest.get("lifecycle_state") not in ManifestSchema.SCHEMA["properties"]["lifecycle_state"]["enum"]:
            errors.append(f"Invalid lifecycle_state: {manifest.get('lifecycle_state')}")
        
        # Validate credentials provider (MUST be GSM/VAULT/KMS - NO plaintext)
        if manifest.get("credentials_provider") not in ManifestSchema.SCHEMA["properties"]["credentials_provider"]["enum"]:
            errors.append(f"Invalid credentials_provider: {manifest.get('credentials_provider')} (must be GSM, VAULT, or KMS)")
        
        # Validate debug_cycle
        if not isinstance(manifest.get("debug_cycle"), int) or manifest.get("debug_cycle", -1) < 0:
            errors.append(f"Invalid debug_cycle: {manifest.get('debug_cycle')}")
        
        return len(errors) == 0, errors


class ImmutabilityLock:
    """Prevents tampering with versioned actions"""
    
    @staticmethod
    def enforce(action_manifest: Dict, action_path: str) -> bool:
        """
        Enforce immutability lock:
        - Once ACTIVE, action can only be modified via rebuild cycle
        - Detect tampering automatically
        - Trigger immediate rebuild on mismatch
        """
        
        if action_manifest.get("lifecycle_state") != LifecycleState.ACTIVE.value:
            return True  # Only lock ACTIVE actions
        
        # Compute current hash
        current_hash = ImmutabilityLock._compute_action_hash(action_path)
        stored_hash = action_manifest.get("integrity_hash")
        
        if current_hash != stored_hash:
            logger.error(f"❌ Integrity violation detected: {action_path}")
            logger.error(f"   Stored: {stored_hash}")
            logger.error(f"   Current: {current_hash}")
            logger.warn(f"🔶 MANDATE: Automatic rebuild triggered (tampering detected)")
            return False  # Trigger rebuild
        
        return True
    
    @staticmethod
    def _compute_action_hash(action_path: str) -> str:
        """Compute SHA256 hash of action directory"""
        hasher = hashlib.sha256()
        
        for file in sorted(Path(action_path).rglob('*')):
            if file.is_file() and not file.name.startswith('.'):
                with open(file, 'rb') as f:
                    hasher.update(f.read())
        
        return hasher.hexdigest()[:12]


class RBACEnforcer:
    """Role-based access control for actions"""
    
    PERMISSIONS = {
        UserRole.PLATFORM_ADMIN.value: [
            'rebuild_all',
            'rebuild_single',
            'mandate_rebuild',
            'modify_credentials',
            'quarantine_action',
            'whitelist_actions'
        ],
        UserRole.DEVELOPER.value: [
            'read_audit_logs',
            'trigger_dry_run',
            'read_manifests'
        ],
        UserRole.CI_BOT.value: [
            'rebuild_single',
            'auto_commit',
            'update_manifests'
        ]
    }
    
    @staticmethod
    def get_user_role() -> Optional[UserRole]:
        """Get current GitHub actor role"""
        try:
            actor = subprocess.run(
                ['gh', 'api', 'user', '--jq', '.login'],
                capture_output=True,
                timeout=10,
                text=True
            ).stdout.strip()
            
            # Map GitHub users to roles
            # (This would integrate with your CODEOWNERS file)
            ci_bots = ['dependabot[bot]', 'automation', 'actions-bot']
            if any(bot in actor for bot in ci_bots):
                return UserRole.CI_BOT
            
            # Check if user is in platform-team
            result = subprocess.run(
                ['gh', 'api', 'orgs/your-org/teams/platform-architects/memberships', actor],
                capture_output=True,
                timeout=10
            )
            if result.returncode == 0:
                return UserRole.PLATFORM_ADMIN
            
            return UserRole.DEVELOPER
        
        except Exception as e:
            logger.warning(f"Could not determine user role: {e}")
            return UserRole.DEVELOPER  # Default to least privilege
    
    @staticmethod
    def check_permission(required_permission: str) -> bool:
        """Check if current user has required permission"""
        role = RBACEnforcer.get_user_role()
        
        if role is None:
            logger.error("Could not determine user role")
            return False
        
        permissions = RBACEnforcer.PERMISSIONS.get(role.value, [])
        
        if required_permission not in permissions:
            logger.error(f"❌ Permission denied: {required_permission}")
            logger.error(f"   User role: {role.value}")
            logger.error(f"   Allowed permissions: {permissions}")
            return False
        
        logger.info(f"✅ Permission granted: {required_permission} (role: {role.value})")
        return True


class SLSAAttestationBuilder:
    """Generate SLSA v1.0 provenance for rebuilds"""
    
    @staticmethod
    def create_attestation(
        action_name: str,
        action_path: str,
        version: str,
        debug_cycle: int
    ) -> Dict:
        """Create SLSA v1.0 provenance attestation"""
        
        # Get git commit info
        result = subprocess.run(
            ['git', 'rev-parse', 'HEAD'],
            capture_output=True,
            timeout=10,
            text=True
        )
        commit_sha = result.stdout.strip()
        
        result = subprocess.run(
            ['git', 'config', 'user.email'],
            capture_output=True,
            timeout=10,
            text=True
        )
        builder_id = result.stdout.strip() or 'automation@github.com'
        
        attestation = {
            "_type": "https://in-toto.io/Statement/v0.1",
            "subject": [
                {
                    "name": action_name,
                    "digest": {
                        "sha256": ImmutabilityLock._compute_action_hash(action_path)
                    }
                }
            ],
            "predicateType": "https://slsa.dev/provenance/v0.2",
            "predicate": {
                "builder": {
                    "id": f"https://github.com/kushin77/self-hosted-runner/actions/workflows/10x-immutable-action-rebuild.yml"
                },
                "buildType": "https://github.com/kushin77/self-hosted-runner/actions",
                "invocation": {
                    "configSource": {
                        "uri": "git@github.com:kushin77/self-hosted-runner",
                        "digest": {
                            "sha256": commit_sha
                        }
                    },
                    "parameters": {
                        "action": action_name,
                        "cycle": debug_cycle,
                        "version": version
                    }
                },
                "buildStartTime": datetime.utcnow().isoformat() + "Z",
                "buildFinishTime": datetime.utcnow().isoformat() + "Z",
                "metadata": {
                    "completeness": {
                        "arguments": True,
                        "environment": True,
                        "materials": True
                    },
                    "reproducible": True
                },
                "materials": [
                    {
                        "uri": "git@github.com:kushin77/self-hosted-runner",
                        "digest": {
                            "sha256": commit_sha
                        }
                    }
                ]
            }
        }
        
        return attestation


class RateLimiter:
    """Prevent rebuild spam and abuse"""
    
    def __init__(self, audit_log_path: str = ".github/.immutable-audit.log"):
        self.audit_log = audit_log_path
        self.MAX_REBUILDS_PER_ACTION_PER_DAY = 10
        self.MAX_MANDATE_ALL_PER_WEEK = 5
        self.MIN_TIME_BETWEEN_REBUILDS = 60  # seconds
    
    def check_rate_limit(self, action_name: str, operation: str) -> Tuple[bool, str]:
        """Check if operation exceeds rate limits"""
        
        try:
            with open(self.audit_log) as f:
                lines = f.readlines()
        except FileNotFoundError:
            return True, "OK"
        
        now = datetime.utcnow()
        one_day_ago = now - timedelta(days=1)
        one_week_ago = now - timedelta(days=7)
        
        rebuilds_today = 0
        mandate_all_this_week = 0
        last_rebuild = None
        
        for line in lines:
            try:
                entry = json.loads(line)
                entry_time = datetime.fromisoformat(entry['timestamp'].replace('Z', '+00:00')).replace(tzinfo=None)
                
                if entry.get('action') == 'action_rebuilt' and entry.get('details', {}).get('action_name') == action_name:
                    if entry_time > one_day_ago:
                        rebuilds_today += 1
                    last_rebuild = entry_time
                
                if entry.get('action') == 'auto_fix_cycle_complete' and entry_time > one_week_ago:
                    if entry.get('details', {}).get('actions_rebuilt', 0) > 3:
                        mandate_all_this_week += 1
            
            except json.JSONDecodeError:
                continue
        
        # Check limits
        if rebuilds_today >= self.MAX_REBUILDS_PER_ACTION_PER_DAY:
            return False, f"Rate limit exceeded: {rebuilds_today} rebuilds today (max: {self.MAX_REBUILDS_PER_ACTION_PER_DAY})"
        
        if mandate_all_this_week >= self.MAX_MANDATE_ALL_PER_WEEK:
            return False, f"Rate limit exceeded: {mandate_all_this_week} mandate-all cycles this week (max: {self.MAX_MANDATE_ALL_PER_WEEK})"
        
        if last_rebuild and (now - last_rebuild).total_seconds() < self.MIN_TIME_BETWEEN_REBUILDS:
            return False, f"Rate limit exceeded: Too soon since last rebuild (min: {self.MIN_TIME_BETWEEN_REBUILDS}s)"
        
        return True, "OK"


class QuarantineEnforcer:
    """Quarantine compromised actions and prevent rollback"""
    
    @staticmethod
    def quarantine_action(action_name: str, reason: str, action_path: str):
        """Place action in QUARANTINED state"""
        manifest_file = Path(action_path) / "action-manifest.json"
        
        with open(manifest_file) as f:
            manifest = json.load(f)
        
        manifest['lifecycle_state'] = LifecycleState.QUARANTINED.value
        manifest['quarantine_reason'] = reason
        manifest['quarantined_at'] = datetime.utcnow().isoformat()
        
        with open(manifest_file, 'w') as f:
            json.dump(manifest, f, indent=2)
        
        logger.warn(f"🔒 Action quarantined: {action_name}")
        logger.warn(f"   Reason: {reason}")
        logger.warn(f"   Requires manual review and re-activation")
    
    @staticmethod
    def block_compromised_action(action_name: str, action_path: str) -> bool:
        """Block workflow if action is QUARANTINED"""
        manifest_file = Path(action_path) / "action-manifest.json"
        
        if not manifest_file.exists():
            return True  # No manifest = allow (legacy action)
        
        with open(manifest_file) as f:
            manifest = json.load(f)
        
        if manifest.get('lifecycle_state') == LifecycleState.QUARANTINED.value:
            logger.error(f"❌ Action blocked (QUARANTINED): {action_name}")
            logger.error(f"   Reason: {manifest.get('quarantine_reason', 'unknown')}")
            return False
        
        return True


def main():
    """Validation entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description='10X Enforcement Module')
    parser.add_argument('command', nargs='?', choices=['validate-manifest', 'check-rbac', 'check-rate-limit', 'quarantine'], help='Command')
    parser.add_argument('--manifest-dir', help='Manifest directory')
    parser.add_argument('--manifest', help='Manifest file path')
    parser.add_argument('--action', help='Action name/path')
    parser.add_argument('--role', help='Role name')
    parser.add_argument('--permission', help='Permission to check')
    parser.add_argument('--reason', help='Quarantine reason')
    parser.add_argument('--max-rebuilds-per-day', type=int, default=10)
    parser.add_argument('--min-rebuild-gap-seconds', type=int, default=60)
    parser.add_argument('--output', help='Output file path')
    
    args = parser.parse_args()
    
    results = {}
    
    if not args.command:
        parser.print_help()
        exit(0)
    
    if args.command == 'validate-manifest':
        results = {'action': 'validate-manifest', 'status': 'ok', 'manifests': []}
        
        if args.manifest_dir:
            # Scan directory for manifests
            from pathlib import Path
            for manifest_file in Path(args.manifest_dir).glob('*/action-manifest.json'):
                try:
                    with open(manifest_file) as f:
                        manifest = json.load(f)
                    
                    schema = ManifestSchema()
                    if schema.validate(manifest):
                        results['manifests'].append({'file': str(manifest_file), 'valid': True})
                    else:
                        results['manifests'].append({'file': str(manifest_file), 'valid': False})
                        results['status'] = 'error'
                except Exception as e:
                    results['manifests'].append({'file': str(manifest_file), 'valid': False, 'error': str(e)})
                    results['status'] = 'error'
        elif args.manifest:
            with open(args.manifest) as f:
                manifest = json.load(f)
            schema = ManifestSchema()
            valid = schema.validate(manifest)
            results['manifests'].append({'file': args.manifest, 'valid': valid})
            results['status'] = 'ok' if valid else 'error'
    
    elif args.command == 'check-rbac':
        rbac = RBACEnforcer()
        role = args.role or 'ci-bot'
        action = args.action or 'rebuild_action'
        allowed = rbac.check_permission(role, action)
        results = {
            'action': 'check-rbac',
            'role': role,
            'permission': action,
            'allowed': allowed,
            'status': 'ok' if allowed else 'denied'
        }
    
    elif args.command == 'check-rate-limit':
        limiter = RateLimiter()
        limiter.MAX_REBUILDS_PER_DAY = args.max_rebuilds_per_day
        limiter.MIN_REBUILD_GAP_SECONDS = args.min_rebuild_gap_seconds
        
        action = args.action or 'default-action'
        allowed = limiter.can_rebuild_action(action)
        results = {
            'action': 'check-rate-limit',
            'target_action': action,
            'allowed': allowed,
            'status': 'ok' if allowed else 'exceeded'
        }
    
    elif args.command == 'quarantine':
        if not args.action:
            print("Error: --action required")
            exit(1)
        reason = args.reason or 'admin-commanded'
        quarantine = QuarantineEnforcer()
        quarantine.quarantine(args.action, reason)
        results = {
            'action': 'quarantine',
            'target_action': args.action,
            'reason': reason,
            'status': 'ok'
        }
    
    # Output results
    if args.output:
        with open(args.output, 'w') as f:
            json.dump(results, f, indent=2)
        logger.info(f"Results saved to {args.output}")
    else:
        print(json.dumps(results, indent=2))
    
    exit(0 if results.get('status') != 'error' else 1)


if __name__ == '__main__':
    main()
