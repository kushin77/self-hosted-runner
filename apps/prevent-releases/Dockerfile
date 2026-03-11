FROM node:18-bullseye-slim
WORKDIR /usr/src/app
COPY package.json package-lock.json* ./
RUN npm ci --production
COPY . ./
EXPOSE 3000
CMD ["node", "index.js"]
