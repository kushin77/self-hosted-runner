#!/usr/bin/env python3
"""
NexusShield CLI - Command line interface for credential management
Refactored to use generated Python SDK
"""

import os
import sys
import argparse
import json
from typing import Optional, Dict, Any

# Import from generated SDK
from nexusshield import (
    create_client,
    NexusShieldClient,
    Provider,
    Status,
)


class NexusShieldCLI:
    """NexusShield CLI application"""

    def __init__(self):
        self.client: NexusShieldClient = self._init_client()

    @staticmethod
    def _init_client() -> NexusShieldClient:
        """Initialize SDK client from environment"""
        api_key = os.getenv('NEXUS_API_KEY')
        base_url = os.getenv('NEXUS_API_URL', 'https://api.nexusshield.cloud')

        if not api_key:
            raise RuntimeError(
                'NEXUS_API_KEY environment variable is required. '
                'Get your API key from https://portal.nexusshield.cloud'
            )

        return create_client(base_url=base_url, api_key=api_key)

    def _print_response(self, response: Any, format_: str = 'json') -> None:
        """Print response in specified format"""
        if format_ == 'json':
            if hasattr(response, '__dict__'):
                print(json.dumps(response.__dict__, indent=2, default=str))
            else:
                print(json.dumps(response, indent=2, default=str))
        elif format_ == 'table':
            # Simple table format for lists
            if isinstance(response, dict) and 'credentials' in response:
                print('\nCredentials:')
                print(f"{'ID':<20} {'Name':<30} {'Type':<15} {'Status':<10}")
                print('-' * 75)
                for cred in response.get('credentials', []):
                    print(
                        f"{cred.get('id', ''):<20} "
                        f"{cred.get('name', ''):<30} "
                        f"{cred.get('type', ''):<15} "
                        f"{cred.get('status', ''):<10}"
                    )
        else:
            print(response)

    # Health command
    def health(self, args: argparse.Namespace) -> int:
        """Check API health status"""
        try:
            response = self.client.get_health()
            if response.is_success():
                print(f"✓ NexusShield API is {response.data['status']}")
                return 0
            else:
                print(f"✗ Health check failed: {response.error.message}")
                return 1
        except Exception as e:
            print(f"✗ Error checking health: {str(e)}")
            return 1

    # Credential commands
    def credential_list(self, args: argparse.Namespace) -> int:
        """List all credentials"""
        try:
            filters = {}
            if args.type:
                filters['type'] = args.type
            if args.provider:
                filters['provider'] = args.provider
            if args.status:
                filters['status'] = args.status

            response = self.client.list_credentials(**filters)

            if response.is_success():
                self._print_response(response.data, format_=args.format)
                return 0
            else:
                print(f"✗ Failed to list credentials: {response.error.message}")
                return 1
        except Exception as e:
            print(f"✗ Error listing credentials: {str(e)}")
            return 1

    def credential_get(self, args: argparse.Namespace) -> int:
        """Get credential details"""
        try:
            response = self.client.get_credential(args.id)

            if response.is_success():
                self._print_response(response.data, format_=args.format)
                return 0
            else:
                print(f"✗ Credential not found: {response.error.message}")
                return 1
        except Exception as e:
            print(f"✗ Error getting credential: {str(e)}")
            return 1

    def credential_create(self, args: argparse.Namespace) -> int:
        """Create new credential"""
        try:
            config = {}
            if args.config:
                config = json.loads(args.config)

            response = self.client.create_credential(
                name=args.name,
                type_=args.type,
                provider=args.provider,
                config=config,
            )

            if response.is_success():
                print(f"✓ Created credential: {response.data['id']}")
                self._print_response(response.data, format_=args.format)
                return 0
            else:
                print(f"✗ Failed to create credential: {response.error.message}")
                return 1
        except Exception as e:
            print(f"✗ Error creating credential: {str(e)}")
            return 1

    def credential_delete(self, args: argparse.Namespace) -> int:
        """Delete credential"""
        try:
            if not args.force:
                confirm = input(f"Delete credential {args.id}? (y/N): ")
                if confirm.lower() != 'y':
                    print("Cancelled.")
                    return 0

            response = self.client.delete_credential(args.id)

            if response.is_success():
                print(f"✓ Deleted credential: {args.id}")
                return 0
            else:
                print(f"✗ Failed to delete credential: {response.error.message}")
                return 1
        except Exception as e:
            print(f"✗ Error deleting credential: {str(e)}")
            return 1

    def credential_rotate(self, args: argparse.Namespace) -> int:
        """Rotate credential"""
        try:
            response = self.client.rotate_credential(
                credential_id=args.id,
                force=args.force,
            )

            if response.is_success():
                print(f"✓ Rotated credential: {args.id}")
                print(f"  Rotated at: {response.data['rotated_at']}")
                print(f"  Expires at: {response.data['expires_at']}")
                return 0
            else:
                if response.error and response.error.retryable:
                    print(
                        f"⚠ Rotation in progress (retryable). "
                        f"Retry after {response.error.retryAfter}ms"
                    )
                else:
                    print(f"✗ Failed to rotate credential: {response.error.message}")
                return 1
        except Exception as e:
            print(f"✗ Error rotating credential: {str(e)}")
            return 1

    # Audit command
    def audit_log(self, args: argparse.Namespace) -> int:
        """Get audit trail"""
        try:
            response = self.client.get_audit_log(
                limit=args.limit,
                offset=args.offset,
                resource_id=args.resource_id,
                action=args.action,
            )

            if response.is_success():
                events = response.data.get('events', [])
                print(f"Found {len(events)} audit events:")
                for event in events:
                    print(
                        f"  {event['timestamp']}: {event['action']} "
                        f"(actor: {event.get('actor_id', 'system')})"
                    )
                return 0
            else:
                print(f"✗ Failed to get audit log: {response.error.message}")
                return 1
        except Exception as e:
            print(f"✗ Error getting audit log: {str(e)}")
            return 1


def main() -> int:
    """Main CLI entry point"""
    parser = argparse.ArgumentParser(
        description='NexusShield - Enterprise credential management CLI',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Examples:
  # List credentials
  nexus credential list
  nexus credential list --type aws_role --status active

  # Get credential details
  nexus credential get cred_123

  # Create credential
  nexus credential create \\
    --name "Production AWS" \\
    --type aws_role \\
    --provider github \\
    --config '{"role_arn": "arn:aws:iam::123456789:role/github"}'

  # Rotate credential
  nexus credential rotate cred_123

  # Delete credential
  nexus credential delete cred_123 --force

  # View audit trail
  nexus audit log --limit 50 --resource-id cred_123

  # Check health
  nexus health
        ''',
    )

    subparsers = parser.add_subparsers(title='commands', dest='command', help='Available commands')

    # Health command
    subparsers.add_parser('health', help='Check API health status')

    # Credential commands
    credential_parser = subparsers.add_parser('credential', help='Credential management')
    credential_sub = credential_parser.add_subparsers(dest='subcommand')

    # credential list
    list_cmd = credential_sub.add_parser('list', help='List credentials')
    list_cmd.add_argument('--type', help='Filter by credential type')
    list_cmd.add_argument('--provider', help='Filter by provider')
    list_cmd.add_argument('--status', help='Filter by status')
    list_cmd.add_argument('--format', choices=['json', 'table'], default='table', help='Output format')

    # credential get
    get_cmd = credential_sub.add_parser('get', help='Get credential details')
    get_cmd.add_argument('id', help='Credential ID')
    get_cmd.add_argument('--format', choices=['json', 'table'], default='json', help='Output format')

    # credential create
    create_cmd = credential_sub.add_parser('create', help='Create new credential')
    create_cmd.add_argument('--name', required=True, help='Credential name')
    create_cmd.add_argument('--type', required=True, help='Credential type')
    create_cmd.add_argument('--provider', required=True, help='Provider (github, google, etc)')
    create_cmd.add_argument('--config', help='Configuration JSON')
    create_cmd.add_argument('--format', choices=['json', 'table'], default='json', help='Output format')

    # credential delete
    delete_cmd = credential_sub.add_parser('delete', help='Delete credential')
    delete_cmd.add_argument('id', help='Credential ID')
    delete_cmd.add_argument('--force', action='store_true', help='Skip confirmation')

    # credential rotate
    rotate_cmd = credential_sub.add_parser('rotate', help='Rotate credential')
    rotate_cmd.add_argument('id', help='Credential ID')
    rotate_cmd.add_argument('--force', action='store_true', help='Force rotation')

    # Audit commands
    audit_parser = subparsers.add_parser('audit', help='Audit trail')
    audit_sub = audit_parser.add_subparsers(dest='audit_command')

    # audit log
    log_cmd = audit_sub.add_parser('log', help='View audit trail')
    log_cmd.add_argument('--limit', type=int, default=100, help='Number of events to return')
    log_cmd.add_argument('--offset', type=int, default=0, help='Offset for pagination')
    log_cmd.add_argument('--resource-id', help='Filter by resource ID')
    log_cmd.add_argument('--action', help='Filter by action')

    args = parser.parse_args()

    # Show help if no command
    if not args.command:
        parser.print_help()
        return 0

    try:
        cli = NexusShieldCLI()

        # Route to handlers
        if args.command == 'health':
            return cli.health(args)
        elif args.command == 'credential':
            if args.subcommand == 'list':
                return cli.credential_list(args)
            elif args.subcommand == 'get':
                return cli.credential_get(args)
            elif args.subcommand == 'create':
                return cli.credential_create(args)
            elif args.subcommand == 'delete':
                return cli.credential_delete(args)
            elif args.subcommand == 'rotate':
                return cli.credential_rotate(args)
            else:
                credential_parser.print_help()
                return 1
        elif args.command == 'audit':
            if args.audit_command == 'log':
                return cli.audit_log(args)
            else:
                audit_parser.print_help()
                return 1
        else:
            parser.print_help()
            return 1
    except RuntimeError as e:
        print(f"✗ {str(e)}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\nCancelled by user", file=sys.stderr)
        return 130
    except Exception as e:
        print(f"✗ Unexpected error: {str(e)}", file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
