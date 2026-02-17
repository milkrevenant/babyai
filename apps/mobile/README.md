# Mobile (Flutter)

Flutter app wired to backend APIs via `Dio`.

## Prerequisites
- Flutter SDK
- Running backend on `http://127.0.0.1:18000`
- Valid backend JWT token (HS256, signed with backend `JWT_SECRET`)
- Platform requirements:
  - Android `14+` (min API 34), target API `35`
  - iOS `18.0+` (Xcode `16+`)

## Local Setup
```powershell
cd C:\Users\milkrevenant\Documents\code\babyai\apps\mobile
flutter pub get
```

## Run (Windows)
```powershell
flutter run -d windows --debug `
  --dart-define=API_BASE_URL=http://127.0.0.1:18000 `
  --dart-define=API_BEARER_TOKEN=<jwt-token>
```

Optional defines:
```text
--dart-define=BABY_ID=<baby-id>
--dart-define=HOUSEHOLD_ID=<household-id>
--dart-define=ALBUM_ID=<album-id>
```

`BABY_ID/HOUSEHOLD_ID/ALBUM_ID` are optional for first onboarding.

## Token Input Rules (Current)
- On onboarding `Save & Start`, token is required.
- Token can come from:
  - `--dart-define=API_BEARER_TOKEN`
  - onboarding token text input
- If missing, app blocks submission before API call with an explicit message.

## Android Studio
`Run/Debug Configurations` -> `Additional run args`:
```text
--dart-define=API_BASE_URL=http://10.0.2.2:18000 --dart-define=API_BEARER_TOKEN=<jwt-token>
```

## Gemini / Assistant (Current)
- Android assistant deep-link integration is wired through:
  - `android/app/src/main/res/xml/shortcuts.xml`
  - `android/app/src/main/kotlin/com/example/babyai/MainActivity.kt`
  - `lib/core/assistant/assistant_intent_bridge.dart`
- Record success is valid only when backend write endpoint succeeds:
  - `POST /api/v1/events/manual`
- If command parsing fails, treat it as non-write and guide user to retry with explicit units (e.g. `120ml`, `15 min`).

## Integrated API Flows
- Home/Record:
  - `GET /api/v1/quick/landing-snapshot`
  - `POST /api/v1/events/voice`
  - `POST /api/v1/events/confirm`
- Chat:
  - `GET /api/v1/quick/last-poo-time`
  - `GET /api/v1/quick/next-feeding-eta`
  - `GET /api/v1/quick/today-summary`
  - `POST /api/v1/ai/query`
- Statistics:
  - `GET /api/v1/reports/daily`
  - `GET /api/v1/reports/weekly`
- Photos:
  - `POST /api/v1/photos/upload-url`
  - `POST /api/v1/photos/complete`

## Troubleshooting
- `Bearer token required`: token not provided
- `Invalid bearer token`: wrong signature/secret mismatch
- `User not found`: backend has `AUTH_AUTOCREATE_USER=false` and `sub` is unknown
- connection error: backend not running or wrong `API_BASE_URL`
