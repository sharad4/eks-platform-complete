# syntax=docker/dockerfile:1.7
# Prerequisite: a Vite React app in this directory
#   npm create vite@latest . -- --template react
#
# Multi-stage: Node (hundreds of MB, full of build tooling) never reaches
# production. The final image is nginx + static files only.

# ---- Stage 1: build ----------------------------------------------------------
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
# API calls use a relative URL (/api/...). The ALB routes /api to the backend, so
# the same build artifact works in every environment: no per-env rebuild.
RUN npm run build

# ---- Stage 2: serve ----------------------------------------------------------
# nginx-unprivileged: runs as uid 101, listens on 8080, writes only to /tmp.
FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime
USER root
# Apply Alpine security fixes released since the base image was built (Trivy gate).
# hadolint ignore=DL3018
RUN apk upgrade --no-cache
USER 101
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 8080