#!/bin/sh

set -eu

HTTP_HEALTHCHECK_URL="${HTTP_HEALTHCHECK_URL:-http://localhost/build/manifest.json}"

curl --fail --silent --show-error --max-time 3 \
    --user-agent HealthCheck \
    "${HTTP_HEALTHCHECK_URL}" >/dev/null

php <<'PHP'
<?php

$requiredVariables = [
    'DB_HOST',
    'DB_PORT',
    'DB_DATABASE',
    'DB_USERNAME',
    'DB_PASSWORD',
];

foreach ($requiredVariables as $variable) {
    if (getenv($variable) === false) {
        fwrite(STDERR, "Missing database healthcheck configuration.\n");
        exit(1);
    }
}

$sslMode = getenv('DB_SSLMODE') ?: 'prefer';
$dsn = sprintf(
    'pgsql:host=%s;port=%s;dbname=%s;sslmode=%s;connect_timeout=3',
    getenv('DB_HOST'),
    getenv('DB_PORT'),
    getenv('DB_DATABASE'),
    $sslMode,
);

try {
    $connection = new PDO(
        $dsn,
        getenv('DB_USERNAME'),
        getenv('DB_PASSWORD'),
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION],
    );

    $result = $connection->query('SELECT 1')->fetchColumn();

    exit((int) $result === 1 ? 0 : 1);
} catch (Throwable) {
    fwrite(STDERR, "Database healthcheck failed.\n");
    exit(1);
}
PHP
