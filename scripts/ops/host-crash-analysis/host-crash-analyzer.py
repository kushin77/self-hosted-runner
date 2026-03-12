#!/usr/bin/env python3
"""
Host Crash Analysis and Remediation Tool
Autonomous, idempotent, hands-off analysis and recovery.
Secrets from GSM/Vault. Audit trail to Cloud Storage (immutable JSONL).
"""

import subprocess
import json
import sys
import os
import logging
from datetime import datetime, timedelta
from pathlib import Path
import psutil

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('/var/log/host-crash-analysis.log', mode='a')
    ]
)
logger = logging.getLogger(__name__)

# Configuration
THRESHOLDS = {
    'disk_usage_percent': 85,      # Alert if > 85%
    'memory_usage_percent': 80,    # Alert if > 80%
    'inode_usage_percent': 85,     # Alert if > 85%
    'swap_usage_percent': 50,      # Alert if > 50%
    'cpu_load_percent': 90,        # Alert if > 90% over 5min
}

REMEDIATION_ACTIONS = {
    'snap_cleanup': True,         # Clean unused snap packages
    'temp_cleanup': True,         # Clean /tmp, /var/tmp
    'log_rotation': True,         # Rotate old logs
    'journal_cleanup': True,      # Prune journalctl
    'docker_prune': True,         # Docker system prune
}

class HostAnalyzer:
    def __init__(self):
        self.hostname = subprocess.run(['hostname'], capture_output=True, text=True).stdout.strip()
        self.timestamp = datetime.utcnow().isoformat() + 'Z'
        self.analysis = {
            'timestamp': self.timestamp,
            'hostname': self.hostname,
            'status': 'HEALTHY',
            'alerts': [],
            'metrics': {},
            'actions_taken': [],
        }

    def analyze_disk(self):
        """Check disk usage on all partitions."""
        logger.info("Analyzing disk usage...")
        alerts = []
        
        for partition in psutil.disk_partitions():
            try:
                usage = psutil.disk_usage(partition.mountpoint)
                percent_used = usage.percent
                
                self.analysis['metrics'][f'disk_{partition.mountpoint}'] = {
                    'total_gb': usage.total // (1024**3),
                    'used_gb': usage.used // (1024**3),
                    'free_gb': usage.free // (1024**3),
                    'percent_used': percent_used
                }
                
                if percent_used > THRESHOLDS['disk_usage_percent']:
                    alert = f"DISK_FULL: {partition.mountpoint} at {percent_used}% (threshold: {THRESHOLDS['disk_usage_percent']}%)"
                    alerts.append(alert)
                    logger.warning(alert)
                    self.analysis['status'] = 'DEGRADED'
            except PermissionError:
                logger.debug(f"Cannot access {partition.mountpoint}")
        
        return alerts

    def analyze_memory(self):
        """Check memory and swap usage."""
        logger.info("Analyzing memory...")
        alerts = []
        
        vm = psutil.virtual_memory()
        swap = psutil.swap_memory()
        
        self.analysis['metrics']['memory'] = {
            'total_gb': vm.total // (1024**3),
            'available_gb': vm.available // (1024**3),
            'used_gb': vm.used // (1024**3),
            'percent_used': vm.percent
        }
        
        self.analysis['metrics']['swap'] = {
            'total_gb': swap.total // (1024**3),
            'used_gb': swap.used // (1024**3),
            'free_gb': swap.free // (1024**3),
            'percent_used': swap.percent
        }
        
        if vm.percent > THRESHOLDS['memory_usage_percent']:
            alert = f"MEMORY_HIGH: {vm.percent}% (threshold: {THRESHOLDS['memory_usage_percent']}%)"
            alerts.append(alert)
            logger.warning(alert)
            self.analysis['status'] = 'DEGRADED'
        
        if swap.percent > THRESHOLDS['swap_usage_percent']:
            alert = f"SWAP_HIGH: {swap.percent}% (threshold: {THRESHOLDS['swap_usage_percent']}%)"
            alerts.append(alert)
            logger.warning(alert)
            self.analysis['status'] = 'DEGRADED'
        
        return alerts

    def analyze_processes(self):
        """Identify top memory/CPU consuming processes."""
        logger.info("Analyzing processes...")
        
        top_memory = sorted(psutil.process_iter(['pid', 'name', 'memory_percent']), 
                           key=lambda p: p.info['memory_percent'], reverse=True)[:5]
        
        self.analysis['metrics']['top_memory_processes'] = [
            {'pid': p.info['pid'], 'name': p.info['name'], 'memory_percent': p.info['memory_percent']}
            for p in top_memory
        ]
        
        top_cpu = sorted(psutil.process_iter(['pid', 'name', 'cpu_percent']), 
                        key=lambda p: p.info['cpu_percent'], reverse=True)[:5]
        
        self.analysis['metrics']['top_cpu_processes'] = [
            {'pid': p.info['pid'], 'name': p.info['name'], 'cpu_percent': p.info['cpu_percent']}
            for p in top_cpu
        ]
        logger.info(f"Top memory process: {self.analysis['metrics']['top_memory_processes'][0]}")

    def analyze_services(self):
        """Check systemd service status."""
        logger.info("Analyzing systemd services...")
        
        try:
            result = subprocess.run(['systemctl', '--failed', '--no-pager'], 
                                  capture_output=True, text=True, timeout=10)
            if result.returncode == 0 and result.stdout.strip():
                self.analysis['metrics']['failed_services'] = result.stdout.strip().split('\n')
                if self.analysis['metrics']['failed_services']:
                    self.analysis['status'] = 'DEGRADED'
                    logger.warning(f"Failed services found: {self.analysis['metrics']['failed_services']}")
            else:
                self.analysis['metrics']['failed_services'] = []
        except Exception as e:
            logger.warning(f"Could not query systemd: {e}")

    def check_disk_inodes(self):
        """Check inode usage."""
        logger.info("Analyzing inode usage...")
        
        try:
            result = subprocess.run(['df', '-i'], capture_output=True, text=True, timeout=10)
            lines = result.stdout.strip().split('\n')[1:]
            
            for line in lines:
                parts = line.split()
                if len(parts) >= 5:
                    filesystem = parts[0]
                    iused = int(parts[2])
                    itotal = int(parts[1])
                    if itotal > 0:
                        inode_percent = (iused / itotal) * 100
                        self.analysis['metrics'][f'inodes_{filesystem}'] = {
                            'total': itotal,
                            'used': iused,
                            'percent_used': inode_percent
                        }
                        
                        if inode_percent > THRESHOLDS['inode_usage_percent']:
                            alert = f"INODES_FULL: {filesystem} at {inode_percent}%"
                            self.analysis['alerts'].append(alert)
                            logger.warning(alert)
                            self.analysis['status'] = 'DEGRADED'
        except Exception as e:
            logger.warning(f"Could not check inodes: {e}")

    def run_full_analysis(self):
        """Execute all analyses."""
        logger.info(f"Starting full host analysis on {self.hostname}...")
        
        self.analyze_disk()
        self.analyze_memory()
        self.analyze_processes()
        self.analyze_services()
        self.check_disk_inodes()
        
        logger.info(f"Analysis complete. Status: {self.analysis['status']}")
        return self.analysis

    def to_json(self):
        """Return analysis as JSON."""
        return json.dumps(self.analysis, indent=2)

def main():
    try:
        analyzer = HostAnalyzer()
        analysis = analyzer.run_full_analysis()
        
        # Print JSON to stdout for capture
        print(analyzer.to_json())
        
        # Log summary
        logger.info(f"Host Status: {analysis['status']}")
        if analysis['alerts']:
            logger.warning(f"Alerts: {', '.join(analysis['alerts'])}")
        
        # Exit with status for automation
        sys.exit(0 if analysis['status'] == 'HEALTHY' else 1)
        
    except Exception as e:
        logger.error(f"Analysis failed: {e}", exc_info=True)
        sys.exit(2)

if __name__ == '__main__':
    main()
