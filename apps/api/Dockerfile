# syntax=docker/dockerfile:1.7
# 멀티스테이지: deps → build → runtime (PRD §7.2)

ARG NODE_VERSION=20-alpine

FROM node:${NODE_VERSION} AS deps
WORKDIR /repo
RUN corepack enable && corepack prepare pnpm@10.33.0 --activate
RUN apk add --no-cache python3 make g++
COPY package.json pnpm-workspace.yaml ./
COPY apps/api/package.json apps/api/package.json
RUN pnpm install --filter api... --frozen-lockfile=false

FROM node:${NODE_VERSION} AS build
WORKDIR /repo
RUN corepack enable && corepack prepare pnpm@10.33.0 --activate
COPY --from=deps /repo /repo
COPY apps/api ./apps/api
RUN pnpm --filter api build

FROM node:${NODE_VERSION} AS runtime
WORKDIR /repo
ENV NODE_ENV=production
RUN corepack enable && corepack prepare pnpm@10.33.0 --activate
RUN apk add --no-cache python3 make g++
COPY package.json pnpm-workspace.yaml ./
COPY apps/api/package.json apps/api/package.json
RUN pnpm install --filter api... --prod --frozen-lockfile=false
COPY --from=build /repo/apps/api/dist ./apps/api/dist
COPY --from=build /repo/apps/api/src/migrations ./apps/api/src/migrations
WORKDIR /repo/apps/api
EXPOSE 4000
CMD ["node", "dist/main.js"]
