FROM node:20-alpine
WORKDIR /app

# Copia apenas manifestos primeiro para melhor cache
COPY package*.json ./

# Se existir package-lock.json → usa `npm ci`; senão → `npm install`
RUN if [ -f package-lock.json ]; then \
      npm ci --legacy-peer-deps; \
    else \
      npm install --legacy-peer-deps; \
    fi

# Copia configs e código
COPY tsconfig*.json ./
COPY src ./src

# Build TS → dist/
RUN npm run build

# Sobe a API compilada
CMD ["node", "dist/main.js"]
