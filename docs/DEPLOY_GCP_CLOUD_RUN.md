# GCP Deployment (Cloud Run + Cloud Build)

This guide deploys the backend API with a fixed Docker build environment on Google Cloud Run and runs Prisma migrations with a Cloud Run Job.

## Official references
- Cloud Run deploy from source/container: https://cloud.google.com/run/docs/deploying-source-code
- Cloud Run container runtime contract (`PORT`, listening interface): https://cloud.google.com/run/docs/container-contract
- Cloud Run Jobs: https://cloud.google.com/run/docs/create-jobs
- Cloud Run secrets integration: https://cloud.google.com/run/docs/configuring/services/secrets
- Cloud Run job secrets integration: https://cloud.google.com/run/docs/configuring/jobs/secrets
- Cloud Build config file schema: https://cloud.google.com/build/docs/build-config-file-schema
- Cloud Build deploy to Cloud Run (required roles): https://cloud.google.com/build/docs/deploying-builds/deploy-cloud-run
- Artifact Registry Docker quickstart: https://cloud.google.com/artifact-registry/docs/docker/store-docker-container-images
- Prisma migrate deploy (production): https://www.prisma.io/docs/orm/prisma-client/deployment/deploy-database-changes-with-prisma-migrate

## Why this path
- This repository already has a Dockerized backend build (`/Dockerfile`).
- Cloud Run + Dockerfile removes most buildpack/runtime mismatch issues.
- Migration is executed explicitly before service rollout.

## Files used
- `/cloudbuild.cloudrun.yaml`
- `/Dockerfile`
- `/packages/schema/prisma/schema.prisma`

## 1) One-time GCP setup
Enable APIs:

```bash
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  secretmanager.googleapis.com
```

Create Artifact Registry repository (Docker):

```bash
gcloud artifacts repositories create babyai \
  --repository-format=docker \
  --location=us-central1 \
  --description="BabyAI backend images"
```

Create/update secrets:

```bash
printf '%s' "$DATABASE_URL" | gcloud secrets create babyai-database-url \
  --replication-policy=automatic \
  --data-file=-

printf '%s' "$JWT_SECRET" | gcloud secrets create babyai-jwt-secret \
  --replication-policy=automatic \
  --data-file=-
```

If secrets already exist, add new versions instead:

```bash
printf '%s' "$DATABASE_URL" | gcloud secrets versions add babyai-database-url --data-file=-
printf '%s' "$JWT_SECRET" | gcloud secrets versions add babyai-jwt-secret --data-file=-
```

Grant secret access to Cloud Run runtime service account:

```bash
PROJECT_ID="$(gcloud config get-value project)"
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
RUNTIME_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

gcloud secrets add-iam-policy-binding babyai-database-url \
  --member="serviceAccount:${RUNTIME_SA}" \
  --role="roles/secretmanager.secretAccessor"

gcloud secrets add-iam-policy-binding babyai-jwt-secret \
  --member="serviceAccount:${RUNTIME_SA}" \
  --role="roles/secretmanager.secretAccessor"
```

Cloud Build service account permissions (minimum for this pipeline):

```bash
PROJECT_ID="$(gcloud config get-value project)"
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
CLOUD_BUILD_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${CLOUD_BUILD_SA}" \
  --role="roles/run.admin"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${CLOUD_BUILD_SA}" \
  --role="roles/artifactregistry.writer"

gcloud iam service-accounts add-iam-policy-binding "${RUNTIME_SA}" \
  --member="serviceAccount:${CLOUD_BUILD_SA}" \
  --role="roles/iam.serviceAccountUser"
```

## 2) Build + migrate + deploy
Run Cloud Build from repository root:

```bash
gcloud builds submit \
  --config cloudbuild.cloudrun.yaml \
  --substitutions=_REGION=us-central1,_AR_REPO=babyai,_IMAGE=babyai-api,_SERVICE=babyai-api,_MIGRATION_JOB=babyai-db-migrate,_DATABASE_URL_SECRET=babyai-database-url,_JWT_SECRET_SECRET=babyai-jwt-secret,_GOOGLE_OAUTH_CLIENT_IDS=<google-web-client-id> \
  .
```

Pipeline order in `cloudbuild.cloudrun.yaml`:
1. Build image (`docker build`)
2. Push image to Artifact Registry
3. Deploy/update Cloud Run migration Job
4. Execute migration Job (`npm run prisma:migrate:deploy`)
5. Deploy Cloud Run service revision

## 3) Verify
Get service URL and health-check:

```bash
SERVICE_URL="$(gcloud run services describe babyai-api --region us-central1 --format='value(status.url)')"
curl "${SERVICE_URL}/health"
```

Expected response:

```json
{"status":"ok","service":"babyai-api"}
```

## 4) Mobile app production endpoint
For Flutter build defines:
- `API_BASE_URL=<Cloud Run service URL>`
- `GOOGLE_SERVER_CLIENT_ID=<google-web-client-id>`

## 5) macOS local vs cloud parity
- macOS (especially Apple Silicon) can build ARM images by default.
- Cloud Run runtime is Linux-based and failures can occur when image architecture does not match runtime expectations.
- Always build/test with explicit platform target:

```bash
docker buildx build --platform linux/amd64 -f Dockerfile .
```

If `docker buildx` is missing:
https://docs.docker.com/build/buildx/install/

- Run project parity check:

```bash
./apps/backend/scripts/self_check_env_parity.sh
```

Detailed parity notes: `docs/LOCAL_ENV_PARITY.md`

## 6) Troubleshooting checklist
- Build fails with Go toolchain mismatch:
  - Confirm `/apps/backend/go.mod` and `/Dockerfile` use the same Go major/minor.
- Service starts then exits immediately:
  - Check `DATABASE_URL`, `JWT_SECRET` secrets exist and are attached.
- API unreachable after deploy:
  - Confirm Cloud Run revision is healthy and listening on container `PORT` (backend already maps `PORT` via config).
- Migration fails on existing DB:
  - If DB was previously managed by `prisma db push`, reset/wipe once then rerun deploy pipeline.
  - If reset is not possible, run baseline first (`npm run prisma:migrate:baseline:init`) before normal deploy flow.
