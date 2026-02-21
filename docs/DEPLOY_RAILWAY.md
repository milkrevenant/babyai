# Railway Deployment (Backend API)

This project deploys the Go backend from `apps/backend` using Docker and applies Prisma migrations during Railway pre-deploy.

## Official references
- Railway deployment docs: https://docs.railway.com/guides/deploy
- Railway config as code (`railway.json`): https://docs.railway.com/reference/config-as-code
- Railway Dockerfile builder: https://docs.railway.com/reference/build-configuration

## What is already prepared in this repo
- `railway.json` (repo root)
- `Dockerfile` (repo root, Railway build entrypoint)
- `apps/backend/Dockerfile` (legacy/local reference)
- Backend reads `PORT` automatically (Railway runtime env)

`railway.json` uses:
- Dockerfile build: `Dockerfile`
- Pre-deploy DB migration: `npm run prisma:migrate:deploy`
- Health check: `/health`

## Deploy steps
1. Create a new Railway project.
2. Add a PostgreSQL service.
3. Add a GitHub service connected to this repository (same project).
4. Confirm Railway detects `railway.json` at repo root.
5. Set environment variables on backend service:
   - `DATABASE_URL` (from Railway PostgreSQL)
   - `JWT_SECRET` (16+ chars)
   - `APP_ENV=production`
   - `AUTH_AUTOCREATE_USER=true` (recommended for first onboarding path)
   - `AUTH_ACCEPT_GOOGLE_ID_TOKEN=true`
   - `GOOGLE_OAUTH_CLIENT_IDS=<google-web-client-id>` (comma-separated if multiple)
   - `OPENAI_API_KEY` (required for AI endpoints)
   - optional (QA build without Google Sign-In):
     - `TEST_LOGIN_ENABLED=true`
     - `TEST_LOGIN_EMAIL=<qa-email>`
     - `TEST_LOGIN_PASSWORD=<qa-password>`
     - `TEST_LOGIN_NAME=QA Tester`
   - optional:
     - `JWT_AUDIENCE`, `JWT_ISSUER`, `CORS_ALLOW_ORIGINS`
     - `ENABLE_PHOTO_PLACEHOLDER_UPLOAD=false`
     - `ENABLE_VOICE_DUMMY_PARSE=false`
6. Deploy.

During each deploy, Railway runs `npm run prisma:migrate:deploy` first, then starts the API container.

## Migration transition note
If your existing Railway database was historically managed by `prisma db push` (no migration history table),
`prisma:migrate:deploy` can fail on first switch. Recommended path for this project is:
- reset/wipe the DB once, then redeploy.

If reset is not possible, baseline the DB before switching fully to migration deploy.

Example baseline command (use your latest migration folder name):

```bash
DATABASE_URL="$DATABASE_URL" \
  npx prisma migrate resolve \
  --applied <migration_folder_name> \
  --schema packages/schema/prisma/schema.prisma
```

For this repository's initial migration, you can also run:

```bash
DATABASE_URL="$DATABASE_URL" npm run prisma:migrate:baseline:init
```

## Verify after deploy
- Health: `GET /health`
- Auth-protected API: `GET /api/v1/settings/me` with Bearer JWT

## Mobile app production endpoint
Use deployed API URL in mobile build defines:
- `API_BASE_URL=https://<your-railway-domain>`
- `GOOGLE_SERVER_CLIENT_ID=<google-web-client-id>`

For QA APK (JWT not embedded in app), do **not** set `API_BEARER_TOKEN` at build time.
Users sign in with test email/password via `POST /auth/test-login`.
