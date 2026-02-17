# Siri App Intents Integration

## Implemented Intents (Backend Side)
- `GetLastPooTimeIntent`
- `GetNextFeedingEtaIntent`
- `GetTodaySummaryIntent`
- `StartRecordFlowIntent` (planned flow trigger)

## Backend Contract
- `POST /api/v1/assistants/siri/GetLastPooTime`
- `POST /api/v1/assistants/siri/GetNextFeedingEta`
- `POST /api/v1/assistants/siri/GetTodaySummary`
- `POST /api/v1/assistants/siri/{intent_name}`

All endpoints require:
```http
Authorization: Bearer <jwt>
```

Request body:
```json
{
  "baby_id": "baby_123",
  "tone": "friendly"
}
```

Response body:
```json
{
  "dialog": "Next feeding in about 35 minutes.",
  "reference": "Based on recent feeding pattern"
}
```

## Notes
- Siri integration currently depends on the same backend auth as the mobile app.
- For local testing, use the same dev JWT flow documented in `apps/backend/README.md`.
