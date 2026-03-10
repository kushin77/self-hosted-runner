FROM python:3.11-slim
WORKDIR /app

# Install Google Cloud SDK and Vault CLI and other runtime deps
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl gnupg lsb-release unzip; \
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" > /etc/apt/sources.list.d/google-cloud-sdk.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends google-cloud-cli; \
    VAULT_VERSION=1.15.0; \
    curl -fsSL "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip" -o /tmp/vault.zip; \
    unzip /tmp/vault.zip -d /usr/local/bin; \
    rm -f /tmp/vault.zip; \
    rm -rf /var/lib/apt/lists/*;

COPY scripts/cloudrun/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY scripts/cloudrun/app.py ./app.py
COPY scripts/vault/sync_gsm_to_vault.sh /opt/scripts/sync_gsm_to_vault.sh
COPY scripts/cleanup/cleanup_ephemeral_runners.sh /opt/scripts/cleanup_ephemeral_runners.sh
RUN chmod +x /opt/scripts/*.sh

ENV PORT=8080
EXPOSE 8080
CMD ["gunicorn", "app:app", "-b", "0.0.0.0:8080", "--workers", "2"]
