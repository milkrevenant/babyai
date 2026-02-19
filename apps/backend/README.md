# Backend (Go + Gin)

## Run (Windows / PowerShell)
```powershell
cd C:\Users\milkrevenant\Documents\code\babyai\apps\backend
Copy-Item .env.example .env
notepad .env
go run ./cmd/api
```

Server default: `http://127.0.0.1:8000` (`/health`).

## PostgreSQL Setup
You need a running PostgreSQL instance before starting backend.

Option A: local PostgreSQL
```sql
-- run in psql as postgres superuser
CREATE USER babyai WITH PASSWORD 'babyai';
ALTER USER babyai CREATEDB;
CREATE DATABASE babyai OWNER babyai;
```

Option B: Docker
```powershell
docker run --name babyai-postgres `
  -e POSTGRES_USER=babyai `
  -e POSTGRES_PASSWORD=babyai `
  -e POSTGRES_DB=babyai `
  -p 5432:5432 -d postgres:16
```

Default connection string used in examples:
`postgres://babyai:babyai@localhost:5432/babyai`

After DB is up, sync schema from repo root:
```powershell
cd C:\Users\milkrevenant\Documents\code\babyai
npm install
$env:DATABASE_URL="postgres://babyai:babyai@localhost:5432/babyai"
npm run prisma:validate
npm run prisma:generate
npm run prisma:push
```

## Required Environment
Set in `.env`:
- `DATABASE_URL`
- `JWT_SECRET` (required)

Optional:
- `JWT_AUDIENCE`
- `JWT_ISSUER`
- `AUTH_AUTOCREATE_USER` (default `false`)
- `LOCAL_FORCE_SUBSCRIPTION_PLAN` (local only: `AI_ONLY` | `AI_PHOTO` | `PHOTO_SHARE`)
- `ONBOARDING_SEED_DUMMY_DATA` (default `false`, local only)
- `CORS_ALLOW_ORIGINS`
- `OPENAI_MODEL` (default `gpt-5-mini`)
- `OPENAI_BASE_URL` (default `https://api.openai.com/v1`)
- `AI_MAX_OUTPUT_TOKENS` (default `600`)
- `AI_TIMEOUT_SECONDS` (default `60`)

Required for real AI routes in non-test env:
- `OPENAI_API_KEY`

Example:
```env
APP_ENV=local
APP_NAME=BabyAI API
API_PREFIX=/api/v1
APP_PORT=8000
DATABASE_URL=postgres://babyai:babyai@localhost:5432/babyai
JWT_SECRET=replace-with-long-random-secret
JWT_ALGORITHM=HS256
JWT_AUDIENCE=
JWT_ISSUER=
AUTH_AUTOCREATE_USER=false
LOCAL_FORCE_SUBSCRIPTION_PLAN=
ONBOARDING_SEED_DUMMY_DATA=false
CORS_ALLOW_ORIGINS=http://localhost:5173,http://127.0.0.1:5173,http://localhost:3000
OPENAI_API_KEY=<your-openai-api-key>
OPENAI_MODEL=gpt-5-mini
OPENAI_BASE_URL=https://api.openai.com/v1
AI_MAX_OUTPUT_TOKENS=600
AI_TIMEOUT_SECONDS=60
```

## AI Credit Billing
- Credit charge: `ceil(total_tokens / 1000)` per AI response.
- Applied routes: `POST /api/v1/chat/query`, `POST /api/v1/ai/query`.
- Wallet unit: `User`.
- Grace policy: up to `3` times per UTC day when balance is insufficient.
- Monthly lazy grant on AI call:
  - `AI_ONLY = 300`
  - `AI_PHOTO = 500`
  - `PHOTO_SHARE = 0`
- Exhausted response: HTTP `402` with `detail=Insufficient AI credits`.

## Auth Behavior
All `/api/v1/*` routes require:
```http
Authorization: Bearer <jwt>
```

JWT expectations:
- algorithm: `HS256`
- signature key: `JWT_SECRET`
- required claim: `sub` (UUID-like user id)
- optional claims used for first provisioning:
  - `name`
  - `provider` (`apple` | `google` | `phone`)
  - `provider_uid`
  - `phone`

If `AUTH_AUTOCREATE_USER=false`, unknown `sub` is rejected with `User not found`.

## Dev Bootstrap Token (No Login API Yet)
This backend does not provide a public token issue endpoint yet.
For local development, mint a dev JWT using the same `JWT_SECRET`.

PowerShell example:
```powershell
$secret = "YOUR_JWT_SECRET_FROM_.env"
$sub = [guid]::NewGuid().ToString()

function B64Url([byte[]]$bytes) {
  [Convert]::ToBase64String($bytes).TrimEnd("=").Replace("+","-").Replace("/","_")
}

$header = @{ alg="HS256"; typ="JWT" } | ConvertTo-Json -Compress
$payload = @{
  sub = $sub
  provider = "google"
  name = "Dev User"
} | ConvertTo-Json -Compress

$h = B64Url([Text.Encoding]::UTF8.GetBytes($header))
$p = B64Url([Text.Encoding]::UTF8.GetBytes($payload))
$unsigned = "$h.$p"

$hmac = [System.Security.Cryptography.HMACSHA256]::new([Text.Encoding]::UTF8.GetBytes($secret))
$sig = B64Url($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($unsigned)))
$token = "$unsigned.$sig"

"SUB=$sub"
"TOKEN=$token"
```

Then pass `TOKEN` to mobile via `--dart-define=API_BEARER_TOKEN=...` or paste it in onboarding token input.

macOS/Linux shortcut script:
```bash
cd /Users/stillclie_mac/Documents/code/babyai/apps/backend
./scripts/gen_dev_jwt.sh
# optional args: ./scripts/gen_dev_jwt.sh <sub-uuid> "Dev User" google
```

Local-only quick endpoint (enabled only when `APP_ENV=local`):
```bash
curl -X POST http://127.0.0.1:8000/dev/local-token
```
Response includes `token` and `sub`.  
`Child Registration` in mobile onboarding also tries this endpoint automatically when token input is empty.

## Build
```powershell
cd C:\Users\milkrevenant\Documents\code\babyai\apps\backend
go mod tidy
go build ./...
```

## Tests
Unit tests always run.
API integration tests require `TEST_DATABASE_URL`.

PowerShell example:
```powershell
$env:TEST_DATABASE_URL = "postgres://babyai:babyai@localhost:5432/babyai_test"
$env:DATABASE_URL = $env:TEST_DATABASE_URL
cd C:\Users\milkrevenant\Documents\code\babyai
npm run prisma:push
cd apps\backend
go test ./internal/server -count=1
go test ./... -count=1
```

## Implemented DB-backed Endpoints
- `POST /api/v1/onboarding/parent`
- `POST /api/v1/events/voice`
- `POST /api/v1/events/confirm`
- `POST /api/v1/events/manual`
- `POST /api/v1/events/start`
- `PATCH /api/v1/events/{event_id}/complete`
- `PATCH /api/v1/events/{event_id}/cancel`
- `GET /api/v1/events/open`
- `GET /api/v1/settings/me`
- `PATCH /api/v1/settings/me`
- `GET /api/v1/babies/profile`
- `PATCH /api/v1/babies/profile`
- `GET /api/v1/quick/last-feeding`
- `GET /api/v1/quick/recent-sleep`
- `GET /api/v1/quick/last-diaper`
- `GET /api/v1/quick/last-medication`
- `GET /api/v1/quick/last-poo-time`
- `GET /api/v1/quick/next-feeding-eta`
- `GET /api/v1/quick/today-summary`
- `GET /api/v1/quick/landing-snapshot`
- `POST /api/v1/ai/query`
- `POST /api/v1/chat/sessions`
- `POST /api/v1/chat/sessions/:session_id/messages`
- `GET /api/v1/chat/sessions/:session_id/messages`
- `POST /api/v1/chat/query`
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

Quick snapshot endpoints support optional timezone conversion:
- query param: `tz_offset` (example: `+09:00`, `-05:00`)
