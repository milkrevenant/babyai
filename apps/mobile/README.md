# Mobile (Flutter)

Flutter app screens are wired to real backend APIs via `Dio`.

## Prerequisites
- Flutter SDK
- Xcode `16+` (for iOS 18.0+ builds on macOS)
- Running backend (`apps/backend`) on `http://127.0.0.1:8000` or your custom base URL
- Valid JWT token for backend auth
- Platform requirements:
  - Android: `14+` (min API 34), target API `35`, `64-bit only` (`arm64-v8a`, `x86_64`)
  - iOS: `18.0+`

## Install / Run
```bash
cd apps/mobile
flutter create .
flutter pub get
flutter run \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000 \
  --dart-define=API_BEARER_TOKEN=<jwt-token> \
  --dart-define=BABY_ID=<baby-id> \
  --dart-define=HOUSEHOLD_ID=<household-id> \
  --dart-define=ALBUM_ID=<album-id>
```

## Integrated API flows
- `Record` tab:
  - `POST /api/v1/events/voice`
  - `POST /api/v1/events/confirm`
- `AI` tab:
  - `GET /api/v1/quick/last-poo-time`
  - `GET /api/v1/quick/next-feeding-eta`
  - `GET /api/v1/quick/today-summary`
  - `POST /api/v1/ai/query`
- `Report` tab:
  - `GET /api/v1/reports/daily`
  - `GET /api/v1/reports/weekly`
- `Photos` tab:
  - `POST /api/v1/photos/upload-url`
  - `POST /api/v1/photos/complete`

All tabs include loading and error handling for API requests.
