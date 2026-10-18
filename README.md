# Mynha Link Docker

Docker image for **Mynha Link**, the LinkStack fork maintained by Mynha.

The image includes Apache, PHP 8.3, production PHP dependencies, and compiled frontend assets. The environment defined in `docker-compose.yml` uses PostgreSQL 17.

## Getting the source

You need Git, Docker, and the Docker Compose plugin to build and run this project locally.

The repository contains two submodules:

- `sources/mynha-link`: application source code;
- `sources/mynha-link-themes`: Mynha themes, stored under its `themes/` directory.

Initialize them after cloning:

```sh
git submodule update --init --recursive
```

Alternatively, clone the repository with `git clone --recurse-submodules`. The submodule URLs use SSH, so cloning requires GitHub SSH access. Although `.gitmodules` specifies `main`, normal submodule initialization checks out the exact commits recorded by this repository.

The Docker build reads the application directly from `sources/mynha-link` and packages the themes from `sources/mynha-link-themes/themes`, together with their license and attribution files. Initializing both submodules is sufficient to prepare the source.

The build context excludes Git metadata, local application environment files, dependencies, and generated assets. The application's `.env.example` is included for initialization.

After pulling changes to this repository, run `git submodule update --init --recursive` again before building to check out the recorded submodule revisions. Local changes inside either submodule are also used by a local build; release builds should use clean checkouts of the pinned commits.

## Running locally

After preparing the source as described above, create the local configuration file:

```sh
cp .env.local.example .env
```

In PowerShell:

```powershell
Copy-Item .env.local.example .env
```

Set `POSTGRES_PASSWORD` in `.env` to a local password, then start the environment:

```sh
docker compose -f docker-compose.yml -f docker-compose.local.yml up --detach --build
```

The base Compose file does not publish any host ports. The `docker-compose.local.yml` override adds the `${HTTP_PORT:-8080}:80` mapping for local browser access.

Open `http://localhost:8080`. To follow startup logs:

```sh
docker compose -f docker-compose.yml -f docker-compose.local.yml logs --follow mynha-link
```

To stop the containers without deleting their data:

```sh
docker compose -f docker-compose.yml -f docker-compose.local.yml down
```

## Persistence and updates

Compose maintains two volumes:

- `mynha_link_data`: the application's `.env`, uploads, backups, advanced configuration, and other mutable data;
- `postgres_data`: the PostgreSQL database.

Application code and packaged themes are stored in `/opt/linkstack` inside the image. At startup, they are synchronized to `/htdocs` while preserving mutable data. The themes directory is read-only for Apache; new themes must be supplied through the source and build process. Synchronization does not remove themes already present in the volume, even when they are absent from a later image.

To build and apply an updated application image:

```sh
docker compose build --pull mynha-link
docker compose up --detach --force-recreate mynha-link
```

For local deployments, use `-f docker-compose.yml -f docker-compose.local.yml` with both commands to retain the local port mapping.

Back up both volumes before production updates. Do not run `docker compose down --volumes` in an environment containing data you need to preserve.

## Configuration

`.env.example` is the full production configuration template. For local use, `.env.local.example` contains only the values needed to override the local defaults in Compose. Each environment uses a single actual `.env` file.

The main settings are:

| Variable | Purpose | Compose default / production example |
| --- | --- | --- |
| `APP_URL` | Public application URL | `http://localhost:8080` / `https://link.example.com` |
| `POSTGRES_DB` | Database name | `mynha_link` |
| `POSTGRES_USER` | Database user | `mynha_link` |
| `POSTGRES_PASSWORD` | Database password | Required; no default |
| `DB_SSLMODE` | PostgreSQL SSL mode | `disable` |
| `HTTP_PORT` | HTTP port published by the local override | `8080` |
| `PHP_MEMORY_LIMIT` | PHP memory limit | `256M` |
| `UPLOAD_MAX_FILESIZE` | Maximum individual upload size | `8M` |
| `POST_MAX_SIZE` | Maximum request body size | `16M` |
| `TZ` | Container timezone | `America/Sao_Paulo` |

Secret fields are empty in the examples so that Compose stops until required values are supplied. In production, set a strong database password, replace `<version>` with an immutable image tag, configure `APP_URL` with your public domain, and keep `APP_DEBUG=false`. Startup is blocked when `APP_DEBUG=true` is combined with `APP_ENV=production`. Compose does not publish PostgreSQL to the host.

This repository's `.env` supplies the Docker deployment configuration. Compose forwards an explicit list of deployment variables to the container. At startup, these values are synchronized with Mynha Link's persistent `.env`, and Laravel's configuration cache is rebuilt.

A deployment-managed key that is no longer supplied is removed from the persistent environment, preventing stale values from remaining active. `APP_KEY` is the exception: when the deployment does not supply it, the application's generated and persisted key is preserved. Settings managed by the installer or dashboard, such as the application name, active language, registration, and homepage, are also preserved.

The `/htdocs` root and `/htdocs/config` directory belong to `root` and are not writable by Apache. The application can write only to `.env`, `config/advanced-config.php`, and mutable data directories such as storage, uploads, caches, and backups.

Apache listens for HTTP on port 80. The base Compose file documents this port without publishing it to the host. In production, configure Traefik or your reverse proxy to terminate TLS and forward requests to this port. The image contains no HTTPS listener or certificate.

## Manual build

Initialize both submodules as described under "Getting the source", then run:

```sh
docker build --tag <TAG> .
```

The build has three stages:

1. Compile frontend assets with Node.js.
2. Install production PHP dependencies with Composer and package the Mynha themes and their license notices.
3. Create the runtime image without `node_modules`, tests, or development tools.

## Automated smoke test

On Linux, WSL, or Git Bash, run:

```sh
sh ./autotest.sh
```

The script creates isolated, temporary Docker resources and checks PostgreSQL, PHP extensions, frontend assets, packaged Mynha themes and their license files, the installer, health checks, permissions, stale configuration cleanup, and persistence after container recreation. Temporary resources are removed when the script finishes, including on failure.

## License

This project is distributed under the GNU Affero General Public License, version 3 only (`AGPL-3.0-only`). Mynha Link Docker is a fork of [LinkStack Docker](https://github.com/LinkStackOrg/linkstack-docker), maintained by Mynha. Copyright notices and third-party component licenses are preserved.

See [LICENSE](LICENSE) for the full terms and [LICENSING.md](LICENSING.md) for authorship, modifications, and scope.
