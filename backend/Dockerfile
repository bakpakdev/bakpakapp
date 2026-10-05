# popup payments/API backend. Works on Render, Railway, Fly.io, or any Docker host.
FROM node:22-alpine

WORKDIR /app
ENV NODE_ENV=production

# Install deps first so this layer is cached between code changes.
# `npm ci` runs @prisma/client's postinstall, which generates the client from prisma/schema.prisma.
COPY package.json package-lock.json ./
COPY prisma ./prisma
RUN npm ci --omit=dev

COPY . .

# The platform injects PORT; server.js falls back to 5001.
EXPOSE 5001
CMD ["node", "server.js"]
