# Docker Deployment (Backend API)

This guide deploys the Go backend with a Docker image and applies Prisma migrations before starting traffic.

## Official references
- Docker build CLI: https://docs.docker.com/reference/cli/docker/buildx/build/
- Docker run CLI: https://docs.docker.com/reference/cli/docker/container/run/
- Prisma migrate deploy (production): https://www.prisma.io/docs/orm/prisma-client/deployment/deploy-database-changes-with-prisma-migrate
- Prisma baselining existing DBs: https://www.prisma.io/docs/orm/prisma-migrate/workflows/baselining

## Build image
From repo root:

```bash
docker buildx build --platform linux/amd64 -t babyai-api:latest .
```

Image architecture check:

```bash
docker image inspect babyai-api:latest --format '{{.Architecture}}/{{.Os}}'
```

## Required runtime env
- `DATABASE_URL`
- `JWT_SECRET`
- `APP_ENV=production`
- `AUTH_ACCEPT_GOOGLE_ID_TOKEN=true`
- `GOOGLE_OAUTH_CLIENT_IDS=<google-web-client-id>`
- `OPENAI_API_KEY` (required for AI routes)

## Apply migrations (one-shot container / pre-deploy job)
Run migration first, then start API container.

```bash
docker run --rm \
  -e DATABASE_URL="$DATABASE_URL" \
  babyai-api:latest \
  npm run prisma:migrate:deploy
```

## Start API container

```bash
docker run --rm -p 8080:8080 \
  -e PORT=8080 \
  -e APP_ENV=production \
  -e DATABASE_URL="$DATABASE_URL" \
  -e JWT_SECRET="$JWT_SECRET" \
  -e OPENAI_API_KEY="$OPENAI_API_KEY" \
  babyai-api:latest
```

Health check:

```bash
curl http://127.0.0.1:8080/health
```

## Note for current repo transition
Recommended path is DB reset/wipe once, then migrate-only flow (`prisma:migrate:deploy`).
If DB reset is not possible, baseline before switching to migration-based deploys.

Baseline example:

```bash
docker run --rm \
  -e DATABASE_URL="$DATABASE_URL" \
  babyai-api:latest \
  npx prisma migrate resolve \
  --applied <migration_folder_name> \
  --schema packages/schema/prisma/schema.prisma
```

Repository shortcut for the current initial migration:

```bash
docker run --rm \
  -e DATABASE_URL="$DATABASE_URL" \
  babyai-api:latest \
  npm run prisma:migrate:baseline:init
```
