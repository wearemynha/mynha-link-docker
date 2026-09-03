# syntax=docker/dockerfile:1.7

ARG ALPINE_VERSION=3.23.5
ARG NODE_VERSION=24-alpine

FROM node:${NODE_VERSION} AS frontend-builder

WORKDIR /app

COPY linkstack/package.json linkstack/package-lock.json ./
RUN npm ci --no-audit --no-fund

COPY linkstack/ ./
RUN npm run build


FROM alpine:${ALPINE_VERSION} AS backend-builder

RUN apk add --no-cache \
        ca-certificates \
        git \
        php83 \
        php83-bcmath \
        php83-bz2 \
        php83-calendar \
        php83-ctype \
        php83-curl \
        php83-dom \
        php83-fileinfo \
        php83-gd \
        php83-iconv \
        php83-intl \
        php83-mbstring \
        php83-openssl \
        php83-pdo \
        php83-pdo_pgsql \
        php83-phar \
        php83-session \
        php83-simplexml \
        php83-sodium \
        php83-tokenizer \
        php83-xml \
        php83-xmlreader \
        php83-xmlwriter \
        php83-zip \
        unzip \
    && ln -sf /usr/bin/php83 /usr/local/bin/php

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

WORKDIR /app

COPY linkstack/ ./
COPY --from=frontend-builder /app/build ./build

RUN cp .env.example .env \
    && composer install \
        --no-dev \
        --no-interaction \
        --no-progress \
        --prefer-dist \
        --optimize-autoloader \
        --classmap-authoritative \
    && composer check-platform-reqs --no-dev \
    && rm -f .env .env.backup \
    && rm -rf node_modules tests .git .idea \
    && find . -type d -exec chmod 0755 {} + \
    && find . -type f -exec chmod 0644 {} + \
    && chmod 0755 artisan


FROM alpine:${ALPINE_VERSION} AS runtime

LABEL org.opencontainers.image.title="Mynha Link" \
      org.opencontainers.image.description="Mynha Link runtime image" \
      org.opencontainers.image.vendor="Mynha" \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.source="https://github.com/wearemynha/mynha-link-docker"

RUN apk add --no-cache \
        apache2 \
        ca-certificates \
        curl \
        php83 \
        php83-apache2 \
        php83-bcmath \
        php83-bz2 \
        php83-calendar \
        php83-ctype \
        php83-curl \
        php83-dom \
        php83-fileinfo \
        php83-gd \
        php83-iconv \
        php83-intl \
        php83-mbstring \
        php83-opcache \
        php83-openssl \
        php83-pdo \
        php83-pdo_pgsql \
        php83-phar \
        php83-session \
        php83-simplexml \
        php83-sodium \
        php83-tokenizer \
        php83-xml \
        php83-xmlreader \
        php83-xmlwriter \
        php83-zip \
        php83-pecl-imagick \
        rsync \
        su-exec \
        tzdata \
    && ln -sf /usr/bin/php83 /usr/local/bin/php \
    && mkdir -p /htdocs /opt/linkstack /run/apache2 \
    && chown root:root /htdocs /opt/linkstack \
    && chown apache:apache /run/apache2

COPY --from=backend-builder /app /opt/linkstack
COPY configs/apache2/httpd.conf /etc/apache2/httpd.conf
COPY configs/php/php.ini /etc/php83/conf.d/40-custom.ini

COPY --chmod=0755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY --chmod=0755 docker-healthcheck.sh /usr/local/bin/docker-healthcheck.sh

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=8s --start-period=30s --retries=3 \
    CMD ["docker-healthcheck.sh"]

WORKDIR /htdocs

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["httpd", "-D", "FOREGROUND"]
