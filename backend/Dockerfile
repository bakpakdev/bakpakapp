# popup payments/API backend. Works on Render, Railway, Fly.io, or any Docker host.
# Use Debian slim (not Alpine): Prisma's musl engine expects libssl.so.1.1, which
# newer Alpine images no longer ship.
FROM node:22-bookworm-slim

WORKDIR /app
ENV NODE_ENV=production
# Prisma generate reads DATABASE_URL at build time. The hosted API uses Supabase, not this MySQL.
ENV DATABASE_URL="mysql://unused:unused@127.0.0.1:3306/unused"

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends openssl ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Install deps first so this layer is cached between code changes.
# `npm ci` runs @prisma/client's postinstall, which generates the client from prisma/schema.prisma.
COPY package.json package-lock.json ./
COPY prisma ./prisma
RUN npm ci --omit=dev

COPY . .

# The platform injects PORT; server.js falls back to 5001.
EXPOSE 5001
CMD ["node", "server.js"]
