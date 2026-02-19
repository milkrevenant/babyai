# Railway Deployment (Backend API)

This project deploys the Go backend from `apps/backend` using Docker and runs Prisma schema sync during Railway pre-deploy.

## Official references
- Railway deployment docs: https://docs.railway.com/guides/deploy
- Railway config as code (`railway.json`): https://docs.railway.com/reference/config-as-code
- Railway Dockerfile builder: https://docs.railway.com/reference/build-configuration

## What is already prepared in this repo
- `railway.json` (repo root)
- `apps/backend/Dockerfile`
- Backend reads `PORT` automatically (Railway runtime env)

`railway.json` uses:
- Dockerfile build: `apps/backend/Dockerfile`
- Pre-deploy DB sync: `npm run prisma:push`
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
   - `AUTH_AUTOCREATE_USER=false`
   - `OPENAI_API_KEY` (required for AI endpoints)
   - optional: `JWT_AUDIENCE`, `JWT_ISSUER`, `CORS_ALLOW_ORIGINS`
6. Deploy.

During each deploy, Railway runs `npm run prisma:push` first, then starts the API container.

## Verify after deploy
- Health: `GET /health`
- Auth-protected API: `GET /api/v1/settings/me` with Bearer JWT

## Mobile app production endpoint
Use deployed API URL in mobile build defines:
- `API_BASE_URL=https://<your-railway-domain>`
