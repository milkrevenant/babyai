# BabyAI

Baby care logging + AI summary monorepo.

## Repository Layout
- `apps/mobile`: Flutter client
- `apps/backend`: Go (Gin) API server
- `packages/schema/prisma/schema.prisma`: DB schema source of truth
- `docs/`: PRD, architecture, data contract, OpenAPI
- `integrations/siri`: Siri assistant contract
- `integrations/bixby`: Bixby assistant contract

## Current Auth Model (Important)
- Backend APIs are protected by `Authorization: Bearer <jwt>`.
- Backend does not yet expose a public login/token-issue API.
- Local dev uses either:
  - `--dart-define=API_BEARER_TOKEN=...`
  - onboarding token input field in the mobile app
- Production target is automatic sign-in/token issue flow (not manual token input).

## Quick Start (Windows / PowerShell)
1. Prepare PostgreSQL (pick one)

Option A: local PostgreSQL service
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

2. Start backend
```powershell
cd C:\Users\milkrevenant\Documents\code\babyai\apps\backend
Copy-Item .env.example .env
# set DATABASE_URL=postgres://babyai:babyai@localhost:5432/babyai
# set JWT_SECRET to a real random string
# set AUTH_AUTOCREATE_USER=true for first local bootstrap only
go run ./cmd/api
```

Default local backend port in this repo is `18000` (`APP_PORT=18000` in `.env`).

3. Prepare schema (new terminal)
```powershell
cd C:\Users\milkrevenant\Documents\code\babyai
npm install
$env:DATABASE_URL="postgres://babyai:babyai@localhost:5432/babyai"
npm run prisma:validate
npm run prisma:generate
npm run prisma:push
```

4. Run mobile
```powershell
cd C:\Users\milkrevenant\Documents\code\babyai\apps\mobile
flutter pub get
flutter run -d windows --debug `
  --dart-define=API_BASE_URL=http://127.0.0.1:18000 `
  --dart-define=API_BEARER_TOKEN=<jwt-token>
```

Android emulator example:
```powershell
flutter run -d emulator-5554 --debug `
  --dart-define=API_BASE_URL=http://10.0.2.2:18000 `
  --dart-define=API_BEARER_TOKEN=<jwt-token>
```

5. Complete onboarding in app
- fill child profile
- agree to 3 required consents
- press `Save & Start` (`등록 후 시작`)

## References
- Backend setup: `apps/backend/README.md`
- Mobile setup: `apps/mobile/README.md`
- Gemini/Assistant roadmap: `docs/gemini-babyai-plan.md`

## Gemini/Assistant Notes (Current)
- Intent-based record flow is integrated on Android (`OPEN_APP_FEATURE` + deep link bridge).
- DB write must be confirmed by backend `POST /api/v1/events/manual`; chat text alone is not a write guarantee.
- For production release, keep record-intent parsing and fallback policy aligned with `docs/gemini-babyai-plan.md`.
