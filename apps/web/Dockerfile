# syntax=docker/dockerfile:1.7
# 멀티스테이지: deps → build → runtime (apps/api/Dockerfile 패턴 미러)

ARG NODE_VERSION=20-alpine

FROM node:${NODE_VERSION} AS deps
WORKDIR /repo
RUN corepack enable && corepack prepare pnpm@10.33.0 --activate
COPY package.json pnpm-workspace.yaml ./
COPY apps/web/package.json apps/web/package.json
RUN pnpm install --filter web... --frozen-lockfile=false

FROM node:${NODE_VERSION} AS build
WORKDIR /repo
RUN corepack enable && corepack prepare pnpm@10.33.0 --activate
COPY --from=deps /repo /repo
COPY apps/web ./apps/web
# 빌드 시 rewrites 타겟은 런타임 env 로 주입되므로 여기선 기본값 사용
RUN pnpm --filter web build

FROM node:${NODE_VERSION} AS runtime
WORKDIR /repo/apps/web
ENV NODE_ENV=production
RUN corepack enable && corepack prepare pnpm@10.33.0 --activate
COPY --from=build /repo /repo
EXPOSE 3000
CMD ["pnpm", "start"]
