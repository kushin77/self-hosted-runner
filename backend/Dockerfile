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

CMD ["uvicorn", "canonical_secrets_api:app", "--host", "0.0.0.0", "--port", "8000"]# NexusShield Portal Backend - Production-ready Docker image
# Multi-stage build for minimal final image

FROM node:18-alpine AS builder

WORKDIR /build

# Copy package files
COPY package*.json ./

# Install dependencies (use `npm ci` if a lockfile exists, otherwise fall back to `npm install`)
RUN if [ -f package-lock.json ]; then \
      npm ci; \
    else \
      npm install; \
    fi

# Copy source
COPY src ./src
COPY tsconfig.json ./
COPY prisma ./prisma

# Build TypeScript
RUN npm run build

# ============================================================================
# FINAL IMAGE
# ============================================================================

FROM node:18-alpine

WORKDIR /app

ENV NODE_ENV=production \
    PORT=3000

# Copy only necessary files from builder
COPY --from=builder /build/dist ./dist
COPY --from=builder /build/node_modules ./node_modules
COPY --from=builder /build/prisma ./prisma
COPY --from=builder /build/package.json ./

# Create logs directory (immutable audit trail location)
RUN mkdir -p /app/logs && chmod 755 /app/logs

EXPOSE 3000

# Health checks for Docker
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost:3000/ready || exit 1

# Run as non-root user for security
RUN addgroup -g 1001 -S nodejs && adduser -S nodejs -u 1001
USER nodejs

# Start server
CMD ["node", "dist/index.js"]
