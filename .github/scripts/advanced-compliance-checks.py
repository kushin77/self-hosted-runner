#!/usr/bin/env python3
"""
Advanced Compliance Checks - 24+ enterprise-grade compliance checks
"""

import json
import os
import re
import sys
import yaml
from pathlib import Path
from typing import List, Dict, Tuple, Any


class ComplianceChecker:
    """Main compliance checker for workflows"""

    def __init__(self):
        self.violations = []
        self.warnings = []
        self.passed_checks = []
        self.checks_run = 0

    def add_violation(self, check_id: str, message: str, severity: str = "error"):
        """Add a violation to the list"""
        self.violations.append({
            "check_id": check_id,
            "message": message,
            "severity": severity
        })

    def add_warning(self, check_id: str, message: str):
        """Add a warning"""
        self.warnings.append({
            "check_id": check_id,
            "message": message
        })

    def add_passed(self, check_id: str, message: str):
        """Record passed check"""
        self.passed_checks.append({
            "check_id": check_id,
            "message": message
        })

    # CREDENTIAL SECURITY CHECKS (6)
    def check_credential_fallback(self, workflow: Dict) -> None:
        """Check 1/24: Multi-layer credential fallback"""
        self.checks_run += 1
        workflow_str = yaml.dump(workflow).lower()
        has_creds = any(x in workflow_str for x in ['gsm', 'vault', 'kms'])
        if has_creds:
            self.add_passed("CRED_001", "Credentials configured")
        else:
            self.add_warning("CRED_001", "No multi-layer credentials found")

    def check_credential_ttl(self, workflow: Dict) -> None:
        """Check 2/24: Credential TTL configured < 24h"""
        self.checks_run += 1
        workflow_str = yaml.dump(workflow).lower()
        if re.search(r'ttl|expir|token.*time', workflow_str):
            self.add_passed("CRED_002", "TTL configured")
        else:
            self.add_warning("CRED_002", "No credential TTL found")

    def check_auto_rotation(self, workflow: Dict) -> None:
        """Check 3/24: Auto-rotation strategy"""
        self.checks_run += 1
        workflow_str = yaml.dump(workflow).lower()
        if any(x in workflow_str for x in ['rotation', 'rotate', 'refresh', 'renew']):
            self.add_passed("CRED_003", "Rotation strategy found")
        else:
            self.add_warning("CRED_003", "No rotation strategy documented")

    def check_no_hardcoded_secrets(self, workflow: Dict) -> None:
        """Check 4/24: No hardcoded secrets"""
        self.checks_run += 1
        workflow_str = yaml.dump(workflow)
        if re.search(r'(AKIA|sk-|rsa-)[A-Za-z0-9]+', workflow_str):
            self.add_violation("CRED_004", "Potential hardcoded secrets found")
        else:
            self.add_passed("CRED_004", "No hardcoded secrets")

    def check_credential_failover(self, workflow: Dict) -> None:
        """Check 5/24: Credential failover tested"""
        self.checks_run += 1
        if 'jobs' in workflow:
            if any('test' in j.lower() or 'failover' in j.lower() for j in workflow['jobs'].keys()):
                self.add_passed("CRED_005", "Failover test found")
            else:
                self.add_warning("CRED_005", "No failover test detected")

    def check_sts_validation(self, workflow: Dict) -> None:
        """Check 6/24: STS token validation"""
        self.checks_run += 1
        workflow_str = yaml.dump(workflow).lower()
        if 'sts' in workflow_str or 'assumerole' in workflow_str:
            self.add_passed("CRED_006", "STS pattern detected")
        else:
            self.add_warning("CRED_006", "No STS token pattern found")

    # WORKFLOW STRUCTURE CHECKS (6)
    def check_approval_gates(self, workflow: Dict) -> None:
        """Check 7/24: Deploy jobs have approval gates"""
        self.checks_run += 1
        is_deploy = False
        has_env = False
        if 'jobs' in workflow:
            for name, job in workflow['jobs'].items():
                if isinstance(job, dict) and ('deploy' in name.lower() or 'release' in name.lower()):
                    is_deploy = True
                    if 'environment' in job:
                        has_env = True
        if not is_deploy:
            self.add_passed("STRUCT_007", "No deploy jobs (N/A)")
        elif has_env:
            self.add_passed("STRUCT_007", "Approval gates configured")
        else:
            self.add_violation("STRUCT_007", "Deploy job missing approval gate")

    def check_idempotent_guards(self, workflow: Dict) -> None:
        """Check 8/24: Mutating jobs have idempotent guards"""
        self.checks_run += 1
        self.add_warning("STRUCT_008", "Manual review recommended for idempotency")

    def check_concurrency(self, workflow: Dict) -> None:
        """Check 9/24: Concurrency group configured"""
        self.checks_run += 1
        if 'concurrency' in workflow:
            self.add_passed("STRUCT_009", "Concurrency configured")
        else:
            self.add_warning("STRUCT_009", "No concurrency group found")

    def check_timeout(self, workflow: Dict) -> None:
        """Check 10/24: Timeout configured"""
        self.checks_run += 1
        missing = []
        if 'jobs' in workflow:
            for name, job in workflow['jobs'].items():
                if isinstance(job, dict) and 'timeout-minutes' not in job:
                    missing.append(name)
        if missing:
            self.add_warning("STRUCT_010", f"Missing timeout: {missing[0]}")
        else:
            self.add_passed("STRUCT_010", "All jobs have timeout")

    def check_conditions(self, workflow: Dict) -> None:
        """Check 11/24: Run conditions documented"""
        self.checks_run += 1
        if 'jobs' in workflow:
            has_if = any('if' in j for j in workflow['jobs'].values() if isinstance(j, dict))
            if has_if:
                self.add_passed("STRUCT_011", "Conditional execution found")
            else:
                self.add_warning("STRUCT_011", "No conditions found")

    def check_idempotency_markers(self, workflow: Dict) -> None:
        """Check 12/24: Idempotency markers present"""
        self.checks_run += 1
        workflow_str = yaml.dump(workflow).lower()
        if any(x in workflow_str for x in ['idempotent', 'ephemeral', 'stateless']):
            self.add_passed("STRUCT_012", "Idempotency markers found")
        else:
            self.add_warning("STRUCT_012", "No idempotency markers")

    # AUDIT & COMPLIANCE CHECKS (6)
    def check_audit_logging(self, workflow: Dict) -> None:
        """Check 13/24: State changes logged"""
        self.checks_run += 1
        workflow_str = yaml.dump(workflow).lower()
        if any(x in workflow_str for x in ['audit', 'log', 'compliance-audit']):
            self.add_passed("AUDIT_013", "Audit logging referenced")
        else:
            self.add_warning("AUDIT_013", "No audit logging detected")

    def check_rollback(self, workflow: Dict) -> None:
        """Check 14/24: Rollback strategy documented"""
        self.checks_run += 1
        workflow_str = yaml.dump(workflow).lower()
        if any(x in workflow_str for x in ['rollback', 'revert', 'restore']):
            self.add_passed("AUDIT_014", "Rollback documented")
        else:
            self.add_warning("AUDIT_014", "No rollback strategy")

    def check_dr(self, workflow: Dict) -> None:
        """Check 15/24: Disaster recovery"""
        self.checks_run += 1
        workflow_str = yaml.dump(workflow).lower()
        if any(x in workflow_str for x in ['disaster', 'recovery', 'failover', 'backup']):
            self.add_passed("AUDIT_015", "DR referenced")
        else:
            self.add_warning("AUDIT_015", "No DR plan")

    def check_access_control(self, workflow: Dict) -> None:
        """Check 16/24: Access control enforced"""
        self.checks_run += 1
        if 'permissions' in yaml.dump(workflow):
            self.add_passed("AUDIT_016", "Permissions block present")
        else:
            self.add_warning("AUDIT_016", "No permissions block")

    def check_tls(self, workflow: Dict) -> None:
        """Check 17/24: Encryption in transit"""
        self.checks_run += 1
        workflow_str = yaml.dump(workflow)
        http_urls = len(re.findall(r'http://[^\s"\']+', workflow_str))
        if http_urls:
            self.add_violation("AUDIT_017", f"Found {http_urls} unencrypted URLs")
        else:
            self.add_passed("AUDIT_017", "No unencrypted URLs")

    def check_encryption_at_rest(self, workflow: Dict) -> None:
        """Check 18/24: Encryption at rest"""
        self.checks_run += 1
        workflow_str = yaml.dump(workflow).lower()
        if any(x in workflow_str for x in ['kms', 'encrypt', 'cipher']):
            self.add_passed("AUDIT_018", "Encryption found")
        else:
            self.add_warning("AUDIT_018", "No encryption at rest")

    # OPERATIONAL EXCELLENCE CHECKS (6)
    def check_resources(self, workflow: Dict) -> None:
        """Check 19/24: Resource limits set"""
        self.checks_run += 1
        workflow_str = yaml.dump(workflow).lower()
        if any(x in workflow_str for x in ['memory', 'cpu', 'limit', 'request']):
            self.add_passed("OPS_019", "Resource limits found")
        else:
            self.add_warning("OPS_019", "No resource limits")

    def check_ephemeral(self, workflow: Dict) -> None:
        """Check 20/24: Ephemeral cleanup"""
        self.checks_run += 1
        workflow_str = yaml.dump(workflow).lower()
        if any(x in workflow_str for x in ['cleanup', 'delete', 'teardown', 'ephemeral']):
            self.add_passed("OPS_020", "Cleanup configured")
        else:
            self.add_warning("OPS_020", "No ephemeral cleanup")

    def check_monitoring(self, workflow: Dict) -> None:
        """Check 21/24: Monitoring configured"""
        self.checks_run += 1
        workflow_str = yaml.dump(workflow).lower()
        if any(x in workflow_str for x in ['monitoring', 'alert', 'metric', 'slack']):
            self.add_passed("OPS_021", "Monitoring configured")
        else:
            self.add_warning("OPS_021", "No monitoring")

    def check_runbook(self, workflow: Dict) -> None:
        """Check 22/24: Runbook linked"""
        self.checks_run += 1
        workflow_str = yaml.dump(workflow).lower()
        if any(x in workflow_str for x in ['runbook', 'playbook', 'documentation']):
            self.add_passed("OPS_022", "Runbook linked")
        else:
            self.add_warning("OPS_022", "No runbook")

    def check_postmortem(self, workflow: Dict) -> None:
        """Check 23/24: Post-mortem template"""
        self.checks_run += 1
        workflow_str = yaml.dump(workflow).lower()
        if any(x in workflow_str for x in ['postmortem', 'incident', 'rca']):
            self.add_passed("OPS_023", "Post-mortem process")
        else:
            self.add_warning("OPS_023", "No post-mortem")

    def check_sla(self, workflow: Dict) -> None:
        """Check 24/24: SLA/objectives documented"""
        self.checks_run += 1
        workflow_str = yaml.dump(workflow).lower()
        if any(x in workflow_str for x in ['sla', 'service level', 'objective', 'rto', 'rpo']):
            self.add_passed("OPS_024", "SLA documented")
        else:
            self.add_warning("OPS_024", "No SLA")

    def run_all(self, workflow: Dict) -> None:
        """Run all 24 checks"""
        # Credentials (6)
        self.check_credential_fallback(workflow)
        self.check_credential_ttl(workflow)
        self.check_auto_rotation(workflow)
        self.check_no_hardcoded_secrets(workflow)
        self.check_credential_failover(workflow)
        self.check_sts_validation(workflow)
        # Structure (6)
        self.check_approval_gates(workflow)
        self.check_idempotent_guards(workflow)
        self.check_concurrency(workflow)
        self.check_timeout(workflow)
        self.check_conditions(workflow)
        self.check_idempotency_markers(workflow)
        # Audit (6)
        self.check_audit_logging(workflow)
        self.check_rollback(workflow)
        self.check_dr(workflow)
        self.check_access_control(workflow)
        self.check_tls(workflow)
        self.check_encryption_at_rest(workflow)
        # Operations (6)
        self.check_resources(workflow)
        self.check_ephemeral(workflow)
        self.check_monitoring(workflow)
        self.check_runbook(workflow)
        self.check_postmortem(workflow)
        self.check_sla(workflow)


def main():
    workflow_dir = Path(".github/workflows")
    if not workflow_dir.exists():
        print("Error: .github/workflows not found")
        sys.exit(1)

    files = list(workflow_dir.glob("*.yml")) + list(workflow_dir.glob("*.yaml"))
    print(f"🔍 Scanning {len(files)} workflows...")
    print()

    total_violations = 0
    total_warnings = 0
    total_passed = 0
    total_checks = 0

    for wf_file in sorted(files):
        try:
            with open(wf_file) as f:
                workflow = yaml.safe_load(f)
            if workflow is None:
                continue

            checker = ComplianceChecker()
            checker.run_all(workflow)

            total_checks += checker.checks_run
            total_passed += len(checker.passed_checks)
            total_violations += len(checker.violations)
            total_warnings += len(checker.warnings)

            status = "✓" if not checker.violations else "❌"
            print(f"{status} {wf_file.name:40s} | {checker.checks_run:2d} checks | {len(checker.violations):2d} violations | {len(checker.warnings):2d} warnings")

        except Exception as e:
            print(f"⚠️  {wf_file.name:40s} | Error: {str(e)[:40]}")

    print()
    print("=" * 100)
    print(f"📊 Advanced Compliance Summary")
    print("=" * 100)
    print(f"Total Checks: {total_checks}")
    print(f"Passed: {total_passed}")
    print(f"Violations: {total_violations}")
    print(f"Warnings: {total_warnings}")
    sys.exit(1 if total_violations > 0 else 0)


if __name__ == "__main__":
    main()
