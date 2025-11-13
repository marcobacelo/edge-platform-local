FROM node:20-alpine
WORKDIR /app

# Copia só o package.json para não prender em lock antigo
COPY package.json ./

# Instala somente dependências de produção
RUN npm install --omit=dev

# Copia o código
COPY persister.js ./

CMD ["node", "persister.js"]
