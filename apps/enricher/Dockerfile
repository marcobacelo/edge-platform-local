FROM node:20-alpine
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci || npm i
COPY enricher.js ./
CMD ["node", "enricher.js"]
