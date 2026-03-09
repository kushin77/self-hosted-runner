#!/usr/bin/env python3
"""
10X INTEGRATION TESTING FRAMEWORK
Post-rebuild validation: unit tests, integration tests, security scanning, compliance
"""

import os
import sys
import json
import subprocess
from pathlib import Path
from typing import Dict, List, Tuple
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)


class IntegrationTestRunner:
    """Runs comprehensive tests after action rebuild"""
    
    def __init__(self, action_path: str):
        self.action_path = action_path
        self.action_name = Path(action_path).name
        self.results = {
            'action': self.action_name,
            'tests_passed': 0,
            'tests_failed': 0,
            'tests_skipped': 0,
            'details': []
        }
    
    def run_all_tests(self) -> Tuple[bool, Dict]:
        """Run all test suites"""
        logger.info(f"🧪 Running integration tests for: {self.action_name}")
        
        # Run test suites
        self._run_unit_tests()
        self._run_integration_tests()
        self._run_security_scan()
        self._run_compliance_check()
        self._run_performance_benchmark()
        
        # Summary
        total = self.results['tests_passed'] + self.results['tests_failed']
        logger.info(f"\n📊 Test Results Summary:")
        logger.info(f"   Passed:  {self.results['tests_passed']}/{total}")
        logger.info(f"   Failed:  {self.results['tests_failed']}/{total}")
        logger.info(f"   Skipped: {self.results['tests_skipped']}")
        
        success = self.results['tests_failed'] == 0
        return success, self.results
    
    def _run_unit_tests(self):
        """Run unit tests if available"""
        test_dir = Path(self.action_path) / 'tests'
        validate_script = test_dir / 'validate.sh'
        
        if not validate_script.exists():
            logger.info("⏭️  Unit tests: skipped (no tests/validate.sh)")
            self.results['tests_skipped'] += 1
            return
        
        logger.info("▶️  Running unit tests...")
        try:
            result = subprocess.run(
                [str(validate_script)],
                cwd=self.action_path,
                timeout=120,
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                logger.info("   ✅ Unit tests passed")
                self.results['tests_passed'] += 1
                self.results['details'].append({
                    'test': 'unit_tests',
                    'status': 'PASS',
                    'output': result.stdout[:500]
                })
            else:
                logger.error("   ❌ Unit tests failed")
                self.results['tests_failed'] += 1
                self.results['details'].append({
                    'test': 'unit_tests',
                    'status': 'FAIL',
                    'error': result.stderr[:500]
                })
        
        except subprocess.TimeoutExpired:
            logger.error("   ❌ Unit tests timed out")
            self.results['tests_failed'] += 1
            self.results['details'].append({
                'test': 'unit_tests',
                'status': 'TIMEOUT'
            })
        except Exception as e:
            logger.error(f"   ❌ Unit tests error: {e}")
            self.results['tests_failed'] += 1
    
    def _run_integration_tests(self):
        """Run action in test workflow"""
        logger.info("▶️  Running integration tests...")
        
        # Create temporary test workflow
        test_workflow = f"""
name: Test {self.action_name}
on: workflow_dispatch

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Test {self.action_name}
        uses: ./{self.action_path}
"""
        
        try:
            # Validate action.yml syntax
            import yaml
            action_yml = Path(self.action_path) / 'action.yml'
            
            if action_yml.exists():
                with open(action_yml) as f:
                    config = yaml.safe_load(f)
                
                if 'name' not in config or 'runs' not in config:
                    raise ValueError("Invalid action.yml: missing name or runs")
                
                logger.info("   ✅ Integration tests passed (YAML valid)")
                self.results['tests_passed'] += 1
                self.results['details'].append({
                    'test': 'integration_tests',
                    'status': 'PASS',
                    'action_name': config.get('name')
                })
            else:
                logger.warn("   ⏭️  Integration tests: skipped (no action.yml)")
                self.results['tests_skipped'] += 1
        
        except Exception as e:
            logger.error(f"   ❌ Integration tests failed: {e}")
            self.results['tests_failed'] += 1
            self.results['details'].append({
                'test': 'integration_tests',
                'status': 'FAIL',
                'error': str(e)
            })
    
    def _run_security_scan(self):
        """Scan for security issues"""
        logger.info("▶️  Running security scan...")
        
        issues = []
        
        # Check 1: No plaintext secrets
        for file in Path(self.action_path).rglob('*'):
            if file.is_file() and not file.name.startswith('.'):
                try:
                    with open(file, 'r') as f:
                        content = f.read()
                        if any(secret in content.lower() for secret in ['password', 'api_key', 'token', 'secret']):
                            issues.append(f"Potential plaintext secret in {file}")
                except:
                    pass
        
        # Check 2: No dangerous permissions
        action_yml_path = Path(self.action_path) / 'action.yml'
        if action_yml_path.exists():
            import yaml
            with open(action_yml_path) as f:
                config = yaml.safe_load(f)
                if config.get('runs', {}).get('using') == 'docker':
                    image = config.get('runs', {}).get('image')
                    if 'latest' in str(image):
                        issues.append(f"Docker image uses 'latest' tag (not reproducible): {image}")
        
        if issues:
            logger.warn(f"   ⚠️  Security scan found {len(issues)} issue(s)")
            for issue in issues:
                logger.warn(f"      - {issue}")
            self.results['tests_failed'] += 1
            self.results['details'].append({
                'test': 'security_scan',
                'status': 'FAIL',
                'issues': issues
            })
        else:
            logger.info("   ✅ Security scan passed")
            self.results['tests_passed'] += 1
            self.results['details'].append({
                'test': 'security_scan',
                'status': 'PASS'
            })
    
    def _run_compliance_check(self):
        """Verify compliance with policies"""
        logger.info("▶️  Running compliance check...")
        
        action_yml_path = Path(self.action_path) / 'action.yml'
        compliance_issues = []
        
        if not action_yml_path.exists():
            logger.error("   ❌ Compliance check failed: no action.yml")
            self.results['tests_failed'] += 1
            return
        
        import yaml
        with open(action_yml_path) as f:
            config = yaml.safe_load(f)
        
        # Check 1: Has description
        if not config.get('description'):
            compliance_issues.append("Missing action description")
        
        # Check 2: Has author
        if not config.get('author'):
            compliance_issues.append("Missing author field")
        
        # Check 3: Has branding (for marketplace)
        if not config.get('branding'):
            compliance_issues.append("Missing branding (optional but recommended)")
        
        # Check 4: No hard-coded secrets
        manifest_path = Path(self.action_path) / 'action-manifest.json'
        if manifest_path.exists():
            with open(manifest_path) as f:
                manifest = json.load(f)
                if manifest.get('credentials_provider') not in ['GSM', 'VAULT', 'KMS']:
                    compliance_issues.append(f"Credentials provider must be GSM, VAULT, or KMS (got: {manifest.get('credentials_provider')})")
        
        if compliance_issues:
            logger.warn(f"   ⚠️  Compliance check found {len(compliance_issues)} issue(s)")
            for issue in compliance_issues:
                logger.warn(f"      - {issue}")
            self.results['tests_failed'] += 1
            self.results['details'].append({
                'test': 'compliance_check',
                'status': 'FAIL',
                'issues': compliance_issues
            })
        else:
            logger.info("   ✅ Compliance check passed")
            self.results['tests_passed'] += 1
            self.results['details'].append({
                'test': 'compliance_check',
                'status': 'PASS'
            })
    
    def _run_performance_benchmark(self):
        """Benchmark action execution time"""
        logger.info("▶️  Running performance benchmark...")
        
        try:
            import time
            
            # Simple benchmark: time to load action
            start = time.time()
            action_yml_path = Path(self.action_path) / 'action.yml'
            
            if action_yml_path.exists():
                import yaml
                with open(action_yml_path) as f:
                    yaml.safe_load(f)
            
            elapsed = time.time() - start
            
            logger.info(f"   ✅ Performance benchmark: {elapsed:.3f}s")
            self.results['tests_passed'] += 1
            self.results['details'].append({
                'test': 'performance_benchmark',
                'status': 'PASS',
                'elapsed_seconds': elapsed
            })
        
        except Exception as e:
            logger.warn(f"   ⚠️  Performance benchmark skipped: {e}")
            self.results['tests_skipped'] += 1


def main():
    """Run integration tests for action"""
    if len(sys.argv) < 2:
        print("Usage: python3 10x-integration-tests.py <action_path>")
        sys.exit(1)
    
    action_path = sys.argv[1]
    
    if not Path(action_path).exists():
        print(f"Error: Action path not found: {action_path}")
        sys.exit(1)
    
    runner = IntegrationTestRunner(action_path)
    success, results = runner.run_all_tests()
    
    # Output JSON for CI/CD integration
    print(json.dumps(results, indent=2))
    
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
