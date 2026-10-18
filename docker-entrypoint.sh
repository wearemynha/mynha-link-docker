#!/bin/sh

set -eu

APP_SOURCE="${APP_SOURCE:-/opt/mynha-link}"
APP_ROOT="${APP_ROOT:-/htdocs}"
RUN_AS="apache:apache"
RUNTIME_PHP_CONFIG="/etc/php83/conf.d/99-mynha-link-runtime.ini"

export SERVER_ADMIN="${SERVER_ADMIN:-admin@example.com}"
export HTTP_SERVER_NAME="${HTTP_SERVER_NAME:-localhost}"
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
        mkdir -p "${APP_ROOT}/storage/app"
        touch "${APP_ROOT}/storage/app/INSTALLING"
        return
    fi

    echo "Synchronizing application code while preserving runtime data"
    rsync -a --delete \
        --exclude='/.env' \
        --exclude='/.env.backup' \
        --exclude='/.mynha-packaged-themes' \
        --exclude='/INSTALLING' \
        --exclude='/INSTALLERLOCK' \
        --exclude='/config/advanced-config.php' \
        --exclude='/storage/***' \
        --exclude='/backups/***' \
        --exclude='/themes/***' \
        --exclude='/assets/img/***' \
        --exclude='/assets/favicon/icons/***' \
        --exclude='/assets/linkstack/images/avatar_*' \
        --exclude='/assets/linkstack/images/favicon_*' \
        --exclude='/assets/dashboard-themes/***' \
        "${APP_SOURCE}/" "${APP_ROOT}/"

    if [ -d "${APP_SOURCE}/storage/templates" ]; then
        mkdir -p "${APP_ROOT}/storage/templates"
        rsync -a --delete \
            "${APP_SOURCE}/storage/templates/" \
            "${APP_ROOT}/storage/templates/"
    fi

}

sync_packaged_themes() {
    manifest="${APP_ROOT}/.mynha-packaged-themes"
    mkdir -p "${APP_ROOT}/themes"

    # Retire only themes supplied by a previous image. Keep separately added themes.
    if [ -f "${manifest}" ]; then
        while IFS= read -r theme_name; do
            case "${theme_name}" in
                ''|*[!a-zA-Z0-9_-]*)
                    echo "Invalid packaged theme name: ${theme_name}" >&2
                    exit 1
                    ;;
            esac
            if [ ! -d "${APP_SOURCE}/themes/${theme_name}" ]; then
                rm -rf -- "${APP_ROOT}/themes/${theme_name}"
            fi
        done < "${manifest}"
    fi

    : > "${manifest}.next"
    if [ -d "${APP_SOURCE}/themes" ]; then
        # Copy root-level license files along with the themes.
        rsync -a "${APP_SOURCE}/themes/" "${APP_ROOT}/themes/"
        for theme_path in "${APP_SOURCE}/themes/"*; do
            [ -d "${theme_path}" ] || continue
            theme_name="${theme_path##*/}"
            case "${theme_name}" in
                *[!a-zA-Z0-9_-]*)
                    echo "Invalid packaged theme name: ${theme_name}" >&2
                    exit 1
                    ;;
            esac
            rsync -a --delete "${theme_path}/" "${APP_ROOT}/themes/${theme_name}/"
            printf '%s\n' "${theme_name}" >> "${manifest}.next"
        done
    fi
    mv "${manifest}.next" "${manifest}"
    chown root:root "${manifest}"
    chmod 0644 "${manifest}"
}

migrate_installer_markers() {
    mkdir -p "${APP_ROOT}/storage/app"

    for marker in INSTALLING INSTALLERLOCK; do
        legacy_marker="${APP_ROOT}/${marker}"
        current_marker="${APP_ROOT}/storage/app/${marker}"

        if [ -f "${legacy_marker}" ]; then
            if [ -f "${current_marker}" ]; then
                rm -f "${legacy_marker}"
            else
                mv "${legacy_marker}" "${current_marker}"
            fi
        fi
    done
}

prepare_writable_paths() {
    mkdir -p \
        "${APP_ROOT}/assets/dashboard-themes" \
        "${APP_ROOT}/assets/favicon/icons" \
        "${APP_ROOT}/assets/img/background-img" \
        "${APP_ROOT}/assets/linkstack/images" \
        "${APP_ROOT}/backups" \
        "${APP_ROOT}/bootstrap/cache" \
        "${APP_ROOT}/storage/app" \
        "${APP_ROOT}/storage/app/public" \
        "${APP_ROOT}/storage/framework/cache/data" \
        "${APP_ROOT}/storage/framework/sessions" \
        "${APP_ROOT}/storage/framework/views" \
        "${APP_ROOT}/storage/logs"

    if [ ! -f "${APP_ROOT}/config/advanced-config.php" ]; then
        if [ ! -f "${APP_ROOT}/storage/templates/advanced-config.php" ]; then
            echo "Advanced configuration template not found" >&2
            exit 1
        fi

        cp \
            "${APP_ROOT}/storage/templates/advanced-config.php" \
            "${APP_ROOT}/config/advanced-config.php"
    fi

    chown root:root "${APP_ROOT}" "${APP_ROOT}/config"
    chmod 0755 "${APP_ROOT}" "${APP_ROOT}/config"

    chown -R apache:apache \
        "${APP_ROOT}/assets/dashboard-themes" \
        "${APP_ROOT}/assets/favicon/icons" \
        "${APP_ROOT}/assets/img" \
        "${APP_ROOT}/assets/linkstack/images" \
        "${APP_ROOT}/backups" \
        "${APP_ROOT}/bootstrap/cache" \
        "${APP_ROOT}/storage"

    chown apache:apache "${APP_ROOT}/config/advanced-config.php"
    chmod 0600 "${APP_ROOT}/config/advanced-config.php"

    chown -R root:root "${APP_ROOT}/themes"
    find "${APP_ROOT}/themes" -type d -exec chmod 0755 {} +
    find "${APP_ROOT}/themes" -type f -exec chmod 0644 {} +
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

synchronize_runtime_environment() {
    process_keys="$(env | cut -d '=' -f 1 | tr '\n' ',')"
    su-exec "${RUN_AS}" php artisan runtime:sync-environment --cache --clear-missing --process-keys="${process_keys}" --no-interaction
}

print_startup_summary() {
    version="unknown"
    if [ -f "${APP_ROOT}/version.json" ]; then
        version="$(tr -d '\r\n' < "${APP_ROOT}/version.json")"
    fi

    echo "Mynha Link ${version}"
    echo "Apache HTTP host: ${HTTP_SERVER_NAME}"
    echo "PHP memory limit: ${PHP_MEMORY_LIMIT}"
    echo "Maximum upload size: ${UPLOAD_MAX_FILESIZE}"
    echo "Timezone: ${TZ}"
}

write_runtime_php_config
sync_application
sync_packaged_themes
migrate_installer_markers
prepare_writable_paths
cd "${APP_ROOT}"
prepare_environment
synchronize_runtime_environment
print_startup_summary

if [ "${1:-}" = "httpd" ]; then
    exec "$@"
fi

exec su-exec "${RUN_AS}" "$@"
