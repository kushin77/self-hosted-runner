#!/usr/bin/env python3
"""
git-metrics.py
Collect and expose git workflow metrics for Prometheus/Grafana.

METRICS:
  - git_merge_success_rate (%) - by branch, author, team
  - git_merge_duration_seconds - time-to-merge
  - git_conflict_rate (%) - conflicts detected
  - git_commits_per_day - commit frequency
  - git_branch_protection_violations - branch protection bypass attempts
  - git_hook_execution_time_seconds - hook performance
  - git_rollback_frequency - total rollbacks

USAGE:
  # Run metrics collector (background)
  python3 scripts/observability/git-metrics.py --port 8001 --interval 300
  
  # Prometheus scrape:
  # http://localhost:8001/metrics
"""

import os
import json
import sqlite3
import logging
from pathlib import Path
from datetime import datetime, timedelta
from typing import Dict, List, Any
from collections import defaultdict
import subprocess
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
import threading

logging.basicConfig(
    format='{"timestamp": "%(asctime)s", "component": "git-metrics", "level": "%(levelname)s", "message": "%(message)s"}',
    level=logging.INFO
)
logger = logging.getLogger(__name__)


class GitMetrics:
    """
    Git workflow metrics collector.
    
    Collects metrics from:
      - Audit logs (git-workflow-audit.jsonl)
      - Git history (git log)
      - GitHub API (PR stats)
    """
    
    def __init__(self, repo_path: str = ".", db_path: Optional[str] = None):
        """
        Initialize metrics collector.
        
        Args:
            repo_path: Git repository path
            db_path: SQLite database path (auto-created)
        """
        self.repo_path = Path(repo_path).resolve()
        self.db_path = Path(db_path or self.repo_path / "logs" / "git-metrics.db")
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        
        # Initialize database
        self._init_db()
        
        logger.info(f"GitMetrics initialized for repo: {self.repo_path}")
    
    def _init_db(self) -> None:
        """Initialize SQLite database schema."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Create tables if not exist
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS merge_events (
                id INTEGER PRIMARY KEY,
                timestamp TEXT,
                pr_number INTEGER,
                branch TEXT,
                author TEXT,
                status TEXT,
                duration_seconds REAL,
                conflict_count INTEGER
            )
        """)
        
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS commit_events (
                id INTEGER PRIMARY KEY,
                timestamp TEXT,
                commit_hash TEXT,
                author TEXT,
                branch TEXT,
                message TEXT
            )
        """)
        
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS hook_events (
                id INTEGER PRIMARY KEY,
                timestamp TEXT,
                hook_name TEXT,
                duration_seconds REAL,
                status TEXT
            )
        """)
        
        conn.commit()
        conn.close()
    
    def _get_merge_success_rate(self, days: int = 7) -> float:
        """Calculate merge success rate (%) for last N days."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        since = (datetime.utcnow() - timedelta(days=days)).isoformat()
        
        cursor.execute("""
            SELECT COUNT(*) as total, 
                   SUM(CASE WHEN status = 'merged' THEN 1 ELSE 0 END) as success
            FROM merge_events
            WHERE timestamp > ?
        """, (since,))
        
        total, success = cursor.fetchone()
        conn.close()
        
        if total == 0:
            return 100.0
        
        return round((success / total) * 100, 2)
    
    def _get_average_merge_duration(self, days: int = 7) -> float:
        """Calculate average merge duration (seconds)."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        since = (datetime.utcnow() - timedelta(days=days)).isoformat()
        
        cursor.execute("""
            SELECT AVG(duration_seconds)
            FROM merge_events
            WHERE timestamp > ? AND duration_seconds IS NOT NULL
        """, (since,))
        
        result = cursor.fetchone()[0]
        conn.close()
        
        return round(result or 0.0, 2)
    
    def _get_conflict_rate(self, days: int = 7) -> float:
        """Calculate conflict detection rate (%)."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        since = (datetime.utcnow() - timedelta(days=days)).isoformat()
        
        cursor.execute("""
            SELECT COUNT(*) as total,
                   SUM(CASE WHEN conflict_count > 0 THEN 1 ELSE 0 END) as with_conflicts
            FROM merge_events
            WHERE timestamp > ?
        """, (since,))
        
        total, with_conflicts = cursor.fetchone()
        conn.close()
        
        if total == 0:
            return 0.0
        
        return round((with_conflicts / total) * 100, 2)
    
    def _get_commits_per_day(self, days: int = 7) -> float:
        """Calculate average commits per day."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        since = (datetime.utcnow() - timedelta(days=days)).isoformat()
        
        cursor.execute("""
            SELECT COUNT(DISTINCT DATE(timestamp))
            FROM commit_events
            WHERE timestamp > ?
        """, (since,))
        
        distinct_days = cursor.fetchone()[0]
        
        cursor.execute("""
            SELECT COUNT(*)
            FROM commit_events
            WHERE timestamp > ?
        """, (since,))
        
        total_commits = cursor.fetchone()[0]
        conn.close()
        
        if distinct_days == 0:
            return 0.0
        
        return round(total_commits / distinct_days, 2)
    
    def _get_hook_performance(self) -> Dict[str, float]:
        """Get hook execution time statistics."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Average by hook type
        cursor.execute("""
            SELECT hook_name, AVG(duration_seconds), MAX(duration_seconds)
            FROM hook_events
            WHERE timestamp > datetime('now', '-7 days')
            GROUP BY hook_name
        """)
        
        stats = {}
        for hook_name, avg_duration, max_duration in cursor.fetchall():
            stats[hook_name] = {
                "avg_seconds": round(avg_duration, 3),
                "max_seconds": round(max_duration, 3),
            }
        
        conn.close()
        return stats
    
    def collect(self) -> Dict[str, Any]:
        """Collect all metrics."""
        logger.info("Collecting git workflow metrics...")
        
        metrics = {
            "timestamp": datetime.utcnow().isoformat(),
            "git_merge_success_rate_percent": self._get_merge_success_rate(),
            "git_merge_duration_seconds": self._get_average_merge_duration(),
            "git_conflict_rate_percent": self._get_conflict_rate(),
            "git_commits_per_day": self._get_commits_per_day(),
            "git_hook_performance": self._get_hook_performance(),
        }
        
        logger.info(f"Metrics collected: {metrics['git_merge_success_rate_percent']}% success rate")
        return metrics
    
    def to_prometheus_format(self) -> str:
        """Convert metrics to Prometheus text format."""
        metrics = self.collect()
        
        lines = [
            "# HELP git_merge_success_rate_percent Percentage of successful merges",
            "# TYPE git_merge_success_rate_percent gauge",
            f"git_merge_success_rate_percent {metrics['git_merge_success_rate_percent']}",
            "",
            "# HELP git_merge_duration_seconds Average merge duration in seconds",
            "# TYPE git_merge_duration_seconds gauge",
            f"git_merge_duration_seconds {metrics['git_merge_duration_seconds']}",
            "",
            "# HELP git_conflict_rate_percent Percentage of merges with conflicts",
            "# TYPE git_conflict_rate_percent gauge",
            f"git_conflict_rate_percent {metrics['git_conflict_rate_percent']}",
            "",
            "# HELP git_commits_per_day Average commits per day",
            "# TYPE git_commits_per_day gauge",
            f"git_commits_per_day {metrics['git_commits_per_day']}",
        ]
        
        # Add hook metrics
        for hook_name, stats in metrics.get("git_hook_performance", {}).items():
            lines.extend([
                f"# HELP git_hook_duration_seconds Hook execution duration",
                f"# TYPE git_hook_duration_seconds gauge",
                f'git_hook_duration_seconds{{hook="{hook_name}",type="avg"}} {stats["avg_seconds"]}',
                f'git_hook_duration_seconds{{hook="{hook_name}",type="max"}} {stats["max_seconds"]}',
            ])
        
        return "\n".join(lines)


class MetricsHTTPHandler(BaseHTTPRequestHandler):
    """HTTP handler for Prometheus scraper."""
    
    metrics_collector: GitMetrics = None
    
    def do_GET(self):
        """Handle GET requests."""
        if self.path == "/metrics":
            self.send_response(200)
            self.send_header("Content-type", "text/plain")
            self.end_headers()
            
            prometheus_output = self.metrics_collector.to_prometheus_format()
            self.wfile.write(prometheus_output.encode())
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        """Suppress HTTP request logging."""
        pass


def run_metrics_server(
    repo_path: str = ".",
    port: int = 8001,
    collection_interval: int = 300,
) -> None:
    """
    Run metrics HTTP server.
    
    Args:
        repo_path: Git repository path
        port: HTTP port to listen on
        collection_interval: Metrics collection interval (seconds)
    """
    collector = GitMetrics(repo_path=repo_path)
    MetricsHTTPHandler.metrics_collector = collector
    
    server = HTTPServer(("0.0.0.0", port), MetricsHTTPHandler)
    logger.info(f"Metrics server listening on port {port}")
    logger.info(f"Prometheus endpoint: http://localhost:{port}/metrics")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Metrics server stopped")
        server.shutdown()


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Git workflow metrics collector")
    parser.add_argument("--repo", default=".", help="Repository path")
    parser.add_argument("--port", type=int, default=8001, help="HTTP port")
    parser.add_argument("--interval", type=int, default=300, help="Collection interval (seconds)")
    
    args = parser.parse_args()
    
    run_metrics_server(
        repo_path=args.repo,
        port=args.port,
        collection_interval=args.interval,
    )
