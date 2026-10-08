FROM node:22.20.0-alpine3.22 AS dependencies
WORKDIR /app
COPY api/package.json api/package-lock.json ./
RUN npm ci --omit=dev

FROM node:22.20.0-alpine3.22 AS runtime
ENV NODE_ENV=production
ENV PORT=8080
WORKDIR /app
COPY --from=dependencies --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node api/package.json api/server.js ./
COPY --chown=node:node api/lib ./lib
COPY --chown=node:node api/scripts ./scripts
COPY --chown=node:node db/schema.sql ./db/schema.sql
USER node
EXPOSE 8080
CMD ["node", "server.js"]
