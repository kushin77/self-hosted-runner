FROM node:18-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    jq \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy all services
COPY services/ /app/services/

# Install dependencies for all services
RUN for svc in provisioner-worker managed-auth vault-shim; do \
    if [ -d "services/$svc" ]; then \
        cd "services/$svc" && npm install --production && cd /app; \
    fi; \
done

# Default command (overridden by docker-compose)
CMD ["node", "services/managed-auth/index.js"]
