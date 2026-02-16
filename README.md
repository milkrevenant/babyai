# BabyAI

Baby care logging + AI summary MVP monorepo.

## Monorepo Layout
- `apps/mobile`: Flutter app
- `apps/backend`: Go (Gin) API server
- `packages/schema/prisma/schema.prisma`: Prisma DB schema
- `docs/PRD.md`: product requirements
- `docs/ARCHITECTURE.md`: architecture
- `docs/DATA_CONTRACT.md`: data and API contract
- `docs/api/openapi.yaml`: OpenAPI spec
- `integrations/siri`: Siri App Intents contract
- `integrations/bixby`: Bixby capsule contract

## Backend (Go)
```bash
cd apps/backend
copy .env.example .env
"C:\Program Files\Go\bin\go.exe" run ./cmd/api
```

## Prisma Schema
```bash
cd C:/Users/milkrevenant/Documents/code/babyai
npm install
$env:DATABASE_URL="postgres://babyai:babyai@localhost:5432/babyai"
npm run prisma:validate
npm run prisma:generate
npm run prisma:push
```

## Notes
- Database schema source of truth is Prisma (`packages/schema/prisma/schema.prisma`).
- Mobile app calls backend APIs in `apps/mobile/lib/core/network/babyai_api.dart`.
