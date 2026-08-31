#!/bin/sh

set -eu

APP_SOURCE="${APP_SOURCE:-/opt/linkstack}"
APP_ROOT="${APP_ROOT:-/htdocs}"
RUN_AS="apache:apache"
RUNTIME_PHP_CONFIG="/etc/php83/conf.d/99-linkstack-runtime.ini"

export SERVER_ADMIN="${SERVER_ADMIN:-admin@example.com}"
export HTTP_SERVER_NAME="${HTTP_SERVER_NAME:-localhost}"
export HTTPS_SERVER_NAME="${HTTPS_SERVER_NAME:-localhost}"
export LOG_LEVEL="${LOG_LEVEL:-info}"
export TZ="${TZ:-UTC}"
export PHP_MEMORY_LIMIT="${PHP_MEMORY_LIMIT:-256M}"
export UPLOAD_MAX_FILESIZE="${UPLOAD_MAX_FILESIZE:-8M}"
export POST_MAX_SIZE="${POST_MAX_SIZE:-16M}"

write_runtime_php_config() {
    printf '%s\n' \
        "upload_max_filesize = ${UPLOAD_MAX_FILESIZE}" \
        "post_max_size = ${POST_MAX_SIZE}" \
        "memory_limit = ${PHP_MEMORY_LIMIT}" \
        "date.timezone = ${TZ}" \
        > "${RUNTIME_PHP_CONFIG}"
}

sync_application() {
    if [ ! -f "${APP_ROOT}/artisan" ]; then
        echo "Initializing the application volume"
        cp -a "${APP_SOURCE}/." "${APP_ROOT}/"
        touch "${APP_ROOT}/INSTALLING"
        return
    fi

    echo "Synchronizing application code while preserving runtime data"
    rsync -a --delete \
        --exclude='/.env' \
        --exclude='/.env.backup' \
        --exclude='/INSTALLING' \
        --exclude='/INSTALLERLOCK' \
        --exclude='/config/advanced-config.php' \
        --exclude='/storage/***' \
        --exclude='/backups/***' \
        --exclude='/themes/***' \
        --exclude='/assets/img/***' \
        --exclude='/assets/favicon/icons/***' \
        --exclude='/assets/linkstack/images/***' \
        --exclude='/assets/dashboard-themes/***' \
        "${APP_SOURCE}/" "${APP_ROOT}/"

    if [ -d "${APP_SOURCE}/storage/templates" ]; then
        mkdir -p "${APP_ROOT}/storage/templates"
        rsync -a --delete \
            "${APP_SOURCE}/storage/templates/" \
            "${APP_ROOT}/storage/templates/"
    fi

    if [ -d "${APP_SOURCE}/themes" ]; then
        mkdir -p "${APP_ROOT}/themes"
        rsync -a "${APP_SOURCE}/themes/" "${APP_ROOT}/themes/"
    fi
}

prepare_writable_paths() {
    mkdir -p \
        "${APP_ROOT}/assets/dashboard-themes" \
        "${APP_ROOT}/assets/favicon/icons" \
        "${APP_ROOT}/assets/img/background-img" \
        "${APP_ROOT}/assets/linkstack/images" \
        "${APP_ROOT}/backups" \
        "${APP_ROOT}/bootstrap/cache" \
        "${APP_ROOT}/storage/app/public" \
        "${APP_ROOT}/storage/framework/cache/data" \
        "${APP_ROOT}/storage/framework/sessions" \
        "${APP_ROOT}/storage/framework/views" \
        "${APP_ROOT}/storage/logs" \
        "${APP_ROOT}/themes"

    chown apache:apache "${APP_ROOT}" "${APP_ROOT}/config"
    chown -R apache:apache \
        "${APP_ROOT}/assets/dashboard-themes" \
        "${APP_ROOT}/assets/favicon/icons" \
        "${APP_ROOT}/assets/img" \
        "${APP_ROOT}/assets/linkstack/images" \
        "${APP_ROOT}/backups" \
        "${APP_ROOT}/bootstrap/cache" \
        "${APP_ROOT}/storage" \
        "${APP_ROOT}/themes"
}

prepare_environment() {
    if [ ! -f "${APP_ROOT}/.env" ]; then
        echo "Creating .env from .env.example"
        cp "${APP_ROOT}/.env.example" "${APP_ROOT}/.env"
    fi

    chown apache:apache "${APP_ROOT}/.env"
    chmod 0600 "${APP_ROOT}/.env"

    persisted_app_key="$(sed -n 's/^APP_KEY=//p' "${APP_ROOT}/.env" | tr -d '\r' | tail -n 1)"

    if [ -z "${APP_KEY:-}" ] && [ -z "${persisted_app_key}" ]; then
        echo "Generating the application key"
        su-exec "${RUN_AS}" php artisan key:generate --force --no-interaction
    fi
}

clear_stale_caches() {
    su-exec "${RUN_AS}" php artisan optimize:clear --no-interaction
}

print_startup_summary() {
    version="unknown"
    if [ -f "${APP_ROOT}/version.json" ]; then
        version="$(tr -d '\r\n' < "${APP_ROOT}/version.json")"
    fi

    echo "Mynha Link ${version}"
    echo "Apache HTTP host: ${HTTP_SERVER_NAME}"
    echo "Apache HTTPS host: ${HTTPS_SERVER_NAME}"
    echo "PHP memory limit: ${PHP_MEMORY_LIMIT}"
    echo "Maximum upload size: ${UPLOAD_MAX_FILESIZE}"
    echo "Timezone: ${TZ}"
}

write_runtime_php_config
sync_application
prepare_writable_paths
cd "${APP_ROOT}"
prepare_environment
clear_stale_caches
print_startup_summary

if [ "${1:-}" = "httpd" ]; then
    exec "$@"
fi

exec su-exec "${RUN_AS}" "$@"
