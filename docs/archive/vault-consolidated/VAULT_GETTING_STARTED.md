# Vault 101: Becoming Your Own Vault Master

This document is a gentle introduction to HashiCorp Vault for developers/operators who are unfamiliar with it. We'll cover
- what Vault is and why it's useful
- key concepts you need to know
- installing Vault (dev and production)
- initializing and unsealing
- common auth methods (AppRole) and secret engines
- using Vault with Google Cloud (GSM/GCP KMS)
- how our repo (`self-hosted-runner` & `ElevatedIQ-Mono-Repo`) integrates with Vault

> **Goal:** by the end you should be comfortable running a Vault server, creating roles/policies, and fetching secrets from an application.

---

## 1. What is Vault?

Vault is a tool for securely storing and accessing secrets. It provides:

* **Centralized secrets store** (key/value, dynamic credentials, PKI, etc.)
* **Leasing and renewal** – all secrets have TTLs and can be revoked
* **Encryption-as-a-service** – you can ask Vault to encrypt/decrypt data
* **Multiple authentication backends** – tokens, GitHub, LDAP, AppRole, GCP, etc.
* **Audit logging** and **fine-grained policies**
* **Auto-unseal mechanisms** (e.g. KMS, transit, GCP KMS)

Vault decouples the storage of secrets from application consumers and provides safe runtime access patterns.

---

## 2. Key Concepts

| Term | Description |
|------|-------------|
| **Server** | The Vault process you run (binary or container). |
| **Storage backend** | Where Vault persists its data (Consul, GCS, Azure blob, etc.). |
| **Seal** | When Vault is started it is "sealed" (inaccessible); requires unseal keys to open. |
| **Unseal keys / Root token** | Generated during `vault operator init`; store these offline! |
| **Token** | Client credential, has policies attached, used for authentication. |
| **Policy** | HCL or JSON rules that grant/deny capabilities on paths. |
| **Auth method** | How clients authenticate (AppRole, GitHub, userpass, etc.).
| **Secret engine** | Plugin that handles a class of secrets (e.g. `kv`, `database`, `aws`).
| **Lease** | Time-limited access to a secret; can be renewed or revoked. |

For a complete glossary see Vault docs: https://www.vaultproject.io/docs/overview

---

## 3. Installing Vault

### 3.1 Development / experimentation

```bash
# Linux / macOS
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install vault

# or via Homebrew (macOS):
brew tap hashicorp/tap
brew install hashicorp/tap/vault

# or use the pre‑built binary directly:
wget https://releases.hashicorp.com/vault/1.14.1/vault_1.14.1_linux_amd64.zip
unzip vault_1.14.1_linux_amd64.zip
chmod +x vault
sudo mv vault /usr/local/bin/

# verify
vault --version
```

### 3.2 Docker (useful for local trials)

```bash
docker run --cap-add=IPC_LOCK --rm -p 8200:8200 \
  -e 'VAULT_DEV_ROOT_TOKEN_ID=myroot' \
  -e 'VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200' \
  vault:1.14.1
```

The "dev" server auto-unseals, has a known root token, and stores data in memory – do **not** use in production.

### 3.3 Production installation

Create a configuration file (e.g. `/etc/vault.d/config.hcl`):

```hcl
storage "gcs" {
  bucket = "my-vault-data"
  project = "my-gcp-project"
}

auto_unseal "gcpckms" {
  project     = "my-gcp-project"
  region      = "us-central1"
  key_ring    = "vault-unseal-ring"
  crypto_key  = "vault-unseal-key"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_cert_file = "/etc/vault.d/vault.crt"
  tls_key_file  = "/etc/vault.d/vault.key"
}

ui = true
```

The above uses Google Cloud Storage for persistence and GCP KMS for auto‑unseal – useful when running on Google Cloud or Google Secret Manager.

Start Vault as a systemd service or container with that config:

```bash
vault server -config=/etc/vault.d/config.hcl
# or if container
docker run --cap-add=IPC_LOCK -v /etc/vault.d:/vault/config \
  -p 8200:8200 vault server
```

---

## 4. Initialization and Unsealing

When you first start a new Vault, it's sealed. Run:

```bash
export VAULT_ADDR=http://127.0.0.1:8200
vault operator init -key-shares=1 -key-threshold=1 > /tmp/vault-init.out
```

This will output **unseal keys** and a **root token**. Example:

```
Unseal Key 1: ABCDEFGH...
Initial Root Token: s.uMjBEXAMPLE
```

**Store the unseal key and root token securely** (offline, e.g. in GCP Secret Manager or an encrypted file). Once the server is initialized you must supply the unseal key to access secrets:

```bash
vault operator unseal ABCDEFGH...
```

If you configured auto‑unseal (e.g. GCP KMS above), the unseal step happens automatically and you can skip manual unseal.

---

## 5. Basic Vault Workflow

### Authenticate

```bash
vault login <root-token>           # one‑time root login
vault token create -policy="dev"  # create a new token
vault login <new-token>
```

### Enable a secrets engine

```bash
vault secrets enable -path=secret kv  # enable key/value v2 at "secret/"
```

### Write and read secrets

```bash
vault kv put secret/myapp/config username='alice' password='s3cr3t'
vault kv get secret/myapp/config
```

### Create a policy

`dev-policy.hcl`:
```hcl
path "secret/data/myapp/*" {
  capabilities = ["create","read","update","delete","list"]
}
```

```bash
vault policy write dev-policy dev-policy.hcl
```

### AppRole auth (used in our services)

```bash
vault auth enable approle

# create a policy and link to role
vault policy write runner-policy -<<'EOF'
path "secret/data/provisioner/*" {
  capabilities = ["read"]
}
EOF

vault write auth/approle/role/provisioner-worker \
  token_policies="runner-policy" \
  token_ttl=1h token_max_ttl=4h

# read the role_id and secret_id (store these securely)
vault read -field=role_id auth/approle/role/provisioner-worker/role-id
vault write -force -field=secret_id auth/approle/role/provisioner-worker/secret-id > /run/vault/.secret
```

In the `self-hosted-runner` code we use these values via environment variables `VAULT_ROLE_ID` and the file `/run/vault/.secret` as shown in `vault-integration.sh`.

---

## 6. Vault + Google Cloud (GSM/GCP) Integration

You already have Google Secret Manager (GSM) in your setup. There are two common patterns:

1. **Vault storage backend on GCS** – Vault persists its data in a GCS bucket. The example config above uses `storage "gcs"`.
2. **Unseal with GCP KMS** – avoid manual unseal by using a GCP KMS key (`auto_unseal "gcpckms"`).
3. **Authentication using Google service accounts** – Vault supports `auth/gcp` where a VM or workload identity authenticates using a signed JWT from a service account.

If you're running in GCP, set up a service account with `roles/storage.admin` (for GCS backend) and `roles/cloudkms.cryptoKeyEncrypterDecrypter` (for KMS). Then configure your VM/container to fetch credentials via metadata server or use Workload Identity.

Sample `auth/gcp` policy binding:

```bash
vault auth enable gcp
vault write auth/gcp/config \
  credentials=@/path/to/service-account.json

vault write auth/gcp/role/my-role \
  policies="some-policy" \
  bound_service_accounts="vault-auth-sa@my-project.iam.gserviceaccount.com" \
  bound_projects="my-project" \
  max_ttl="1h"
```

Then workloads can authenticate by presenting a signed JWT from the VM metadata.

**Note:** our `vault-integration.sh` currently uses AppRole; you could extend it to support `auth/gcp` if you prefer.

---

## 7. How the `self-hosted-runner` Repo Uses Vault

* `vault-integration.sh` implements AppRole authentication, secret fetching, caching, and rotation (see earlier file).
* Services like `managed-auth` rely on `VAULT_ADDR`, `VAULT_ROLE_ID`, and the secret-id file to log in and fetch credentials.
* Production environment file `/config/vault/env-prod.sh` is a placeholder; once real credentials are available you will export them there:
  ```bash
  export VAULT_ADDR="https://vault.myorg.internal:8200"
  export VAULT_ROLE_ID="<role id>"
  # secret id is mounted via Kubernetes or written to /run/vault/.secret
  ```
* Alerts in `alerts/provisioner-alerts.yml` watch Vault connectivity and error rate.
* The `services/vault-shim` is an abstraction that fronts Vault for other services. It uses an internal token or path; you usually point your app to the shim rather than Vault directly.

### Troubleshooting

- If authentication fails, check `VAULT_ROLE_ID` and that `/run/vault/.secret` exists with matching secret id.
- Use `vault token lookup` to inspect current token TTL.
- `vault status` shows sealed/unsealed, cluster info.
- Logs from vault-shim and provisioner-worker often include Vault errors.

---

## 8. Vault Best Practices

* Never store unseal keys or root tokens in GitHub or plaintext.
* Use a secure storage system (GSM, HSM, etc.) for root/unseal keys.
* Rotate tokens regularly; use short TTLs for AppRole tokens.
* Restrict policies to the least privilege required.
* Enable audit logging and monitor for unusual access patterns.
* Back up the storage backend (e.g. GCS bucket) and test recovery.
* Consider HA setup with integrated storage (e.g. Consul) if you need high availability.

---

## 9. Exercise: Run a Local Vault Server

1. Start dev server:
   ```bash
   vault server -dev -dev-root-token-id="root" &
   export VAULT_ADDR="http://127.0.0.1:8200"
   vault login root
   vault secrets enable -path=secret kv
   vault kv put secret/test foo=bar
   vault kv get secret/test
   ```
2. Create an AppRole:
   ```bash
   vault auth enable approle
   vault policy write test-policy -<<'EOF'
   path "secret/data/test" {
     capabilities=["read"]
   }
   EOF
   vault write auth/approle/role/test-role token_policies="test-policy" token_ttl=1h
   vault read -field=role_id auth/approle/role/test-role/role-id
   vault write -force -field=secret_id auth/approle/role/test-role/secret-id > /tmp/role.secret
   ```
3. Use `vault-integration.sh` with the above to fetch the secret (modify env vars accordingly).

---

## 10. Next Steps for You

1. **Install Vault** on a dedicated host or use a managed offering (e.g. Vault Enterprise, HCP Vault).
2. **Decide on storage/unseal backend** – for GCP this will usually be GCS + KMS.
3. **Initialize and unseal** the cluster; save keys securely in Google Secret Manager or another offline vault.
4. **Create policies** and **AppRoles** for each service. Record the role_id/secret_id pairs securely.
5. **Deploy services** with environment pointing to Vault (or vault-shim) and provide secret-id files via secure volume mounts.
6. **Train team** on rotating credentials and handoff vault master responsibilities.

Troubleshooting and advanced topics (dynamic secrets, PKI, database credentials) are beyond the scope of this primer but are covered in Vault's official docs.

---

*Happy vaulting!* Reach out if you need help creating policies, roles, or integrating with the GSM/GCP workflow.
