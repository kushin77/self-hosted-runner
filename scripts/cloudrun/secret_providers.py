"""Secret provider abstraction: GSM, Vault, ENV fallbacks.
This module tries to load the most secure provider available based on environment.
"""
import os
import json

def get_env_secret(name):
    return os.environ.get(name)

def get_secret_gsm(name):
    try:
        from google.cloud import secretmanager
        client = secretmanager.SecretManagerServiceClient()
        project = os.environ.get('GCP_PROJECT')
        if not project:
            return None
        name_path = f"projects/{project}/secrets/{name}/versions/latest"
        resp = client.access_secret_version(request={"name": name_path})
        return resp.payload.data.decode('utf-8')
    except Exception:
        return None

def get_secret_vault(name):
    try:
        import hvac
        VAULT_ADDR = os.environ.get('VAULT_ADDR')
        if not VAULT_ADDR:
            return None
        # Let the hvac client pick up authentication via environment or agent
        client = hvac.Client(url=VAULT_ADDR)
        kv_path = os.environ.get('VAULT_KV_PATH', 'secret/data')
        # Try KV v2
        try:
            resp = client.secrets.kv.v2.read_secret_version(path=name)
            return json.dumps(resp.get('data', {})) if resp else None
        except Exception:
            # Fallback to kv v1
            resp = client.secrets.kv.v1.read_secret(name)
            return json.dumps(resp.get('data', {})) if resp else None
    except Exception:
        return None

def get_secret(name):
    # Priority: Vault -> GSM -> ENV
    val = get_secret_vault(name)
    if val:
        return val
    val = get_secret_gsm(name)
    if val:
        return val
    return get_env_secret(name)
