# Data Contract - BabyAI MVP

## 1. 엔티티와 필드

### User
- `id` (uuid, pk)
- `provider` (enum: apple|google|phone)
- `provider_uid` (string, nullable)
- `phone` (string, nullable)
- `name` (string)
- `created_at` (timestamp)

제약
- `provider + provider_uid` unique(소셜 로그인 시)
- `phone` unique(휴대폰 로그인 시)

### Household
- `id` (uuid, pk)
- `owner_user_id` (uuid, fk->User)
- `created_at` (timestamp)

### HouseholdMember
- `id` (uuid, pk)
- `household_id` (uuid, fk->Household)
- `user_id` (uuid, fk->User)
- `role` (enum: OWNER|PARENT|FAMILY_VIEWER|CAREGIVER)
- `status` (enum: ACTIVE|INVITED|REMOVED)
- `created_at` (timestamp)

제약
- `household_id + user_id` unique

### Baby
- `id` (uuid, pk)
- `household_id` (uuid, fk->Household)
- `name` (string)
- `birth_date` (date, required)
- `created_at` (timestamp)

### Event
- `id` (uuid, pk)
- `baby_id` (uuid, fk->Baby)
- `type` (enum: FORMULA|BREASTFEED|SLEEP|PEE|POO|GROWTH|MEMO|SYMPTOM|MEDICATION)
- `start_time` (timestamp)
- `end_time` (timestamp, nullable)
- `value_json` (jsonb)
- `metadata_json` (jsonb)
- `source` (enum: VOICE|TEXT|MANUAL|IMPORT)
- `created_by` (uuid, fk->User)
- `created_at` (timestamp)

### VoiceClip
- `id` (uuid, pk)
- `household_id` (uuid, fk->Household)
- `baby_id` (uuid, fk->Baby)
- `audio_url` (string)
- `transcript` (text)
- `parsed_events_json` (jsonb)
- `confidence_json` (jsonb)
- `status` (enum: PARSED|CONFIRMED|FAILED)
- `created_at` (timestamp)

### Report
- `id` (uuid, pk)
- `household_id` (uuid, fk->Household)
- `baby_id` (uuid, fk->Baby)
- `period_type` (enum: DAILY|WEEKLY)
- `period_start` (date)
- `period_end` (date)
- `metrics_json` (jsonb)
- `summary_text` (text)
- `model_version` (string)
- `created_at` (timestamp)

### PersonaProfile / AiToneProfile
- `persona_profiles(user_id, persona_json, updated_at)`
- `ai_tone_profiles(user_id, tone_enum, verbosity_level, safety_strictness, updated_at)`

### Photo/Invite/Subscription
- `albums`, `photo_assets`, `invites`, `subscriptions`, `consents`, `audit_logs`
- 세부 필드는 `docs/ARCHITECTURE.md` 기준

## 2. 사용자 플로우

### Parent(Owner/Parent) 가입
1. 로그인
2. Household 생성
3. Baby 최소 1명 생성(출생일 필수)
4. 필수 동의 저장
5. 홈 진입

### Family Viewer 초대 가입
1. 초대 링크/QR 진입(토큰)
2. 간편 로그인
3. 최소 동의
4. 즉시 사진 보기

### 음성 기록
1. 녹음 업로드
2. STT + 이벤트 파싱
3. 카드 검수
4. 1탭 확정 저장
5. 차트/요약 반영

### 대화형 조회
1. 질문 입력(앱/음성)
2. 질의 타입 분류
3. 데이터 집계
4. 톤 반영 답변
5. 근거 기준 문구 포함

## 3. MVP API Contract

### 인증/온보딩
- `POST /auth/login`
- `POST /onboarding/parent`
- `POST /invites/accept`
- `POST /consents`

### 기록/분석
- `POST /events/voice`
- `POST /events/confirm`
- `GET /events/timeline`
- `GET /analytics/summary`

### AI
- `POST /ai/query`
- `GET /ai/quick/today-summary`
- `GET /reports/daily`
- `GET /reports/weekly`
- `PUT /settings/persona`
- `PUT /settings/ai-tone`

### 사진/구독
- `POST /albums`
- `POST /photos/upload-url`
- `POST /photos/complete`
- `GET /albums/:id/photos`
- `PATCH /photos/:id/downloadable`
- `GET /subscription/me`
- `POST /subscription/checkout`

