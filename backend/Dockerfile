FROM python:3.11-slim

WORKDIR /app

# system deps for crypto and common wheels
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libssl-dev \
    libffi-dev \
    git \
 && rm -rf /var/lib/apt/lists/*

COPY backend/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

COPY backend /app

ENV PYTHONUNBUFFERED=1
ENV PORT=8000
CMD ["uvicorn", "canonical_secrets_api:app", "--host", "0.0.0.0", "--port", "8000"]
