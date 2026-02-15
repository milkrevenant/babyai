# Siri App Intents Integration

## 제공 인텐트
- `GetLastPooTimeIntent`
- `GetNextFeedingEtaIntent`
- `GetTodaySummaryIntent`
- `StartRecordFlowIntent`

## 백엔드 계약
- `POST /api/v1/assistants/siri/GetLastPooTime`
- `POST /api/v1/assistants/siri/GetNextFeedingEta`
- `POST /api/v1/assistants/siri/GetTodaySummary`

요청 바디
```json
{
  "baby_id": "baby_123",
  "tone": "friendly"
}
```

응답 바디
```json
{
  "dialog": "다음 수유까지 35분 남았어.",
  "reference": "최근 5회 평균 텀 기준"
}
```

