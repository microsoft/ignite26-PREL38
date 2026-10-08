FROM node:22.20.0-alpine3.22 AS dependencies
WORKDIR /app
COPY portal/package.json portal/package-lock.json ./
RUN npm ci --omit=dev

FROM node:22.20.0-alpine3.22 AS runtime
ENV NODE_ENV=production
ENV PORT=8080
WORKDIR /app
COPY --from=dependencies --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node portal/package.json portal/server.js ./
USER node
EXPOSE 8080
CMD ["node", "server.js"]
