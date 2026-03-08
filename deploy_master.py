#!/usr/bin/env python3
"""
MASTER DEPLOYMENT EXECUTOR - À la carte Full Suite

This script executes the complete à la carte deployment orchestration:
  1. Security: Remove embedded secrets
  2. Credentials: Migrate to GSM/Vault/KMS
  3. Automation: Setup dynamic retrieval + rotation
  4. Healing: Activate RCA auto-healer

Architecture: Immutable, Ephemeral, Idempotent, No-Ops
Framework: À la carte Deployment Orchestration v1.0
Status: AUTHORIZED & EXECUTING
"""

import os
import sys
import json
import subprocess
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Any

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

FULL_SUITE_COMPONENTS = [
    "remove-embedded-secrets",
    "migrate-to-gsm",
    "migrate-to-vault",
    "migrate-to-kms",
    "setup-dynamic-credential-retrieval",
    "setup-credential-rotation",
    "activate-rca-autohealer",
]

DEPLOYMENT_ID = f"master-{datetime.now().isoformat().replace(':', '-')}"
AUDIT_DIR = Path(".deployment-audit")
AUDIT_DIR.mkdir(exist_ok=True)

# ═══════════════════════════════════════════════════════════════════════════════
# MASTER ORCHESTRATOR
# ═══════════════════════════════════════════════════════════════════════════════

class MasterDeploymentExecutor:
    """Master executor for full suite deployment."""
    
    def __init__(self):
        self.deployment_id = DEPLOYMENT_ID
        self.start_time = datetime.utcnow()
        self.results = {
            "deployment_id": self.deployment_id,
            "start_time": self.start_time.isoformat(),
            "components": {},
        }
    
    def log(self, message: str, level: str = "INFO"):
        """Log message with timestamp."""
        timestamp = datetime.utcnow().isoformat()
        print(f"[{timestamp}] [{level:8}] {message}")
    
    def execute_full_suite(self) -> bool:
        """Execute full suite deployment."""
        self.log(f"════════════════════════════════════════════════════════════")
        self.log(f"MASTER DEPLOYMENT EXECUTOR - FULL SUITE")
        self.log(f"════════════════════════════════════════════════════════════")
        self.log(f"Deployment ID: {self.deployment_id}")
        self.log(f"Authorization: User approved - full execution")
        self.log(f"Architecture: Immutable, Idempotent, Ephemeral, No-Ops")
        self.log(f"Components: {len(FULL_SUITE_COMPONENTS)}")
        self.log(f"════════════════════════════════════════════════════════════")
        
        success = True
        for i, component_id in enumerate(FULL_SUITE_COMPONENTS, 1):
            self.log(f"\n[{i}/{len(FULL_SUITE_COMPONENTS)}] Deploying: {component_id}")
            self.log(f"─────────────────────────────────────────────────────────")
            
            try:
                # Execute component via orchestrator
                result = self._execute_component(component_id)
                
                self.results["components"][component_id] = {
                    "status": "success" if result else "failed",
                    "timestamp": datetime.utcnow().isoformat(),
                }
                
                if result:
                    self.log(f"✅ {component_id} deployed successfully", "SUCCESS")
                else:
                    self.log(f"❌ {component_id} deployment failed", "ERROR")
                    success = False
            
            except Exception as e:
                self.log(f"❌ {component_id} execution error: {e}", "ERROR")
                self.results["components"][component_id] = {
                    "status": "error",
                    "error": str(e),
                    "timestamp": datetime.utcnow().isoformat(),
                }
                success = False
        
        self.results["end_time"] = datetime.utcnow().isoformat()
        self.results["status"] = "success" if success else "failed"
        self.results["total_components"] = len(FULL_SUITE_COMPONENTS)
        self.results["successful_components"] = sum(
            1 for c in self.results["components"].values() if c["status"] == "success"
        )
        
        self._print_summary(success)
        self._write_audit_log(success)
        
        return success
    
    def _execute_component(self, component_id: str) -> bool:
        """Execute single component via orchestrator."""
        try:
            # Call orchestrator for this component
            cmd = f"python3 -m deployment.alacarte --deploy {component_id}"
            
            result = subprocess.run(
                cmd,
                shell=True,
                capture_output=True,
                text=True,
                timeout=900,  # 15 minutes per component
                cwd="/home/akushnir/self-hosted-runner"
            )
            
            if result.returncode == 0:
                self.log(f"  Output: {result.stdout[:300]}", "DEBUG")
                return True
            else:
                self.log(f"  Error: {result.stderr[:300]}", "ERROR")
                return False
        
        except subprocess.TimeoutExpired:
            self.log(f"  Timeout after 15 minutes", "ERROR")
            return False
        except Exception as e:
            self.log(f"  Exception: {e}", "ERROR")
            return False
    
    def _print_summary(self, success: bool):
        """Print deployment summary."""
        self.log(f"\n════════════════════════════════════════════════════════════")
        self.log(f"DEPLOYMENT SUMMARY")
        self.log(f"════════════════════════════════════════════════════════════")
        self.log(f"Deployment ID: {self.deployment_id}")
        self.log(f"Status: {'✅ SUCCESS' if success else '❌ FAILED'}")
        self.log(f"Duration: {(datetime.utcnow() - self.start_time).total_seconds():.1f} seconds")
        self.log(f"\nComponents Deployed: {self.results['successful_components']}/{self.results['total_components']}")
        
        for component_id, result in self.results["components"].items():
            status = "✅" if result["status"] == "success" else "❌"
            self.log(f"  {status} {component_id}")
        
        self.log(f"\nAudit Trail: {AUDIT_DIR / f'deployment_{self.deployment_id}.jsonl'}")
        self.log(f"════════════════════════════════════════════════════════════")
    
    def _write_audit_log(self, success: bool):
        """Write immutable audit log."""
        audit_file = AUDIT_DIR / f"deployment_{self.deployment_id}.jsonl"
        
        # Write header event
        header_event = {
            "timestamp": self.start_time.isoformat(),
            "event_type": "master_deployment_start",
            "deployment_id": self.deployment_id,
            "components_count": len(FULL_SUITE_COMPONENTS),
        }
        
        with open(audit_file, 'a') as f:
            f.write(json.dumps(header_event) + '\n')
        
        # Write component events
        for component_id, result in self.results["components"].items():
            event = {
                "timestamp": result["timestamp"],
                "event_type": "component_deployment",
                "component_id": component_id,
                "status": result["status"],
            }
            with open(audit_file, 'a') as f:
                f.write(json.dumps(event) + '\n')
        
        # Write summary event
        summary_event = {
            "timestamp": self.results.get("end_time", datetime.utcnow().isoformat()),
            "event_type": "master_deployment_complete",
            "status": self.results["status"],
            "successful": self.results["successful_components"],
            "total": self.results["total_components"],
        }
        
        with open(audit_file, 'a') as f:
            f.write(json.dumps(summary_event) + '\n')
        
        # Write manifest
        manifest_file = AUDIT_DIR / f"deployment_{self.deployment_id}_manifest.json"
        with open(manifest_file, 'w') as f:
            json.dump(self.results, f, indent=2)


def main():
    """Main entry point."""
    executor = MasterDeploymentExecutor()
    success = executor.execute_full_suite()
    
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
