FROM python:3.11-slim
WORKDIR /app

# Install minimal runtime deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gcloud \
    && rm -rf /var/lib/apt/lists/* || true

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py ./
COPY ../vault/sync_gsm_to_vault.sh /opt/scripts/sync_gsm_to_vault.sh
COPY ../cleanup/cleanup_ephemeral_runners.sh /opt/scripts/cleanup_ephemeral_runners.sh
RUN chmod +x /opt/scripts/*.sh

ENV PORT=8080
EXPOSE 8080
CMD ["gunicorn", "app:app", "-b", "0.0.0.0:8080", "--workers", "2"]
