# NexusShield Portal Backend - Minimal Docker image for rapid deployment
FROM node:18-alpine

WORKDIR /app

ENV NODE_ENV=production \
    PORT=3000

# Copy only minimal files needed
COPY index.js package.json ./

# No npm install needed - pure Node.js HTTP server
EXPOSE 3000

# Simple health probe
HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost:3000/api/health || exit 1

# Run Node server
CMD ["node", "index.js"]
