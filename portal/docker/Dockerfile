# Multi-stage build for NexusShield Portal

# Stage 1: Install dependencies and build
FROM node:18.18.0-alpine AS builder

WORKDIR /app

# Install pnpm
RUN npm install -g pnpm

# Copy monorepo files
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml* tsconfig.base.json ./
COPY packages/ ./packages/

# Install dependencies. Use lockfile if present, allow pnpm to handle version mismatches
RUN if [ -f pnpm-lock.yaml ]; then \
			pnpm install --no-frozen-lockfile || pnpm install --force; \
		else \
			pnpm install; \
		fi

# Do not run monorepo-wide builds during image creation.
# Compose starts service-specific commands for API and frontend.

# Stage 2: Runtime
FROM node:18.18.0-alpine

WORKDIR /app

RUN npm install -g pnpm

# Copy built files and dependencies
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/packages ./packages
COPY --from=builder /app/pnpm-lock.yaml* ./
COPY --from=builder /app/package.json ./
COPY --from=builder /app/pnpm-workspace.yaml ./
COPY --from=builder /app/tsconfig.base.json ./

EXPOSE 3000 5000

ENV NODE_ENV=production
ENV LOG_LEVEL=info
ENV PORT=5000

# Start both frontend and backend. For runtime images we keep behavior minimal — compose runs
# service-specific commands in dev, but for an image fallback we start both processes.
CMD ["sh", "-c", "pnpm -C packages/api start & pnpm -C packages/frontend preview"]
