FROM node:26-alpine AS build

# The frontend's prepare script runs `vp config`, which needs git.
RUN apk add --no-cache git
RUN npm install --global pnpm@12
WORKDIR /app

COPY frontend/package.json frontend/pnpm-lock.yaml frontend/pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile

COPY frontend/ ./
# shortcut: vite-plus has no Node10-resolvable vite/client type entry; remove when upstream fixes it.
RUN printf "/// <reference path='./dist/vite/client.d.ts' />\n" > node_modules/vite/client.d.ts
RUN pnpm run build

FROM nginx:alpine
COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY --from=build /app/dist /usr/share/nginx/html
