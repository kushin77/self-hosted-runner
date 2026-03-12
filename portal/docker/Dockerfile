# Multi-stage build for NexusShield Portal

# Stage 1: Install dependencies and build
FROM node:18-alpine AS builder

WORKDIR /app

# Install pnpm
RUN npm install -g pnpm

# Copy monorepo files
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml* tsconfig.base.json ./
COPY packages/ ./packages/

# Install dependencies
RUN pnpm install --frozen-lockfile

# Build all packages
RUN pnpm build

# Stage 2: Runtime
FROM node:18-alpine

WORKDIR /app

RUN npm install -g pnpm

# Copy built files and dependencies
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/packages ./packages
COPY --from=builder /app/pnpm-lock.yaml* ./

EXPOSE 3000 5000

ENV NODE_ENV=production
ENV LOG_LEVEL=info
ENV PORT=5000

# Start both frontend and backend
CMD ["sh", "-c", "pnpm -C packages/api start & pnpm -C packages/frontend preview"]
