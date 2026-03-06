FROM node:18-alpine
WORKDIR /usr/src/app

COPY package*.json ./ 2>/dev/null || true
RUN if [ -f package.json ]; then npm ci --only=production; fi

COPY . .

EXPOSE 8200

CMD ["node", "shim.js"]
