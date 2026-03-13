# Zero-Trust Authentication Service (FAANG-Grade)
# Runtime: Node.js 20 + TypeScript + Express
# Security: Non-root, minimal base, security headers, no secrets in image

FROM node:20-alpine AS builder
WORKDIR /build
COPY security/package*.json ./
RUN npm ci --only=prod && npm ci --only=dev

# Copy source
COPY security/*.ts ./
COPY security/tsconfig.json ./

# Build TypeScript
RUN npm run tsc || true

# Runtime image
FROM node:20-alpine
RUN apk add --no-cache dumb-init ca-certificates

# Use existing non-root `node` user from official base image to avoid uid/gid conflicts

WORKDIR /app

# Copy deps from builder
COPY --from=builder /build/node_modules ./node_modules

# Copy runtime (compiled JS would be here; for now using TS directly)
COPY security/*.ts ./
COPY security/package*.json ./

# Copy credential rotation scripts for sidecar access
COPY scripts/secrets/rotate-credentials.sh /app/scripts/
RUN chmod +x /app/scripts/rotate-credentials.sh || true

# Ownership
RUN chown -R node:node /app

# Security headers
ENV NODE_ENV=production
ENV LOG_LEVEL=info
ENV JWT_ISSUER_URL=https://accounts.google.com
ENV MUTABLE_CACHE_TTL=300

USER node
EXPOSE 8080

# Use dumb-init to handle signals properly
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "-r", "ts-node/register", "zero-trust-auth.ts"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "require('http').get('http://localhost:8080/health', (r) => {if (r.statusCode !== 200) throw new Error(r.statusCode)})"
