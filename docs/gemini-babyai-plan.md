# BabyAI x Gemini 연동 및 `app.dart` 리팩토링 계획

## 1. 목표
- Gemini/Assistant 음성 명령으로 BabyAI 기록이 실제 DB까지 반영되도록 안정화
- "오늘 마지막 수유 시간/양", "최근 잠" 같은 조회형 질문을 Gemini 경유로 처리
- `app.dart`를 책임 분리해 유지보수 가능한 구조로 리팩토링
- 최종적으로 E2E(명령 -> 앱/서버 -> DB -> UI 반영) 검증 가능 상태 확보

## 2. 핵심 요구사항(정리)
- 기록형: 분유, 모유, 기저귀(소변/대변), 투약, 수면 시작/종료
- 조회형: 마지막 수유 시간, 마지막 수유량, 최근 잠 시작/지속시간 등
- 실패 시: "기록 완료"처럼 오해되는 응답 금지, 명확한 실패 메시지 표시

## 3. 전제/제약
- Android App Actions는 BII/로케일/매칭 품질 영향을 받음
- `OPEN_APP_FEATURE`, `GET_THING` 중심으로 설계해야 안정적
- 앱 미설치/권한 미허용/토큰 만료 시 graceful fallback 필요
- 운영 배포 기준으로 Play Console 심사/테스트 경로 고려 필요

## 4. 아키텍처 계획

### 4.1 Mobile (`app.dart`) 리팩토링
현재 `app.dart`가 라우팅/어시스턴트 처리/세션/UI 상태를 함께 다루고 있어 분리 필요.

분리 대상:
1. `AssistantIntentOrchestrator`
- 인텐트 payload 수신
- 기록형/조회형/채팅형 의도 분기
- 실패/미해석 처리 정책 중앙화

2. `AssistantCommandParser`
- 텍스트 -> 도메인 명령(`RecordFormula(ml)`, `GetLastFeeding`, `SleepStart` 등)
- 한국어/영어 동시 처리
- 숫자 단위(ml, 분, 시간) 파싱

3. `HomeNavigationCoordinator`
- 하단 탭/상단 컨트롤/사이드바 라우팅만 담당

4. `RecordCommandExecutor`
- 파싱된 기록 명령을 `createManualEvent`로 실행
- 성공/실패 스낵바 및 재조회 트리거

### 4.2 Backend API 확장
기존 `/quick/landing-snapshot` 외에 조회형 명령용 경량 endpoint 추가:
- `GET /api/v1/quick/last-feeding`
- `GET /api/v1/quick/recent-sleep`
- `GET /api/v1/quick/last-diaper`
- `GET /api/v1/quick/last-medication`

응답은 Gemini 프롬프트 친화적으로 고정 필드 제공:
- timestamp(UTC), local_time, amount_ml, duration_min, type, confidence

### 4.3 Gemini 질의 흐름
1. 사용자 음성 명령
2. Assistant/App Actions -> BabyAI deep link/intent
3. Mobile Parser가 기록형/조회형 분기
4. 기록형: backend write -> 성공시 UI/스냅샷 갱신
5. 조회형: backend read -> 요약 응답 렌더링(채팅/요약 카드)

## 5. 단계별 실행 계획

### Phase A: 안정화(기록형 우선)
- 기록형 명령을 chat fallback으로 보내지 않도록 정책 고정
- 기록 성공은 backend `events/manual` 성공 응답 기준으로만 표시
- 실패 시 원인별 메시지(파싱 실패/권한/토큰/네트워크)

완료 기준:
- 분유/모유/기저귀/투약/수면 시작·종료 전부 DB 반영 확인

### Phase B: 조회형 명령 구현
- "마지막 수유 시간/양", "최근 잠" 질문 처리
- 응답 카드 + 채팅 텍스트 동시 제공
- 다국어(ko/en/es) 표현 템플릿 정리

완료 기준:
- 조회 명령 5종 이상에서 backend 값과 UI 표시 일치

### Phase C: 배포 준비
- 앱/서버 통합 로깅 정리(명령 ID, 파싱 결과, API latency)
- 개인 정보/약관/동의 흐름 점검
- Play 배포 체크리스트 및 테스트 시나리오 정리

## 6. E2E 테스트 계획

시나리오 세트:
1. `분유 120ml 기록` -> DB 이벤트 생성 -> 홈 카드 반영
2. `모유 15분 기록` -> duration 저장 확인
3. `기저귀 대변 기록` / `기저귀 소변 기록` 타입 분기 확인
4. `수면 시작` 후 `수면 종료` -> duration 계산 확인
5. `마지막 수유 시간 알려줘` -> 조회 응답 정확성 확인
6. 토큰 만료/네트워크 단절 시 실패 메시지 검증

검증 방식:
- 모바일 UI 검증 + backend access log + DB row 검증
- 실패 케이스(401/403/timeout)도 필수 포함

## 7. 스킬 기반 실행 가이드
요청하신 대로 다음 순서로 스킬 사용 권장.

1. `app-dev`
- 전체 작업 오케스트레이션(계획 -> 구현 -> 검증)

2. `backend-patterns`
- quick 조회 API/핸들러 구조 정리, 에러 모델 표준화

3. `frontend-patterns`
- `app.dart` 분리, 상태/라우팅 책임 경계 설정

4. `security-reviewer`
- 토큰 처리, 로그 민감정보, 동의/개인정보 노출 점검

5. `test-agent`
- analyze/build/integration/E2E 시나리오 검증

권장 요청 템플릿:
- "`app-dev + backend-patterns + frontend-patterns`로 Phase A 구현"
- "`test-agent`로 기록형 E2E만 먼저 검증"
- "`security-reviewer`로 릴리즈 전 점검"

## 8. 산출물(예정)
- `docs/assistant-command-spec.md` (명령 문법/파싱 규칙)
- `docs/app-actions-mapping.md` (BII/shortcut/deeplink 매핑)
- `docs/e2e-test-matrix.md` (케이스별 기대결과)
- 리팩토링된 코드 모듈(`orchestrator/parser/executor`)

## 9. 참고 문서(공식)
- Android App Actions overview: https://developer.android.com/guide/app-actions/overview
- Build App Actions: https://developer.android.com/guide/app-actions/get-started
- BII reference: https://developer.android.com/reference/app-actions/built-in-intents
- BII index (locale/feature 확인): https://developer.android.com/reference/app-actions/built-in-intents/bii-index
- Google App Actions docs hub: https://developers.google.com/actions/app/
