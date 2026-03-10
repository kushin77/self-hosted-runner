#!/usr/bin/env python3
import os
import sys
import time
import json
import threading

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
import pyotp
import requests

# This is an integration test stub for MFA-protected /api/v1/migrate endpoint.
# Set PORTAL_MFA_SECRET env var before running this test.

def main():
    secret = os.environ.get('PORTAL_MFA_SECRET')
    if not secret:
        print('PORTAL_MFA_SECRET not set; skipping')
        return
    totp = pyotp.TOTP(secret)
    otp = totp.now()

    url = os.environ.get('TEST_MIGRATE_URL', 'http://127.0.0.1:8080/api/v1/migrate')
    payload = {'source': 'on-prem', 'destination': 'gcp', 'mode': 'live', 'rollback': True}
    headers = {'Content-Type': 'application/json', 'X-MFA-OTP': otp}
    r = requests.post(url, headers=headers, json=payload)
    print('status', r.status_code)
    print(r.text)

if __name__ == '__main__':
    main()
