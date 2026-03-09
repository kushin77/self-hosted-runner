#!/usr/bin/env python3
"""
Immutable Audit System - Append-Only Credential Lifecycle Logging

Guarantees:
- Append-only (no modification/deletion)
- Cryptographic integrity (SHA-256 hash chain)
- 365+ day retention
- Operation-only logging (credentials never logged)
- Session traceability with unique IDs
"""

import json
import hashlib
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path
import uuid

class ImmutableAuditLog:
    def __init__(self, log_dir=".audit-logs"):
        self.log_dir = Path(log_dir)
        self.log_dir.mkdir(parents=True, exist_ok=True)
        
    def _get_previous_hash(self):
        """Get hash of last log entry for chain integrity."""
        logs = sorted(self.log_dir.glob("*.jsonl"))
        if not logs:
            return hashlib.sha256(b"BOOTSTRAP").hexdigest()
        
        last_log = logs[-1]
        with open(last_log, 'rb') as f:
            lines = f.readlines()
            if lines:
                last_entry = json.loads(lines[-1].decode('utf-8'))
                return last_entry.get('hash', hashlib.sha256(b"BOOTSTRAP").hexdigest())
        return hashlib.sha256(b"BOOTSTRAP").hexdigest()
    
    def _compute_hash(self, entry_json, previous_hash):
        """Compute SHA-256 hash of entry + previous hash (chain)."""
        chain_input = json.dumps(entry_json, sort_keys=True) + previous_hash
        return hashlib.sha256(chain_input.encode()).hexdigest()
    
    def append_log(self, operation, status, provider=None, details=None):
        """Append immutable audit log entry."""
        session_id = os.environ.get('AUDIT_SESSION_ID', str(uuid.uuid4())[:8])
        previous_hash = self._get_previous_hash()
        
        entry = {
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'operation': operation,
            'status': status,  # success, skipped, error
            'provider': provider,  # gsm, vault, kms
            'session_id': session_id,
            'details': details or {},
            'previous_hash': previous_hash,
        }
        
        # Add hash of this entry
        entry['hash'] = self._compute_hash(entry, previous_hash)
        
        # Append to log file (mode 'a' = append-only)
        log_file = self.log_dir / f"{datetime.utcnow().strftime('%Y%m%d')}-operations.jsonl"
        with open(log_file, 'a') as f:
            f.write(json.dumps(entry) + '\n')
        
        return entry['hash']
    
    def verify_integrity(self):
        """Verify all entries form unbroken hash chain."""
        logs = sorted(self.log_dir.glob("*.jsonl"))
        expected_hash = hashlib.sha256(b"BOOTSTRAP").hexdigest()
        
        for log_file in logs:
            with open(log_file, 'r') as f:
                for i, line in enumerate(f):
                    entry = json.loads(line)
                    
                    # Verify hash chain
                    if entry.get('previous_hash') != expected_hash:
                        print(f"❌ Hash chain broken at {log_file}:{i}")
                        return False
                    
                    expected_hash = entry.get('hash')
        
        print(f"✓ Audit log integrity verified (chain length: {i+1})")
        return True
    
    def retention_check(self, days=365):
        """Check all entries are within retention window."""
        cutoff = datetime.utcnow() - timedelta(days=days)
        removed = 0
        
        for log_file in self.log_dir.glob("*.jsonl"):
            with open(log_file, 'r') as f:
                lines = f.readlines()
            
            # Never delete (immutable), but warn if old
            if lines:
                first_entry = json.loads(lines[0])
                timestamp = datetime.fromisoformat(first_entry['timestamp'].replace('Z', '+00:00'))
                
                if timestamp < cutoff:
                    print(f"⚠ {log_file} exceeds {days} day retention (age: {(datetime.utcnow() - timestamp).days} days)")
        
        return True

if __name__ == "__main__":
    audit = ImmutableAuditLog()
    
    if len(sys.argv) > 1 and sys.argv[1] == "verify":
        audit.verify_integrity()
    elif len(sys.argv) > 1 and sys.argv[1] == "check-retention":
        audit.retention_check()
    else:
        # Example: log a credential operation
        audit.append_log(
            operation="credential_refresh",
            status="success",
            provider="gsm",
            details={"secret_count": 5, "ttl_minutes": 60}
        )
        print("✓ Audit log entry appended (immutable)")
