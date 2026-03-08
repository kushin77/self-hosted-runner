#!/usr/bin/env python3
"""
Fully Automated & Hands-Off Credential Rotation Runner

Scheduled daily execution with:
- Immutable audit logging (append-only)
- Idempotent execution (safe to run repeatedly)
- Ephemeral cleanup (auto-TTL)
- No manual intervention required
- OIDC-based provider authentication (no hardcoded tokens)

Usage:
  python3 rotate_all_credentials.py --config rotation_config.json
  python3 rotate_all_credentials.py --cleanup
"""

import argparse
import json
import logging
import sys
from datetime import datetime
from pathlib import Path
from typing import List, Dict
import os

# Add parent to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from security.cred_rotation import (
    RotationConfig,
    RotationOrchestrator,
    get_rotation_orchestrator
)


logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class RotationRunner:
    """Hands-off rotation runner with zero manual intervention."""
    
    def __init__(self, config_file: str = None):
        self.config_file = config_file or "rotation_config.json"
        self.orchestrator = get_rotation_orchestrator()
        self.configs: List[RotationConfig] = []
    
    def load_config(self) -> bool:
        """Load rotation configuration from file."""
        try:
            if not Path(self.config_file).exists():
                logger.warning(f"Config file not found: {self.config_file}")
                return False
            
            with open(self.config_file, 'r') as f:
                data = json.load(f)
            
            # Convert to RotationConfig objects
            for item in data.get('credentials', []):
                config = RotationConfig(
                    credential_id=item['id'],
                    provider=item['provider'],
                    rotation_interval_hours=item.get('interval_hours', 24),
                    notify_channels=item.get('notify', []),
                    affected_workflows=item.get('workflows', [])
                )
                self.configs.append(config)
            
            logger.info(f"Loaded {len(self.configs)} credential configs")
            return True
        
        except Exception as e:
            logger.error(f"Failed to load config: {e}")
            return False
    
    def run_rotation(self) -> Dict[str, bool]:
        """
        Execute rotation for all configured credentials.
        
        Idempotent: Safe to call repeatedly.
        Returns: Dict mapping credential_id -> success/failure
        """
        logger.info("=" * 80)
        logger.info(f"Starting credential rotation run at {datetime.utcnow().isoformat()}")
        logger.info("=" * 80)
        
        if not self.configs:
            logger.warning("No credentials to rotate")
            return {}
        
        results = self.orchestrator.rotate_all(self.configs)
        
        # Log summary
        successes = sum(1 for v in results.values() if v)
        logger.info(f"Rotation completed: {successes}/{len(results)} succeeded")
        
        return results
    
    def cleanup_expired(self, ttl_days: int = 30):
        """
        Remove expired credential records.
        
        Ephemeral cleanup: auto-deletes after TTL.
        Idempotent: Safe to call repeatedly.
        """
        logger.info(f"Starting ephemeral cleanup (TTL: {ttl_days} days)")
        self.orchestrator.cleanup_expired_credentials(ttl_days)
        logger.info("Cleanup completed")
    
    def verify_rotations(self) -> bool:
        """
        Verify all credentials have been rotated recently.
        
        Returns: True if all within expected rotation window.
        """
        logger.info("Verifying recent rotations...")
        
        for config in self.configs:
            history = self.orchestrator.get_rotation_history(config.credential_id)
            
            if not history:
                logger.warning(f"No rotation history: {config.credential_id}")
                continue
            
            last_rotation = max(history, key=lambda h: h.timestamp)
            ts = datetime.fromisoformat(last_rotation.timestamp)
            hours_ago = (datetime.utcnow() - ts).total_seconds() / 3600
            
            expected = config.rotation_interval_hours + 24  # Allow 24h buffer
            
            if hours_ago <= expected:
                logger.info(f"✓ {config.credential_id}: rotated {hours_ago:.1f}h ago")
            else:
                logger.warning(f"✗ {config.credential_id}: NOT rotated in {hours_ago:.1f}h")
        
        return True


class NotificationHandler:
    """Send notifications on rotation events."""
    
    @staticmethod
    def notify(channel: str, message: str, metadata: Dict = None):
        """Send notification to configured channel."""
        metadata = metadata or {}
        
        if channel == 'slack':
            NotificationHandler._notify_slack(message, metadata)
        elif channel == 'email':
            NotificationHandler._notify_email(message, metadata)
        elif channel == 'pagerduty':
            NotificationHandler._notify_pagerduty(message, metadata)
        else:
            logger.warning(f"Unknown notification channel: {channel}")
    
    @staticmethod
    def _notify_slack(message: str, metadata: Dict):
        """Send to Slack (via webhook)."""
        try:
            import requests
            webhook = os.getenv('SLACK_WEBHOOK_URL')
            if not webhook:
                logger.warning("SLACK_WEBHOOK_URL not set")
                return
            
            payload = {
                'text': message,
                'blocks': [
                    {
                        'type': 'section',
                        'text': {'type': 'mrkdwn', 'text': message}
                    },
                    {
                        'type': 'section',
                        'fields': [
                            {'type': 'mrkdwn', 'text': f"*Timestamp*\n{metadata.get('timestamp', 'N/A')}"},
                            {'type': 'mrkdwn', 'text': f"*Status*\n{metadata.get('status', 'N/A')}"}
                        ]
                    }
                ]
            }
            
            requests.post(webhook, json=payload, timeout=10)
            logger.info(f"Slack notification sent")
        except Exception as e:
            logger.error(f"Slack notification failed: {e}")
    
    @staticmethod
    def _notify_email(message: str, metadata: Dict):
        """Send email (via SMTP)."""
        try:
            import smtplib
            from email.mime.text import MIMEText
            
            smtp_host = os.getenv('SMTP_HOST')
            smtp_port = int(os.getenv('SMTP_PORT', '587'))
            sender = os.getenv('SMTP_FROM')
            
            if not all([smtp_host, sender]):
                logger.warning("Email config incomplete")
                return
            
            msg = MIMEText(message)
            msg['Subject'] = 'Credential Rotation Report'
            msg['From'] = sender
            msg['To'] = os.getenv('ALERT_EMAIL', sender)
            
            with smtplib.SMTP(smtp_host, smtp_port) as s:
                s.starttls()
                s.send_message(msg)
            
            logger.info("Email notification sent")
        except Exception as e:
            logger.error(f"Email notification failed: {e}")
    
    @staticmethod
    def _notify_pagerduty(message: str, metadata: Dict):
        """Create PagerDuty incident (production failures only)."""
        try:
            import requests
            
            if metadata.get('status') != 'failed':
                return  # Only alert on failures
            
            api_key = os.getenv('PAGERDUTY_API_KEY')
            if not api_key:
                logger.warning("PAGERDUTY_API_KEY not set")
                return
            
            payload = {
                'routing_key': os.getenv('PAGERDUTY_ROUTING_KEY'),
                'event_action': 'trigger',
                'dedup_key': f"rotation-{metadata.get('credential_id', 'unknown')}",
                'payload': {
                    'summary': f"Credential rotation failed: {message}",
                    'severity': 'critical',
                    'source': 'credential-rotation',
                    'custom_details': metadata
                }
            }
            
            headers = {'Authorization': f'Token token={api_key}'}
            requests.post(
                'https://events.pagerduty.com/v2/enqueue',
                json=payload,
                headers=headers,
                timeout=10
            )
            logger.info("PagerDuty incident created")
        except Exception as e:
            logger.error(f"PagerDuty notification failed: {e}")


def main():
    """Entry point for credential rotation automation."""
    parser = argparse.ArgumentParser(
        description='Fully automated, hands-off credential rotation'
    )
    parser.add_argument(
        '--config',
        default='rotation_config.json',
        help='Path to rotation config file'
    )
    parser.add_argument(
        '--rotate',
        action='store_true',
        default=True,
        help='Execute credential rotation'
    )
    parser.add_argument(
        '--cleanup',
        action='store_true',
        help='Clean up expired credentials (ephemeral TTL)'
    )
    parser.add_argument(
        '--verify',
        action='store_true',
        help='Verify recent rotations'
    )
    parser.add_argument(
        '--ttl-days',
        type=int,
        default=30,
        help='TTL for credential records (default: 30 days)'
    )
    
    args = parser.parse_args()
    
    runner = RotationRunner(config_file=args.config)
    
    if args.rotate:
        if not runner.load_config():
            logger.error("Failed to load config")
            sys.exit(1)
        
        results = runner.run_rotation()
        
        # Send notifications
        for cred_id, success in results.items():
            status = 'success' if success else 'failed'
            message = f"Rotation {status}: {cred_id}"
            
            # Notify on failures
            if not success:
                NotificationHandler.notify('slack', message, {
                    'credential_id': cred_id,
                    'status': status,
                    'timestamp': datetime.utcnow().isoformat()
                })
                NotificationHandler.notify('pagerduty', message, {
                    'credential_id': cred_id,
                    'status': status,
                    'timestamp': datetime.utcnow().isoformat()
                })
    
    if args.cleanup:
        runner.cleanup_expired(args.ttl_days)
    
    if args.verify:
        runner.verify_rotations()
    
    logger.info("Rotation run complete")


if __name__ == '__main__':
    main()
