Run With Secret — wrapper usage

This wrapper runs a command with a secret fetched from the canonical secret chain
(GSM → Vault → KMS) using `scripts/secrets/fetch-secret-oidc-gsm-vault.sh`.

Usage examples

- FD-based (preferred, ephemeral):
  ```bash
  GSM_PROJECT=my-gcp-project GSM_SECRET_NAME=my-secret \
    ./scripts/secrets/run-with-secret.sh -- ./my-service --serve
  ```

- Env-based (less secure; may expose secret in process environment):
  ```bash
  GSM_PROJECT=my-gcp-project GSM_SECRET_NAME=my-secret \
    ./scripts/secrets/run-with-secret.sh --env -- ./my-service --serve
  ```

Behavior
- FD-based: the secret is provided on file descriptor 3. The wrapper sets
  environment variable `SECRET_FD=3` for the child process. The child can read
  from `/dev/fd/3` or use FD 3 directly.
- Env-based: the secret is exported into `SECRET_VALUE` for the duration of
  the child process. Use only when FD-based delivery is not possible.

Security notes
- The wrapper writes the secret to a temporary file with mode 600 and removes it
  (shred if available) when the process exits.
- Prefer FD-based delivery to avoid putting secrets into the environment.
