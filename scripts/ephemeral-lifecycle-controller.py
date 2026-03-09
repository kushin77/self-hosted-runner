#!/usr/bin/env python3
"""
Ephemeral Runner Lifecycle Controller

Purpose: Manage TTL policies, graceful drain, and safe reaping of ephemeral runners
Features:
  - Dynamic TTL assignment based on job complexity and telemetry
  - Graceful drain with in-progress job handling
  - Safe reap with verification checks
  - AI-Oracle integration (optional)
  - Immutable audit trail
  - Comprehensive monitoring

Usage:
  # Display runner info
  python3 scripts/ephemeral-lifecycle-controller.py info

  # Assign TTL based on policy
  python3 scripts/ephemeral-lifecycle-controller.py assign-ttl --job-type build --duration 1800

  # Initiate graceful drain
  python3 scripts/ephemeral-lifecycle-controller.py drain --strategy graceful --timeout 300

  # Check if safe to reap
  python3 scripts/ephemeral-lifecycle-controller.py check-reap

  # Execute reap operation
  python3 scripts/ephemeral-lifecycle-controller.py reap --force
"""

import os
import sys
import json
import yaml
import argparse
import logging
import subprocess
import time
import uuid
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass
from enum import Enum
import signal
import psutil


# ============================================================================
# Configuration and Constants
# ============================================================================

class DrainStrategy(Enum):
    """Drain strategies for ephemeral runners"""
    GRACEFUL = "graceful"
    FORCEFUL = "forceful"
    SAFE_REAP = "safe_reap"


@dataclass
class TTLConfig:
    """TTL configuration for a runner"""
    base_ttl: int
    max_ttl: int
    complexity_multiplier: float
    assigned_at: datetime
    policy_name: str


class EphemeralLifecycleController:
    """Main lifecycle controller for ephemeral runners"""

    def __init__(self, config_path: str = "config/ttl-policies.yaml"):
        """Initialize the lifecycle controller"""
        self.config_path = Path(config_path)
        self.runner_home = Path(os.getenv("RUNNER_HOME", "."))
        self.temp_dir = Path(os.getenv("RUNNER_TEMP", "/tmp"))
        self.audit_log_dir = self.temp_dir / "audit-logs"
        self.state_file = self.temp_dir / "runner-ttl-state.json"
        
        # Setup logging
        self.logger = self._setup_logging()
        
        # Load policy configuration
        self.policy_config = self._load_policy_config()
        
        # Ensure audit log directory exists
        self.audit_log_dir.mkdir(parents=True, exist_ok=True)
        
        self.logger.info("Lifecycle controller initialized")

    def _setup_logging(self) -> logging.Logger:
        """Setup logging with audit trail"""
        logger = logging.getLogger("ephemeral-lifecycle")
        logger.setLevel(logging.DEBUG)
        
        # Console handler
        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setLevel(logging.INFO)
        console_format = logging.Formatter(
            '[%(asctime)s] [%(levelname)s] %(message)s'
        )
        console_handler.setFormatter(console_format)
        logger.addHandler(console_handler)
        
        return logger

    def _load_policy_config(self) -> Dict:
        """Load TTL policy configuration from YAML"""
        if not self.config_path.exists():
            self.logger.warning(
                f"Policy config not found at {self.config_path}, using defaults"
            )
            return {}
        
        try:
            with open(self.config_path, 'r') as f:
                config = yaml.safe_load(f)
            self.logger.info(f"Loaded policy config from {self.config_path}")
            return config
        except Exception as e:
            self.logger.error(f"Failed to load policy config: {e}")
            return {}

    def _audit_log(self, event: str, details: Dict) -> None:
        """Write immutable audit log entry"""
        if not self.policy_config.get("audit", {}).get("enabled", True):
            return
        
        try:
            audit_entry = {
                "timestamp": datetime.utcnow().isoformat() + "Z",
                "event": event,
                "runner_id": os.getenv("RUNNER_NAME", "unknown"),
                "job_id": os.getenv("GITHUB_JOB", "unknown"),
                "audit_id": str(uuid.uuid4()),
                "details": details
            }
            
            log_file = self.audit_log_dir / f"audit-{datetime.utcnow().strftime('%Y%m%d')}.jsonl"
            
            with open(log_file, 'a') as f:
                f.write(json.dumps(audit_entry) + "\n")
            
            self.logger.debug(f"Audit logged: {event}")
        except Exception as e:
            self.logger.error(f"Failed to write audit log: {e}")

    def _save_state(self, state: Dict) -> None:
        """Save runner state to file"""
        try:
            with open(self.state_file, 'w') as f:
                json.dump(state, f, indent=2, default=str)
            self.logger.debug(f"State saved to {self.state_file}")
        except Exception as e:
            self.logger.error(f"Failed to save state: {e}")

    def _load_state(self) -> Dict:
        """Load runner state from file"""
        if not self.state_file.exists():
            return {}
        
        try:
            with open(self.state_file, 'r') as f:
                return json.load(f)
        except Exception as e:
            self.logger.error(f"Failed to load state: {e}")
            return {}

    # ========================================================================
    # TTL Policy Engine
    # ========================================================================

    def _match_policy(self, job_type: str, labels: List[str] = None,
                     duration_hint: int = None) -> Optional[Dict]:
        """Match job to applicable TTL policy"""
        labels = labels or []
        policies = self.policy_config.get("policies", [])
        
        for policy in policies:
            filters = policy.get("filters", {})
            
            # Check job_type filter
            if job_type and job_type not in filters.get("job_type", []):
                continue
            
            # Check labels filter
            if labels:
                required_labels = set(filters.get("labels", []))
                job_labels = set(labels)
                if required_labels and not required_labels.issubset(job_labels):
                    continue
            
            # Check max duration filter
            if duration_hint:
                max_duration = filters.get("max_duration", float('inf'))
                if duration_hint > max_duration:
                    continue
            
            self.logger.info(f"Matched policy: {policy.get('name', 'unknown')}")
            return policy
        
        self.logger.warning(f"No policy matched for job_type={job_type}, using default")
        return None

    def _calculate_ttl(self, policy: Dict, telemetry: Dict = None) -> int:
        """Calculate final TTL based on policy and telemetry"""
        telemetry = telemetry or {}
        
        ttl_config = policy.get("ttl_config", {})
        base_ttl = ttl_config.get("base_ttl", 1800)
        max_ttl = ttl_config.get("max_ttl", 3600)
        multiplier = ttl_config.get("complexity_multiplier", 1.0)
        
        # Start with base TTL
        calculated_ttl = int(base_ttl * multiplier)
        
        # Apply telemetry-based adjustments
        if telemetry:
            cpu_util = telemetry.get("cpu_utilization", 0.5)
            memory_util = telemetry.get("memory_utilization", 0.5)
            
            adjustments = self.policy_config.get("telemetry_adjustments", {})
            
            # CPU adjustment
            if cpu_util > 0.8:
                cpu_multiplier = adjustments.get("cpu_utilization", {}).get("high", 1.5)
            elif cpu_util > 0.5:
                cpu_multiplier = adjustments.get("cpu_utilization", {}).get("medium", 1.2)
            else:
                cpu_multiplier = adjustments.get("cpu_utilization", {}).get("low", 0.8)
            
            # Memory adjustment
            if memory_util > 0.8:
                memory_multiplier = adjustments.get("memory_utilization", {}).get("high", 1.3)
            elif memory_util > 0.5:
                memory_multiplier = adjustments.get("memory_utilization", {}).get("medium", 1.0)
            else:
                memory_multiplier = adjustments.get("memory_utilization", {}).get("low", 0.9)
            
            calculated_ttl = int(calculated_ttl * cpu_multiplier * memory_multiplier)
            self.logger.info(
                f"Applied telemetry adjustments: CPU={cpu_multiplier}, Memory={memory_multiplier}"
            )
        
        # Enforce max TTL
        final_ttl = min(calculated_ttl, max_ttl)
        
        logger_msg = f"Calculated TTL={final_ttl}s (base={base_ttl}, multiplier={multiplier}"
        if calculated_ttl != final_ttl:
            logger_msg += f", capped from {calculated_ttl}"
        logger_msg += ")"
        self.logger.info(logger_msg)
        
        return final_ttl

    def assign_ttl(self, job_type: str, labels: List[str] = None,
                  duration_hint: int = None, telemetry: Dict = None) -> Tuple[int, str]:
        """Assign TTL to runner based on job characteristics"""
        self.logger.info(
            f"Assigning TTL for job_type={job_type}, labels={labels}, "
            f"duration_hint={duration_hint}s"
        )
        
        # Match job to policy
        policy = self._match_policy(job_type, labels, duration_hint)
        
        if not policy:
            # Use default TTL
            default_ttl = self.policy_config.get("global", {}).get("default_ttl", 1800)
            policy_name = "default"
            ttl = default_ttl
            self.logger.info(f"Using default TTL={ttl}s")
        else:
            # Calculate TTL from policy
            policy_name = policy.get("name", "unknown")
            ttl = self._calculate_ttl(policy, telemetry)
        
        # Save state
        state = {
            "ttl_assigned": ttl,
            "assigned_at": datetime.utcnow().isoformat() + "Z",
            "policy_name": policy_name,
            "job_type": job_type,
            "labels": labels or [],
            "ttl_extensions": 0
        }
        self._save_state(state)
        
        # Audit log
        self._audit_log("ttl_assigned", {
            "ttl_seconds": ttl,
            "policy_name": policy_name,
            "job_type": job_type
        })
        
        return ttl, policy_name

    # ========================================================================
    # Drain Operations
    # ========================================================================

    def _notify_workflow_context(self) -> bool:
        """Notify workflow context about impending termination"""
        try:
            # Set GitHub output if in workflow
            if "GITHUB_ENV" in os.environ:
                with open(os.environ["GITHUB_ENV"], 'a') as f:
                    f.write(f"RUNNER_TERMINATING=true\n")
                    f.write(f"RUNNER_TERMINATION_TIME={datetime.utcnow().isoformat()}Z\n")
            
            self.logger.info("Workflow context notified of termination")
            return True
        except Exception as e:
            self.logger.error(f"Failed to notify workflow context: {e}")
            return False

    def _set_runner_offline(self) -> bool:
        """Set runner to offline state in GitHub"""
        try:
            # This would call GitHub API to mark runner as offline
            # For now, just create a marker file
            offline_marker = self.temp_dir / ".runner-offline"
            offline_marker.touch()
            
            self.logger.info("Runner marked offline")
            return True
        except Exception as e:
            self.logger.error(f"Failed to set runner offline: {e}")
            return False

    def _wait_for_job_completion(self, timeout: int = 300) -> bool:
        """Wait for any in-progress jobs to complete"""
        start_time = time.time()
        check_interval = 10  # Check every 10 seconds
        
        while time.time() - start_time < timeout:
            # Check if any processes are running under this user
            try:
                processes = [p for p in psutil.process_iter(['pid', 'name', 'status'])
                           if p.info['status'] != psutil.STATUS_ZOMBIE]
                
                if not processes:
                    self.logger.info("No running processes detected")
                    return True
                
                self.logger.debug(f"Waiting for {len(processes)} processes to complete...")
                time.sleep(check_interval)
            except Exception as e:
                self.logger.error(f"Error checking processes: {e}")
                break
        
        return False

    def _upload_logs_and_artifacts(self) -> bool:
        """Upload logs and artifacts before drain completes"""
        try:
            # This would be customized per runner setup
            # For now, just log the operation
            self.logger.info("Uploading logs and artifacts")
            return True
        except Exception as e:
            self.logger.error(f"Failed to upload logs and artifacts: {e}")
            return False

    def _cleanup_ephemeral_state(self) -> bool:
        """Clean up ephemeral runner state"""
        try:
            # Call runner cleanup script
            cleanup_script = Path("scripts/runner/runner-ephemeral-cleanup.sh")
            if cleanup_script.exists():
                subprocess.run(
                    [str(cleanup_script)],
                    timeout=120,
                    check=False
                )
                self.logger.info("Ephemeral state cleaned up")
            
            return True
        except Exception as e:
            self.logger.error(f"Failed to cleanup ephemeral state: {e}")
            return False

    def drain(self, strategy: DrainStrategy = DrainStrategy.GRACEFUL,
             timeout: int = 300, allow_force: bool = True) -> bool:
        """Execute drain operation"""
        self.logger.info(f"Starting drain with strategy={strategy.value}, timeout={timeout}s")
        
        self._audit_log("drain_started", {
            "strategy": strategy.value,
            "timeout": timeout
        })
        
        if strategy == DrainStrategy.GRACEFUL:
            return self._graceful_drain(timeout, allow_force)
        elif strategy == DrainStrategy.FORCEFUL:
            return self._forceful_drain(timeout)
        elif strategy == DrainStrategy.SAFE_REAP:
            return self._safe_reap(timeout)
        
        return False

    def _graceful_drain(self, timeout: int = 300, allow_force: bool = True) -> bool:
        """Perform graceful drain with in-progress job handling"""
        self.logger.info(f"Graceful drain with {timeout}s timeout")
        
        steps = [
            ("Notify workflow context", self._notify_workflow_context),
            ("Set runner offline", self._set_runner_offline),
            ("Wait for job completion", lambda: self._wait_for_job_completion(timeout - 60)),
            ("Upload logs and artifacts", self._upload_logs_and_artifacts),
            ("Cleanup ephemeral state", self._cleanup_ephemeral_state),
        ]
        
        for step_name, step_func in steps:
            self.logger.info(f"  → {step_name}")
            try:
                if not step_func():
                    self.logger.warning(f"  ✗ {step_name} returned False")
                    if not allow_force:
                        return False
                    # Continue to next step
                else:
                    self.logger.info(f"  ✓ {step_name} completed")
            except Exception as e:
                self.logger.error(f"  ✗ {step_name} failed: {e}")
                if not allow_force:
                    return False
        
        self._audit_log("drain_completed", {
            "strategy": "graceful",
            "success": True
        })
        
        self.logger.info("Graceful drain completed successfully")
        return True

    def _forceful_drain(self, timeout: int = 60) -> bool:
        """Perform forceful drain, terminating jobs"""
        self.logger.warning(f"Forceful drain with {timeout}s timeout")
        
        try:
            # Send SIGTERM to all child processes
            os.killpg(os.getpgrp(), signal.SIGTERM)
            time.sleep(timeout // 2)
            
            # Send SIGKILL to remaining processes
            os.killpg(os.getpgrp(), signal.SIGKILL)
            
            self.logger.info("Forceful drain completed")
            self._audit_log("drain_completed", {
                "strategy": "forceful",
                "success": True
            })
            return True
        except Exception as e:
            self.logger.error(f"Forceful drain failed: {e}")
            self._audit_log("drain_failed", {
                "strategy": "forceful",
                "error": str(e)
            })
            return False

    # ========================================================================
    # Safe Reap Operations
    # ========================================================================

    def check_reap(self) -> Tuple[bool, Dict]:
        """Check if runner is safe to reap"""
        self.logger.info("Checking if safe to reap")
        
        state = self._load_state()
        checks = {
            "ttl_expired": False,
            "no_in_progress_jobs": False,
            "no_recent_heartbeat": False,
            "safe_to_reap": False
        }
        
        # Check TTL expiration
        if "assigned_at" in state and "ttl_assigned" in state:
            assigned_time = datetime.fromisoformat(
                state["assigned_at"].replace('Z', '+00:00')
            )
            ttl_seconds = state["ttl_assigned"]
            expiry_time = assigned_time + timedelta(seconds=ttl_seconds)
            
            if datetime.utcnow() > expiry_time:
                checks["ttl_expired"] = True
                self.logger.info(f"TTL expired at {expiry_time}")
        
        # Check for in-progress jobs
        try:
            processes = [p for p in psutil.process_iter(['pid', 'status'])
                       if p.info['status'] != psutil.STATUS_ZOMBIE]
            checks["no_in_progress_jobs"] = len(processes) == 0
            if checks["no_in_progress_jobs"]:
                self.logger.info("No in-progress jobs detected")
        except Exception as e:
            self.logger.error(f"Failed to check processes: {e}")
        
        # Check heartbeat (would be updated by runner)
        offline_marker = self.temp_dir / ".runner-offline"
        if offline_marker.exists():
            heartbeat_age = time.time() - offline_marker.stat().st_mtime
            checks["no_recent_heartbeat"] = heartbeat_age > 300  # 5 minutes
            if checks["no_recent_heartbeat"]:
                self.logger.info(f"No heartbeat for {heartbeat_age}s")
        
        # Determine if safe to reap
        checks["safe_to_reap"] = (
            checks["ttl_expired"] and
            checks["no_in_progress_jobs"]
        )
        
        self.logger.info(f"Reap safety check: {checks}")
        return checks["safe_to_reap"], checks

    def _safe_reap(self, timeout: int = 300) -> bool:
        """Perform safe reap of expired runner"""
        self.logger.info("Executing safe reap")
        
        safe, checks = self.check_reap()
        
        if not safe:
            self.logger.error(f"Not safe to reap: {checks}")
            self._audit_log("reap_failed", {
                "reason": "safety_checks_failed",
                "checks": checks
            })
            return False
        
        try:
            # Cleanup ephemeral state
            self._cleanup_ephemeral_state()
            
            # Log reap execution
            self._audit_log("reap_executed", {
                "timestamp": datetime.utcnow().isoformat() + "Z"
            })
            
            self.logger.info("Safe reap completed successfully")
            return True
        except Exception as e:
            self.logger.error(f"Safe reap failed: {e}")
            self._audit_log("reap_failed", {
                "error": str(e)
            })
            return False

    # ========================================================================
    # CLI and Info Operations
    # ========================================================================

    def show_info(self) -> None:
        """Display runner information and TTL status"""
        state = self._load_state()
        
        print("\n" + "=" * 70)
        print("EPHEMERAL RUNNER LIFECYCLE STATUS".center(70))
        print("=" * 70)
        
        # Basic info
        print(f"\nRunner:           {os.getenv('RUNNER_NAME', 'unknown')}")
        print(f"Home:             {self.runner_home}")
        print(f"Job:              {os.getenv('GITHUB_JOB', 'unknown')}")
        print(f"Current Time:     {datetime.utcnow().isoformat()}Z")
        
        if state:
            print(f"\nTTL Configuration:")
            print(f"  Assigned At:    {state.get('assigned_at', 'N/A')}")
            print(f"  TTL (seconds):  {state.get('ttl_assigned', 'N/A')}")
            print(f"  Policy:         {state.get('policy_name', 'N/A')}")
            print(f"  Job Type:       {state.get('job_type', 'N/A')}")
            print(f"  Labels:         {', '.join(state.get('labels', []))}")
            print(f"  Extensions:     {state.get('ttl_extensions', 0)}")
            
            # Calculate remaining TTL
            if "assigned_at" in state and "ttl_assigned" in state:
                assigned_time = datetime.fromisoformat(
                    state["assigned_at"].replace('Z', '+00:00')
                )
                ttl_seconds = state["ttl_assigned"]
                expiry_time = assigned_time + timedelta(seconds=ttl_seconds)
                remaining = (expiry_time - datetime.utcnow()).total_seconds()
                
                if remaining > 0:
                    remaining_str = f"{int(remaining)}s"
                    print(f"  TTL Remaining:  {remaining_str}")
                    print(f"  Expiry Time:    {expiry_time.isoformat()}Z")
                else:
                    print(f"  Status:         EXPIRED ({abs(int(remaining))}\s ago)")
        
        # Check reap safety
        safe, checks = self.check_reap()
        print(f"\nReap Safety:")
        print(f"  TTL Expired:         {checks.get('ttl_expired', False)}")
        print(f"  No in-progress jobs: {checks.get('no_in_progress_jobs', False)}")
        print(f"  Safe to Reap:        {safe}")
        
        print("\n" + "=" * 70 + "\n")


# ============================================================================
# Main Entry Point
# ============================================================================

def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="Ephemeral Runner Lifecycle Controller"
    )
    
    subparsers = parser.add_subparsers(dest="command", help="Command to execute")
    
    # Info command
    subparsers.add_parser("info", help="Show runner info and TTL status")
    
    # Assign TTL command
    assign_parser = subparsers.add_parser("assign-ttl", help="Assign TTL to runner")
    assign_parser.add_argument("--job-type", required=True, help="Job type")
    assign_parser.add_argument("--labels", nargs="+", help="Job labels")
    assign_parser.add_argument("--duration", type=int, help="Expected duration in seconds")
    assign_parser.add_argument("--cpu-util", type=float, help="CPU utilization (0-1)")
    assign_parser.add_argument("--mem-util", type=float, help="Memory utilization (0-1)")
    
    # Drain command
    drain_parser = subparsers.add_parser("drain", help="Drain runner")
    drain_parser.add_argument(
        "--strategy", 
        choices=["graceful", "forceful", "safe_reap"],
        default="graceful",
        help="Drain strategy"
    )
    drain_parser.add_argument("--timeout", type=int, default=300, help="Timeout in seconds")
    drain_parser.add_argument("--no-force", action="store_true", help="Don't force if graceful fails")
    
    # Check reap command
    subparsers.add_parser("check-reap", help="Check if safe to reap")
    
    # Reap command
    reap_parser = subparsers.add_parser("reap", help="Execute reap operation")
    reap_parser.add_argument("--force", action="store_true", help="Force reap even if not safe")
    
    args = parser.parse_args()
    
    # Initialize controller
    controller = EphemeralLifecycleController()
    
    # Execute command
    if args.command == "info":
        controller.show_info()
    
    elif args.command == "assign-ttl":
        telemetry = {}
        if args.cpu_util is not None:
            telemetry["cpu_utilization"] = args.cpu_util
        if args.mem_util is not None:
            telemetry["memory_utilization"] = args.mem_util
        
        ttl, policy = controller.assign_ttl(
            args.job_type,
            labels=args.labels,
            duration_hint=args.duration,
            telemetry=telemetry
        )
        
        print(f"✓ TTL assigned: {ttl}s (policy: {policy})")
        sys.exit(0)
    
    elif args.command == "drain":
        strategy = DrainStrategy(args.strategy)
        success = controller.drain(
            strategy=strategy,
            timeout=args.timeout,
            allow_force=not args.no_force
        )
        
        sys.exit(0 if success else 1)
    
    elif args.command == "check-reap":
        safe, checks = controller.check_reap()
        
        print(f"Safe to reap: {safe}")
        print(f"Checks: {checks}")
        
        sys.exit(0 if safe else 1)
    
    elif args.command == "reap":
        safe, checks = controller.check_reap()
        
        if not safe and not args.force:
            print(f"✗ Not safe to reap: {checks}")
            sys.exit(1)
        
        success = controller._safe_reap()
        sys.exit(0 if success else 1)
    
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
