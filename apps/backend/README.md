# Backend (Go + Gin)

## Run
```bash
cd apps/backend
copy .env.example .env
"C:\Program Files\Go\bin\go.exe" run ./cmd/api
```

Server defaults to `http://localhost:8000`.

## Environment
Set these values in `.env`:
- `DATABASE_URL`
- `JWT_SECRET` (required; server fails fast when missing/insecure)
- optional: `JWT_AUDIENCE`, `JWT_ISSUER`
- optional: `CORS_ALLOW_ORIGINS` (comma-separated)

Example:
```env
APP_ENV=local
APP_NAME=BabyLog AI API
API_PREFIX=/api/v1
APP_PORT=8000
DATABASE_URL=postgres://babylog:babylog@localhost:5432/babylog
JWT_SECRET=replace-with-long-random-secret
JWT_ALGORITHM=HS256
JWT_AUDIENCE=
JWT_ISSUER=
AUTH_AUTOCREATE_USER=false
CORS_ALLOW_ORIGINS=http://localhost:5173,http://127.0.0.1:5173,http://localhost:3000
```

If you use Prisma Dev DB instead of local PostgreSQL:
```bash
cd C:/Users/milkrevenant/Documents/code/babylog-ai
npx prisma dev start babylog
npx prisma dev ls
```
Use the `TCP` URL from `prisma dev ls` output as `DATABASE_URL`.

## Build
```bash
cd apps/backend
"C:\Program Files\Go\bin\go.exe" mod tidy
"C:\Program Files\Go\bin\go.exe" build ./...
```

## Auth
Most endpoints require:
```http
Authorization: Bearer <jwt>
```

Required JWT claim:
- `sub` (user id UUID)

Optional claims for first-login auto-provisioning:
- `name`
- `provider` (`apple` | `google` | `phone`)
- `provider_uid`
- `phone`

With `AUTH_AUTOCREATE_USER=false` (default), unknown token subjects are rejected.
Set it to `true` only in controlled bootstrap/dev flows.

## Implemented DB-backed endpoints
- `POST /api/v1/onboarding/parent`
- `POST /api/v1/events/voice`
- `POST /api/v1/events/confirm`
- `GET /api/v1/quick/last-poo-time`
- `GET /api/v1/quick/next-feeding-eta`
- `GET /api/v1/quick/today-summary`
- `POST /api/v1/ai/query`
- `GET /api/v1/reports/daily`
- `GET /api/v1/reports/weekly`
- `POST /api/v1/photos/upload-url`
- `POST /api/v1/photos/complete`
- `GET /api/v1/subscription/me`
- `POST /api/v1/subscription/checkout`
- `POST /api/v1/assistants/siri/GetLastPooTime`
- `POST /api/v1/assistants/siri/GetNextFeedingEta`
- `POST /api/v1/assistants/siri/GetTodaySummary`
- `POST /api/v1/assistants/siri/{intent_name}`
- `POST /api/v1/assistants/bixby/query`
