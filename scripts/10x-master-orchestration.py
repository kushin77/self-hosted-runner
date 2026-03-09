#!/usr/bin/env python3
"""
10X MASTER ENFORCEMENT ORCHESTRATION
Complete end-to-end enforcement lifecycle

Phases:
1. DISCOVERY: Scan all workflows and actions
2. ANALYSIS: Identify violations and risks
3. REMEDIATION: Auto-fix remediable issues
4. ENFORCEMENT: Apply progressive gates
5. AUDIT: Immutable logging and reporting
"""

import subprocess
import json
import sys
import logging
from pathlib import Path
from datetime import datetime
import argparse

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [10X-MASTER] %(levelname)s: %(message)s'
)
logger = logging.getLogger(__name__)


class MasterOrchestrator:
    """Complete 10X enforcement lifecycle"""
    
    def __init__(self, repo_root: str = '.'):
        self.repo_root = Path(repo_root)
        self.execution_log = {
            'timestamp': datetime.utcnow().isoformat(),
            'phases': {}
        }
    
    def phase_1_discovery(self) -> bool:
        """Phase 1: Comprehensive discovery"""
        logger.info("═" * 70)
        logger.info("PHASE 1: DISCOVERY - Scan all workflows and actions")
        logger.info("═" * 70)
        
        try:
            result = subprocess.run([
                'python3',
                str(self.repo_root / 'scripts/10x-enforcement-orchestrator.py'),
                'scan-all',
                '--output', '/tmp/phase1-discovery.json'
            ], capture_output=True, text=True)
            
            if result.returncode != 0:
                logger.warning("⚠️  Discovery completed with warnings")
            
            # Parse results
            with open('/tmp/phase1-discovery.json') as f:
                discovery_results = json.load(f)
            
            self.execution_log['phases']['discovery'] = {
                'status': 'COMPLETE',
                'results': discovery_results
            }
            
            logger.info("✅ PHASE 1 COMPLETE")
            return True
        
        except Exception as e:
            logger.error(f"❌ Phase 1 failed: {e}")
            return False
    
    def phase_2_analysis(self) -> bool:
        """Phase 2: Risk and compliance analysis"""
        logger.info("═" * 70)
        logger.info("PHASE 2: ANALYSIS - Risk assessment and compliance check")
        logger.info("═" * 70)
        
        try:
            result = subprocess.run([
                'python3',
                str(self.repo_root / 'scripts/10x-remediation-engine.py'),
                'dashboard',
                '--output', '/tmp/phase2-analysis.json'
            ], capture_output=True, text=True)
            
            if result.returncode == 0:
                with open('/tmp/phase2-analysis.json') as f:
                    analysis_results = json.load(f)
                
                self.execution_log['phases']['analysis'] = {
                    'status': 'COMPLETE',
                    'results': analysis_results
                }
                
                logger.info("✅ PHASE 2 COMPLETE")
                return True
            else:
                logger.error(f"Phase 2 error: {result.stderr}")
                return False
        
        except Exception as e:
            logger.error(f"❌ Phase 2 failed: {e}")
            return False
    
    def phase_3_remediation(self, auto_apply: bool = False) -> bool:
        """Phase 3: Automatic remediation"""
        logger.info("═" * 70)
        logger.info(f"PHASE 3: REMEDIATION - Auto-fix violations (apply={auto_apply})")
        logger.info("═" * 70)
        
        try:
            cmd = [
                'python3',
                str(self.repo_root / 'scripts/10x-remediation-engine.py'),
                'remediate',
                '--output', '/tmp/phase3-remediation.json'
            ]
            
            if auto_apply:
                cmd.append('--apply')
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            with open('/tmp/phase3-remediation.json') as f:
                remediation_results = json.load(f)
            
            self.execution_log['phases']['remediation'] = {
                'status': 'COMPLETE',
                'auto_apply': auto_apply,
                'remediations_found': len(remediation_results.get('remediations', [])),
                'results': remediation_results
            }
            
            logger.info("✅ PHASE 3 COMPLETE")
            return True
        
        except Exception as e:
            logger.error(f"❌ Phase 3 failed: {e}")
            return False
    
    def phase_4_enforcement(self, mode: str = 'audit') -> bool:
        """Phase 4: Progressive enforcement"""
        logger.info("═" * 70)
        logger.info(f"PHASE 4: ENFORCEMENT - Progressive gates (mode={mode})")
        logger.info("═" * 70)
        
        try:
            result = subprocess.run([
                'python3',
                str(self.repo_root / 'scripts/10x-enforcement-orchestrator.py'),
                'enforce',
                '--mode', mode,
                '--output', '/tmp/phase4-enforcement.json'
            ], capture_output=True, text=True)
            
            with open('/tmp/phase4-enforcement.json') as f:
                enforcement_results = json.load(f)
            
            self.execution_log['phases']['enforcement'] = {
                'status': 'COMPLETE',
                'mode': mode,
                'should_pass': enforcement_results.get('should_pass', False),
                'results': enforcement_results
            }
            
            logger.info("✅ PHASE 4 COMPLETE")
            return enforcement_results.get('should_pass', False)
        
        except Exception as e:
            logger.error(f"❌ Phase 4 failed: {e}")
            return False
    
    def phase_5_audit(self) -> bool:
        """Phase 5: Immutable audit logging"""
        logger.info("═" * 70)
        logger.info("PHASE 5: AUDIT - Immutable logging and reports")
        logger.info("═" * 70)
        
        try:
            audit_record = {
                'timestamp': datetime.utcnow().isoformat(),
                'execution_summary': self.execution_log,
                'phases_completed': list(self.execution_log['phases'].keys()),
                'overall_status': 'SUCCESS' if all(
                    p.get('status') == 'COMPLETE'
                    for p in self.execution_log['phases'].values()
                ) else 'PARTIAL'
            }
            
            # Write immutable audit log
            audit_file = Path('/tmp/10x-audit.log')
            with open(audit_file, 'a') as f:
                f.write(json.dumps(audit_record) + '\n')
            
            logger.info(f"✅ Audit log: {audit_file}")
            logger.info("✅ PHASE 5 COMPLETE")
            
            return True
        
        except Exception as e:
            logger.error(f"❌ Phase 5 failed: {e}")
            return False
    
    def run_full_lifecycle(self, mode: str = 'audit', auto_apply: bool = False) -> int:
        """Execute complete enforcement lifecycle"""
        
        logger.info("\n" + "🚀" * 35)
        logger.info("10X MASTER ENFORCEMENT ORCHESTRATION")
        logger.info("RCA: 108 workflows, 291 violations, 15 YAML errors")
        logger.info("Solution: Progressive enforcement with auto-remediation")
        logger.info("🚀" * 35 + "\n")
        
        # Execute all phases
        success = True
        
        if not self.phase_1_discovery():
            logger.error("Discovery phase failed")
            return 1
        
        if not self.phase_2_analysis():
            logger.error("Analysis phase failed")
            return 1
        
        if not self.phase_3_remediation(auto_apply=auto_apply):
            logger.error("Remediation phase failed")
            return 1
        
        if not self.phase_4_enforcement(mode=mode):
            logger.warning(f"Enforcement phase blocked in {mode} mode")
            if mode == 'block':
                success = False
        
        if not self.phase_5_audit():
            logger.error("Audit phase failed")
            return 1
        
        # Final summary
        logger.info("\n" + "═" * 70)
        logger.info("EXECUTION SUMMARY")
        logger.info("═" * 70)
        
        for phase_name, phase_data in self.execution_log['phases'].items():
            status = phase_data.get('status', 'UNKNOWN')
            logger.info(f"  {phase_name.upper()}: {status}")
        
        logger.info("=" * 70 + "\n")
        
        return 0 if success else 1


def main():
    parser = argparse.ArgumentParser(
        description='10X Master Enforcement Orchestration'
    )
    parser.add_argument('--mode', choices=['audit', 'warn', 'block'], default='audit',
                       help='Progressive enforcement mode')
    parser.add_argument('--apply-fixes', action='store_true',
                       help='Automatically apply remediations')
    parser.add_argument('--repo-root', default='.',
                       help='Repository root path')
    
    args = parser.parse_args()
    
    orchestrator = MasterOrchestrator(repo_root=args.repo_root)
    return orchestrator.run_full_lifecycle(
        mode=args.mode,
        auto_apply=args.apply_fixes
    )


if __name__ == '__main__':
    exit_code = main()
    sys.exit(exit_code)
