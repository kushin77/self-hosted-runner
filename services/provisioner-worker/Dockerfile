FROM node:18-alpine
WORKDIR /usr/src/app

# Install dependencies if package.json present
COPY package*.json ./ 2>/dev/null || true
RUN if [ -f package.json ]; then npm ci --only=production; fi

# Copy service code
COPY . .

EXPOSE 9090

CMD ["node", "worker.js"]
