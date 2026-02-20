# Architecture - BabyAI MVP

## 1. 시스템 구성
- Client: Flutter 앱(iOS/Android)
- API: BFF + Domain API
- Data: PostgreSQL + Redis
- Storage: Object Storage + CDN
- AI:
  - STT 파이프라인
  - 이벤트 파서
  - RAG 질의응답
  - 리포트 생성기
- Voice Assistant:
  - iOS App Intents
  - Samsung Bixby Capsule/Endpoint

## 2. 도메인 바운디드 컨텍스트
- `identity`: 사용자/로그인/동의
- `household`: 가구/멤버/역할/권한
- `baby`: 아기 프로필
- `events`: 육아 이벤트 기록
- `ai`: 질의응답/리포트/페르소나/톤
- `photos`: 앨범/자산/공유 권한
- `billing`: 구독/플랜/게이팅
- `audit`: 감사로그

## 3. 핵심 데이터 모델(RDB)
### 3.1 주요 테이블
- `users(id, provider, provider_uid, phone, name, created_at)`
- `households(id, owner_user_id, created_at)`
- `household_members(id, household_id, user_id, role, status, created_at)`
- `babies(id, household_id, name, birth_date, sex, created_at)`
- `consents(id, user_id, consent_type, granted, granted_at)`
- `subscriptions(id, household_id, plan, status, renew_at)`
- `events(id, baby_id, type, start_time, end_time, value_json, metadata_json, status, source, created_by, created_at, updated_at)`
- `voice_clips(id, household_id, baby_id, audio_url, transcript, parsed_events_json, confidence_json, status, created_at)`
- `persona_profiles(id, user_id, persona_json, updated_at)`
- `ai_tone_profiles(id, user_id, tone, verbosity_level, safety_strictness, updated_at)`
- `reports(id, household_id, baby_id, period_type, period_start, period_end, metrics_json, summary_text, model_version, created_at)`
- `albums(id, household_id, baby_id, title, month_key, created_at)`
- `photo_assets(id, album_id, uploader_user_id, variants_json, visibility, downloadable, created_at)`
- `invites(id, household_id, token, role, expires_at, invited_by, created_at, used_at)`
- `audit_logs(id, household_id, actor_user_id, action, target_type, target_id, payload_json, created_at)`

### 3.2 인덱스
- `events(baby_id, start_time desc)`
- `events(baby_id, type, start_time desc)`
- `events(baby_id, status, start_time desc)`
- `events(baby_id, type, status, start_time desc)`
- `reports(household_id, baby_id, period_type, period_start)`
- `photo_assets(album_id, created_at desc)`
- `audit_logs(household_id, created_at desc)`

## 4. API 설계(MVP)
### 4.1 인증/온보딩
- `POST /auth/login`
- `POST /onboarding/parent`
- `POST /invites/accept`
- `POST /consents`

### 4.2 이벤트 기록/조회
- `POST /events/voice` (audio 업로드 + STT + 파싱)
- `POST /events/confirm` (1탭 확정)
- `POST /events/manual` (단건 완료 입력)
- `POST /events/start` (진행중 OPEN 입력)
- `PATCH /events/{event_id}/complete` (OPEN -> CLOSED)
- `PATCH /events/{event_id}/cancel` (OPEN -> CANCELED)
- `GET /events/open?baby_id`
- `GET /events/timeline?babyId&from&to`
- `GET /analytics/summary?babyId&period=today|7d`

### 4.3 AI 질의응답/리포트
- `POST /ai/query`
- `GET /ai/quick/today-summary?babyId`
- `GET /reports/daily?babyId&date`
- `GET /reports/weekly?babyId&weekStart`
- `PUT /settings/persona`
- `PUT /settings/ai-tone`

### 4.4 사진 공유/구독
- `POST /albums`
- `POST /photos/upload-url`
- `POST /photos/complete`
- `GET /albums/:id/photos`
- `PATCH /photos/:id/downloadable`
- `GET /subscription/me`
- `POST /subscription/checkout`

## 5. 권한/게이팅 규칙
- 기록/AI API는 `Owner|Parent` 기본 허용
- `Caregiver`는 이벤트 입력 범위 기반 제한
- `Family Viewer`는 사진 read만 허용(다운로드는 asset flag + role check)
- 구독 게이팅:
  - `Photo Share`: photos API 허용, ai API 차단
  - `AI Only`: ai API 허용, photos API 차단
  - `AI + Photo`: 둘 다 허용

## 6. AI 파이프라인
### 6.1 음성 기록
1. 앱 녹음 업로드
2. STT 수행
3. 이벤트 파싱(복수 이벤트)
4. 필드 confidence 계산
5. 확정 전 카드 반환
6. 사용자 확정 시 events 저장

### 6.2 질의응답
1. 질의 분류(조회/계산/요약/비교)
2. 집계 질의 실행
3. 근거 문장 생성(기준/기록 범위/데이터 부족)
4. AiToneProfile로 문체 변환
5. 가드레일 적용 후 응답

## 7. 다음 수유 ETA 규칙
- 입력: 최근 `N=5` 수유 이벤트(최소 2개)
- 텀: 인접 이벤트 시작시각 차이
- 옵션: 상하위 10% 절삭 평균
- 계산:
  - `mean_interval = average(intervals)`
  - `eta = last_feeding_time + mean_interval - now`
- 데이터 부족:
  - `최근 기록이 1회뿐이라 계산이 어렵습니다.`

## 8. Siri/Bixby 연동 방식
### iOS(App Intents)
- 인텐트 실행 시 서버 API 조회
- 결과를 `dialog` 문자열로 반환
- 사용자 톤 설정 반영

### Samsung(Bixby)
- 질문 -> 원격 endpoint -> result dialog
- 다이얼로그 템플릿에서 친근/격식 톤 분기

## 9. NFR/운영
- 질의응답 캐시(짧은 TTL)로 2~3초 체감 목표
- 미기록은 0으로 간주하지 않음
- 감사로그 의무 저장
- 의료 안내는 비진단 정책 강제
