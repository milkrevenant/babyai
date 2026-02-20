# Bixby Dialog Templates

## Friendly
- Last poo: `오늘은 {time}에 쌌어.`
- Next feeding ETA: `다음 수유까지 {eta_min}분 남았어.`
- Today summary: `오늘 요약 읽어줄게. {summary}`

## Formal
- Last poo: `금일 마지막 대변 기록 시각은 {time}입니다.`
- Next feeding ETA: `다음 수유 권장 시각까지 {eta_min}분 남았습니다.`
- Today summary: `금일 요약 정보를 안내드립니다. {summary}`

## Endpoint Payload
```json
{
  "capsule_action": "GetNextFeedingEta",
  "baby_id": "baby_123",
  "tone": "formal"
}
```

## Endpoint Response
```json
{
  "answer": "다음 수유 권장 시각까지 35분 남았습니다.",
  "resultMoment": true
}
```

