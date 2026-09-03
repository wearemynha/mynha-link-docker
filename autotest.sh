#!/bin/sh

set -eu

# Prevent Git Bash on Windows from rewriting Linux container paths.
export MSYS_NO_PATHCONV=1

IMAGE_NAME="${IMAGE_NAME:-mynha-link-docker-smoke:local}"
TEST_PREFIX="mynha-link-docker-smoke-$$"
NETWORK_NAME="${TEST_PREFIX}-network"
APP_CONTAINER="${TEST_PREFIX}-app"
POSTGRES_CONTAINER="${TEST_PREFIX}-postgres"
APP_VOLUME="${TEST_PREFIX}-app-data"
POSTGRES_VOLUME="${TEST_PREFIX}-postgres-data"
POSTGRES_DB="linkstack_test"
POSTGRES_USER="linkstack_test"
POSTGRES_PASSWORD="smoke-test-password"

cleanup() {
    echo "Cleaning up smoke-test resources"
    docker rm --force "${APP_CONTAINER}" "${POSTGRES_CONTAINER}" >/dev/null 2>&1 || true
    docker volume rm "${APP_VOLUME}" "${POSTGRES_VOLUME}" >/dev/null 2>&1 || true
    docker network rm "${NETWORK_NAME}" >/dev/null 2>&1 || true
}

wait_for_postgres() {
    attempts=0
    until docker exec "${POSTGRES_CONTAINER}" pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" >/dev/null 2>&1; do
        attempts=$((attempts + 1))
        if [ "${attempts}" -ge 30 ]; then
            docker logs "${POSTGRES_CONTAINER}"
            echo "PostgreSQL did not become ready" >&2
            exit 1
        fi
        sleep 2
    done
}

wait_for_application() {
    attempts=0
    until [ "$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "${APP_CONTAINER}")" = "healthy" ]; do
        attempts=$((attempts + 1))
        if [ "${attempts}" -ge 45 ]; then
            docker logs "${APP_CONTAINER}"
            echo "Mynha Link did not become healthy" >&2
            exit 1
        fi
        sleep 2
    done
}

start_application() {
    docker run --detach \
        --name "${APP_CONTAINER}" \
        --network "${NETWORK_NAME}" \
        --volume "${APP_VOLUME}:/htdocs" \
        --env APP_ENV=production \
        --env APP_DEBUG=false \
        --env APP_URL=http://localhost \
        --env LOG_CHANNEL=stderr \
        --env DB_CONNECTION=pgsql \
        --env DB_HOST="${POSTGRES_CONTAINER}" \
        --env DB_PORT=5432 \
        --env DB_DATABASE="${POSTGRES_DB}" \
        --env DB_USERNAME="${POSTGRES_USER}" \
        --env DB_PASSWORD="${POSTGRES_PASSWORD}" \
        --env DB_SSLMODE=disable \
        --env MAIL_FROM_ADDRESS=no-reply@example.com \
        "${IMAGE_NAME}" >/dev/null
}

trap cleanup EXIT INT TERM

echo "Building ${IMAGE_NAME}"
docker build --tag "${IMAGE_NAME}" .
docker image inspect --format '{{json .Config.ExposedPorts}}' "${IMAGE_NAME}" | grep -q '"80/tcp"'
if docker image inspect --format '{{json .Config.ExposedPorts}}' "${IMAGE_NAME}" | grep -q '"443/tcp"'; then
    echo "The image must not expose port 443" >&2
    exit 1
fi

echo "Rejecting debug mode in production"
if docker run --rm \
    --env APP_ENV=production \
    --env APP_DEBUG=true \
    --env MAIL_FROM_ADDRESS=no-reply@example.com \
    "${IMAGE_NAME}" true >/dev/null 2>&1; then
    echo "The image accepted APP_DEBUG=true in production" >&2
    exit 1
fi

docker network create "${NETWORK_NAME}" >/dev/null
docker volume create "${APP_VOLUME}" >/dev/null
docker volume create "${POSTGRES_VOLUME}" >/dev/null

echo "Starting PostgreSQL"
docker run --detach \
    --name "${POSTGRES_CONTAINER}" \
    --network "${NETWORK_NAME}" \
    --volume "${POSTGRES_VOLUME}:/var/lib/postgresql/data" \
    --env POSTGRES_DB="${POSTGRES_DB}" \
    --env POSTGRES_USER="${POSTGRES_USER}" \
    --env POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
    postgres:17-alpine >/dev/null
wait_for_postgres

echo "Starting Mynha Link"
start_application
wait_for_application

echo "Checking runtime and installer"
docker exec "${APP_CONTAINER}" php -m | grep -q '^pdo_pgsql$'
docker exec "${APP_CONTAINER}" php -m | grep -q '^imagick$'
docker exec "${APP_CONTAINER}" test -f /htdocs/build/manifest.json
docker exec "${APP_CONTAINER}" test ! -d /htdocs/node_modules
docker exec "${APP_CONTAINER}" test ! -d /htdocs/tests
docker exec "${APP_CONTAINER}" test ! -e /htdocs/vendor/bin/phpunit
docker exec "${APP_CONTAINER}" test -f /htdocs/bootstrap/cache/config.php
docker exec "${APP_CONTAINER}" test -f /htdocs/storage/app/INSTALLING
docker exec "${APP_CONTAINER}" test ! -e /htdocs/INSTALLING
docker exec "${APP_CONTAINER}" stat -c '%U:%G' /htdocs | grep -q '^root:root$'
docker exec "${APP_CONTAINER}" stat -c '%U:%G' /htdocs/config | grep -q '^root:root$'
docker exec --user apache:apache "${APP_CONTAINER}" test ! -w /htdocs
docker exec --user apache:apache "${APP_CONTAINER}" test ! -w /htdocs/config
docker exec --user apache:apache "${APP_CONTAINER}" test -w /htdocs/.env
docker exec "${APP_CONTAINER}" grep -q '^APP_ENV="production"$' /htdocs/.env
docker exec "${APP_CONTAINER}" grep -q '^APP_DEBUG=false$' /htdocs/.env
docker exec "${APP_CONTAINER}" curl --fail --silent --show-error http://localhost/ | grep -q 'language-form'
if docker exec \
    --env DB_HOST=127.0.0.1 \
    --env DB_PORT=1 \
    "${APP_CONTAINER}" docker-healthcheck.sh >/dev/null 2>&1; then
    echo "Healthcheck accepted an unavailable database" >&2
    exit 1
fi

echo "Preparing persistence checks"
APP_KEY_BEFORE="$(docker exec "${APP_CONTAINER}" sh -c "grep '^APP_KEY=' /htdocs/.env | cut -d '=' -f 2-")"
docker exec --user apache:apache "${APP_CONTAINER}" sh -c "printf '\n%s\n' 'MAIL_USERNAME=legacy-user' >> /htdocs/.env"
docker exec --user apache:apache "${APP_CONTAINER}" sh -c "printf '%s\n' 'storage-ok' > /htdocs/storage/persistence-marker"
docker exec "${APP_CONTAINER}" sh -c "mkdir -p /htdocs/themes/custom-smoke && printf '%s\n' 'theme-ok' > /htdocs/themes/custom-smoke/marker"
docker exec --user apache:apache "${APP_CONTAINER}" sh -c "printf '%s\n' '<?php return [];' > /htdocs/config/advanced-config.php"
docker exec --user apache:apache "${APP_CONTAINER}" test -w /htdocs/storage/persistence-marker
docker exec --user apache:apache "${APP_CONTAINER}" test ! -w /htdocs/themes/custom-smoke/marker
docker exec --user apache:apache "${APP_CONTAINER}" test -w /htdocs/config/advanced-config.php
if docker exec --user apache:apache "${APP_CONTAINER}" touch /htdocs/runtime-code.php >/dev/null 2>&1; then
    echo "The Apache user can create files in the application root" >&2
    exit 1
fi
if docker exec --user apache:apache "${APP_CONTAINER}" touch /htdocs/config/runtime-code.php >/dev/null 2>&1; then
    echo "The Apache user can create files in the configuration directory" >&2
    exit 1
fi
docker exec "${APP_CONTAINER}" sh -c "printf '%s\n' 'remove-me' > /htdocs/obsolete-code-file"
docker exec "${POSTGRES_CONTAINER}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -c "CREATE TABLE smoke_test (value text NOT NULL); INSERT INTO smoke_test VALUES ('database-ok');" >/dev/null

echo "Recreating the application container"
docker rm --force "${APP_CONTAINER}" >/dev/null
start_application
wait_for_application

[ "${APP_KEY_BEFORE}" = "$(docker exec "${APP_CONTAINER}" sh -c "grep '^APP_KEY=' /htdocs/.env | cut -d '=' -f 2-")" ]
docker exec "${APP_CONTAINER}" sh -c "! grep -q '^MAIL_USERNAME=' /htdocs/.env"
docker exec "${APP_CONTAINER}" grep -q '^APP_ENV="production"$' /htdocs/.env
docker exec "${APP_CONTAINER}" grep -q '^APP_DEBUG=false$' /htdocs/.env
docker exec "${APP_CONTAINER}" grep -q '^storage-ok$' /htdocs/storage/persistence-marker
docker exec "${APP_CONTAINER}" grep -q '^theme-ok$' /htdocs/themes/custom-smoke/marker
docker exec "${APP_CONTAINER}" test -f /htdocs/config/advanced-config.php
docker exec --user apache:apache "${APP_CONTAINER}" test -w /htdocs/storage/persistence-marker
docker exec --user apache:apache "${APP_CONTAINER}" test ! -w /htdocs/themes/custom-smoke/marker
docker exec --user apache:apache "${APP_CONTAINER}" test -w /htdocs/config/advanced-config.php
docker exec --user apache:apache "${APP_CONTAINER}" test ! -w /htdocs
docker exec --user apache:apache "${APP_CONTAINER}" test ! -w /htdocs/config
docker exec "${APP_CONTAINER}" stat -c '%U:%G' /htdocs | grep -q '^root:root$'
docker exec "${APP_CONTAINER}" stat -c '%U:%G' /htdocs/config | grep -q '^root:root$'
docker exec "${APP_CONTAINER}" stat -c '%U:%G' /htdocs/storage/persistence-marker | grep -q '^apache:apache$'
docker exec "${APP_CONTAINER}" stat -c '%U:%G' /htdocs/themes/custom-smoke/marker | grep -q '^root:root$'
docker exec "${APP_CONTAINER}" stat -c '%U:%G' /htdocs/config/advanced-config.php | grep -q '^apache:apache$'
docker exec "${APP_CONTAINER}" test ! -e /htdocs/obsolete-code-file
docker exec "${POSTGRES_CONTAINER}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -tAc "SELECT value FROM smoke_test LIMIT 1" | grep -q '^database-ok$'
docker exec "${APP_CONTAINER}" curl --fail --silent --show-error http://localhost/ | grep -q 'language-form'

echo "Smoke test passed"
