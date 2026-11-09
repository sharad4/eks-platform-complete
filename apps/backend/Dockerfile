# syntax=docker/dockerfile:1.7
# =============================================================================
# Laravel API image. Multi-stage: build tooling never ships to production.
#
# Prerequisite: a Laravel app in this directory, e.g.
#   composer create-project laravel/laravel . && git add -A
# plus the health/metrics routes described in README.md.
# =============================================================================

# ---- Stage 1: resolve PHP dependencies --------------------------------------
FROM composer:2 AS vendor
WORKDIR /app

# Copy manifests first so the (slow) install layer is cached until they change.
COPY composer.json composer.lock ./
# The composer image lacks the runtime extensions, which are present in the final image.
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist \
    --no-interaction --ignore-platform-reqs

COPY . .
RUN composer dump-autoload --optimize --classmap-authoritative --no-dev --no-scripts \
    --ignore-platform-reqs

# ---- Stage 2: runtime --------------------------------------------------------
# serversideup/php: php-fpm + nginx in one container, listens on 8080, runs as
# an unprivileged user (www-data, uid 33 on the Debian variant).
FROM serversideup/php:8.3-fpm-nginx AS runtime

# Extensions: pdo_pgsql (RDS), redis (ElastiCache), pcntl (queue workers), apcu (per-pod Prometheus metrics).
USER root
RUN install-php-extensions pdo_pgsql redis pcntl opcache apcu
USER www-data

ENV PHP_OPCACHE_ENABLE=1 \
    APP_ENV=production

WORKDIR /var/www/html
COPY --from=vendor --chown=www-data:www-data /app ./

# The worker reuses this image with a different command (see helm/app/values/worker.yaml).
EXPOSE 8080

# No HEALTHCHECK here: Kubernetes probes own health, and a Docker HEALTHCHECK is ignored by the kubelet.
