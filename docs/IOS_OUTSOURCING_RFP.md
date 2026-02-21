# BabyAI iOS 외주 개발 RFP/SOW (실행본)

- 문서 버전: v1.0
- 작성일: 2026-02-21
- 기준 코드: 현재 저장소 `main` 워크트리 기준
- 필수 선행 문서: `docs/IOS_NATIVE_CONVERSION_HANDOFF.md`

## 1. 목적

Flutter 앱 BabyAI를 iOS 네이티브(Swift)로 전환하기 위한 외주 개발 범위, 산출물, 검수 기준을 명확히 정의한다.  
본 문서는 견적/일정 협의와 계약서(SOW) 부속 문서로 사용한다.

## 2. 프로젝트 배경(현재 상태)

- 현재 모바일 앱: Flutter (`apps/mobile`)
- 백엔드: Go/Gin (`apps/backend`)
- DB: PostgreSQL + Prisma 스키마 (`packages/schema/prisma/schema.prisma`)
- iOS 최소 버전: 18.0 (`apps/mobile/ios/Runner.xcodeproj/project.pbxproj`)

핵심 기능:

1. 육아 기록(수유/수면/기저귀/투약/메모)
2. AI 채팅(세션/메시지/질의)
3. 리포트(일/주/월)
4. 설정/구독/CSV 내보내기
5. Assistant 연동(딥링크 + App Intents)

## 3. 외주 개발 범위(In Scope)

### 3.1 앱 구조

1. 탭/화면 구조를 기존 동작 기준으로 이식
2. 온보딩 게이트(아기 프로필 필수) 이식
3. 세션 복원/로그인 상태 복원 이식

### 3.2 도메인 기능

1. 기록 기능
2. 이벤트 lifecycle(`createClosed`, `startOnly`, `completeOpen`)
3. 채팅 세션/메시지/질의 + 날짜 스코프(day/week/month)
4. 리포트(일/주/월) + 이벤트 수정/삭제/Undo
5. 설정(언어/테마/폰트/구조) + 구독 + CSV export

### 3.3 오프라인/동기화

1. 오프라인 캐시
2. mutation queue
3. 온라인 복귀 시 큐 flush
4. 로컬 온보딩 후 온라인 동기화

### 3.4 Assistant

1. `babyai://assistant/query|open` URL 인입
2. payload 키 매핑(`feature`, `query`, `memo`, `amount_ml`, `duration_min`, etc.)
3. App Intents + App Shortcuts 구현

## 4. 범위 제외(Out of Scope)

1. 백엔드 신규 기능 개발
2. Android 앱 수정
3. 결제 PG 실결제 연동 신규 구축
4. 서버 인프라/DevOps 개편

단, iOS 구현을 막는 API 계약 이슈는 별도 CR(Change Request) 없이 선행 조정해야 한다.

## 5. 기술 요구사항(필수)

1. Swift + SwiftUI 기반
2. Xcode 16+ / iOS 18.0+ 타겟
3. 네트워크: `URLSession` + 명시적 에러 매핑
4. 인증 토큰 저장: Keychain
5. 로컬 데이터 저장: App Sandbox 안전 경로 + 데이터 보호 정책
6. 비동기 처리: Swift Concurrency(`async/await`)
7. 로그: 개인정보 마스킹

## 6. API 소스 오브 트루스 및 선행 이슈

### 6.1 계약 기준 우선순위

1. 1순위: `apps/backend/internal/server/app.go` (실제 라우터)
2. 2순위: `docs/api/openapi.yaml`
3. 3순위: Flutter 클라이언트 구현

### 6.2 킥오프 전 확정 필요(블로커)

아래 경로는 현재 Router에 없으나 OpenAPI/모바일에는 존재한다.

- `/api/v1/photos/upload`
- `/api/v1/photos/recent`
- `/api/v1/quick/last-feeding`
- `/api/v1/quick/recent-sleep`
- `/api/v1/quick/last-diaper`
- `/api/v1/quick/last-medication`

또한 Router에는 있으나 OpenAPI에 누락된 경로가 있다.

- `/api/v1/chat/sessions`
- `/api/v1/chat/sessions/:session_id/messages`
- `/api/v1/chat/query`
- `/api/v1/events/:event_id`

**요구사항:** 계약 시작일 +3영업일 내 API 동결 문서(v2) 확정.

## 7. 산출물(Deliverables)

1. iOS 앱 소스코드(Xcode 프로젝트 전체)
2. 환경설정 문서(개발/스테이징/운영)
3. API 매핑표(엔드포인트별 Request/Response/에러코드)
4. 화면별 기능 명세 및 상태 다이어그램
5. 테스트 결과서
6. 릴리즈 노트(알려진 이슈 포함)
7. 인수인계 문서(빌드/배포/운영)

## 8. 검수/수락 기준(Acceptance Criteria)

### 8.1 기능 수락

1. 온보딩 -> 홈 진입 -> 기록 생성/수정/삭제/Undo 정상 동작
2. 채팅 세션 생성/목록/대화/재진입 정상 동작
3. 일/주/월 리포트 데이터 정확히 표시
4. 설정 변경 즉시 반영 및 재실행 후 복원
5. CSV 내보내기 정상
6. URL 딥링크 + App Intent 인입 정상

### 8.2 품질 수락

1. 크래시 없는 주요 경로 테스트 통과
2. 네트워크 실패/토큰 만료/오프라인 복구 시나리오 처리
3. 개인정보/민감정보 로그 유출 없음
4. 코드 리뷰 기준 충족(치명 버그 0건)

## 9. 일정/지급 마일스톤(권장)

1. M1 기획/설계 확정 (20%)
2. M2 핵심 기능(온보딩+기록+API 통신) 완료 (30%)
3. M3 채팅/리포트/설정/Assistant 완료 (30%)
4. M4 QA 수정 + 최종 인수인계 (20%)

각 마일스톤 수락 조건은 8장 기준으로 체크리스트 서명 후 지급.

## 10. 보고 체계

1. 주 2회 진행 리포트
2. 이슈 트래커(우선순위/원인/해결일) 공유
3. 위험요인 사전 통지(일정 영향 포함)

## 11. 제출 요청(외주사 제안서 포맷)

외주사는 아래 항목을 포함해 제안한다.

1. 수행 범위 이해도 및 구현 전략
2. 투입 인력(역할/경력/투입률)
3. 상세 일정(WBS)
4. 견적(마일스톤별 금액)
5. 리스크 및 대응 계획
6. 유사 프로젝트 실적

## 12. 공식/기술 레퍼런스(필수 준수)

Apple 공식 문서:

- App Intents: <https://developer.apple.com/documentation/appintents>
- AppIntent: <https://developer.apple.com/documentation/appintents/appintent>
- AppShortcutsProvider: <https://developer.apple.com/documentation/appintents/appshortcutsprovider>
- URLComponents: <https://developer.apple.com/documentation/foundation/urlcomponents>
- UIApplication open URL: <https://developer.apple.com/documentation/uikit/uiapplicationdelegate/application(_:open:options:)>
- UIScene open URL: <https://developer.apple.com/documentation/uikit/uiscenedelegate/scene(_:openurlcontexts:)>
- Keychain Services: <https://developer.apple.com/documentation/security/keychain-services>
- URLSession: <https://developer.apple.com/documentation/foundation/urlsession>
- NSPhotoLibraryUsageDescription: <https://developer.apple.com/documentation/bundleresources/information_property_list/nsphotolibraryusagedescription>
- Speech 권한: <https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition>

저장소 기준 문서:

- `docs/IOS_NATIVE_CONVERSION_HANDOFF.md`
- `apps/backend/internal/server/app.go`
- `docs/api/openapi.yaml`
- `packages/schema/prisma/schema.prisma`

## 13. 계약 특약 권장 문구

1. 소스코드/산출물 저작권은 발주사 귀속
2. 제3자 라이선스 위반 시 외주사 책임
3. 하자보수 기간(예: 검수 완료 후 60일) 명시
4. 개인정보 처리/비밀유지 위반 시 즉시 계약 해지 가능

