# iOS Native 전환 핸드오프 (BabyAI)

- 작성일: 2026-02-21
- 대상: iOS 네이티브(Xcode/Swift) 전환 구현 담당
- 기준: 이 저장소의 실제 코드(Flutter/Go/Prisma) 기준

## 1) 문서 목적

현재 Flutter 앱의 동작을 **추측 없이 코드 기준으로** iOS 네이티브에 이식하기 위한 구현 명세 문서다.  
특히 다음 5가지를 맞추는 것이 목표다.

1. 화면/기능 동작 동일성
2. API 계약 동일성
3. 오프라인/동기화 정책 동일성
4. Assistant(앱 인텐트/딥링크) 브리지 동일성
5. 릴리즈 전 검증 포인트 명확화

## 2) 코드 기준 소스(핵심)

- 앱 셸/네비게이션: `apps/mobile/lib/core/app.dart`
- API 클라이언트/오프라인 큐: `apps/mobile/lib/core/network/babyai_api.dart`
- 세션 저장: `apps/mobile/lib/core/config/session_store.dart`
- 오프라인 저장소: `apps/mobile/lib/core/storage/offline_data_store.dart`
- Assistant 브리지: `apps/mobile/lib/core/assistant/assistant_intent_bridge.dart`
- iOS 브리지: `apps/mobile/ios/Runner/AppDelegate.swift`, `apps/mobile/ios/Runner/SceneDelegate.swift`, `apps/mobile/ios/Runner/Info.plist`
- 백엔드 라우터: `apps/backend/internal/server/app.go`
- 요청/응답 모델: `apps/backend/internal/server/handlers.go` + 각 handler 파일
- DB 스키마: `packages/schema/prisma/schema.prisma`
- API 문서(참조): `docs/api/openapi.yaml`

## 3) 앱 요약

- 도메인: 육아 기록(수유/수면/기저귀/투약/메모) + AI 대화/요약 + 리포트 + 구독/사진 + Assistant.
- 현재 모바일 프레임워크: Flutter (`apps/mobile/pubspec.yaml`)
- 백엔드: Go + Gin + PostgreSQL (`apps/backend`)
- 인증: Bearer JWT 필수(개발용 `/dev/local-token`, `/auth/test-login` 존재)
- iOS 프로젝트 설정: Deployment Target `18.0` (`apps/mobile/ios/Runner.xcodeproj/project.pbxproj`)

## 4) 현재 화면 구조와 동작

### 4.1 메인 인덱스 구조

`_HomeShell` 인덱스는 아래와 같다 (`apps/mobile/lib/core/app.dart`).

- `0`: Home(기록)
- `1`: Chat
- `2`: Statistics(리포트)
- `3`: `_photosPage`인데 실제 위젯은 `SettingsPage`로 연결됨
- `4`: Market
- `5`: Community

주의: `_photosPage` 이름과 다르게 실제로는 설정 화면이다. 또한 설정 UI에서 bottom menu 토글은 `photos`를 노출하지 않도록 되어 있다(`apps/mobile/lib/features/settings/settings_page.dart`).

### 4.2 핵심 기능

- Home/Recording
1. 수기 입력 + 타이머 입력 지원.
2. 이벤트 lifecycle: `createClosed`, `startOnly`, `completeOpen`.
3. 이벤트 타입 매핑:
   - `FORMULA`, `BREASTFEED`, `SLEEP`, `PEE/POO`, `MEDICATION`, `MEMO`
   - 이유식은 `MEMO` + `category=WEANING`/`metadata.entry_kind=WEANING`으로 저장됨.

- Chat
1. 세션 생성/목록/메시지 조회/질의.
2. 날짜 스코프(day/week/month + anchor date) 반영.
3. 음성 입력(STT) 버튼 존재(`speech_to_text` 사용).
4. 릴리즈 빌드에서는 구독 플랜에 따라 접근 제어.

- Statistics/Report
1. 일/주/월 리포트 조회.
2. 일일 이벤트 시간 수정(`PATCH /events/{event_id}`), 삭제(`PATCH /events/{event_id}/cancel`) 지원.
3. 삭제 Undo 시 `updateManualEvent(... metadata.undo_delete=true)` 사용.

- Settings
1. 개인화(언어/테마/폰트/톤), 앱 구조(홈 타일/하단 메뉴), 계정/아이 프로필, 구독, CSV 내보내기.
2. 언어: `ko`, `en`, `es`.

## 5) 상태/온보딩/오프라인 모델

### 5.1 온보딩 및 로그인 흐름

1. 앱 시작 시 `AppSessionStore.load()`로 로컬 세션 복원.
2. `baby_id`가 없으면 아기 온보딩 화면으로 진입.
3. 온보딩 저장 시 먼저 `createOfflineOnboarding()`으로 로컬 프로필 생성.
4. Google 연동 상태면 `onboardingParent()`로 서버 온보딩 동기화 시도.
5. 동기화 성공 시 서버 `baby_id/household_id`로 런타임 ID 교체.

### 5.2 오프라인 저장

- 세션 파일: `~/.babyai_session.json`
- 오프라인 캐시/큐: `~/.babyai_offline_store.json`
- mutation queue 종류:
  - `event_create_closed`
  - `event_start`
  - `event_complete`
  - `event_update`
  - `event_cancel`
- 온라인 복귀 시 `flushOfflineMutations()`로 서버 반영.

### 5.3 iOS 네이티브 전환 시 보안 전환 필수

- JWT/식별자 파일 직접 저장 대신 Keychain 저장 권장.
- 오프라인 파일은 App Support + 파일 보호(NSFileProtection) 정책 적용 권장.

## 6) 백엔드 API 계약 (현재 Router 기준)

아래는 `apps/backend/internal/server/app.go` 기준 실제 등록 라우트다.

### 6.1 비인증

- `GET /health`
- `GET /dev/local-token`
- `POST /dev/local-token`
- `POST /auth/test-login`

### 6.2 인증(`/api/v1/*`)

- 온보딩/이벤트
  - `POST /onboarding/parent`
  - `POST /events/voice`
  - `POST /events/confirm`
  - `POST /events/manual`
  - `POST /events/start`
  - `PATCH /events/:event_id`
  - `PATCH /events/:event_id/complete`
  - `PATCH /events/:event_id/cancel`
  - `GET /events/open`
- 설정/프로필/내보내기
  - `GET /settings/me`
  - `PATCH /settings/me`
  - `GET /data/export.csv`
  - `GET /babies/profile`
  - `PATCH /babies/profile`
- Quick/AI/Chat
  - `GET /quick/last-poo-time`
  - `GET /quick/next-feeding-eta`
  - `GET /quick/today-summary`
  - `GET /quick/landing-snapshot`
  - `POST /ai/query`
  - `POST /chat/sessions`
  - `GET /chat/sessions`
  - `POST /chat/sessions/:session_id/messages`
  - `GET /chat/sessions/:session_id/messages`
  - `POST /chat/query`
- 리포트
  - `GET /reports/daily`
  - `GET /reports/weekly`
  - `GET /reports/monthly`
- 사진/구독/Assistant
  - `POST /photos/upload-url`
  - `POST /photos/complete`
  - `GET /subscription/me`
  - `POST /subscription/checkout`
  - `POST /assistants/siri/GetLastPooTime`
  - `POST /assistants/siri/GetNextFeedingEta`
  - `POST /assistants/siri/GetTodaySummary`
  - `POST /assistants/siri/:intent_name`
  - `POST /assistants/bixby/query`

## 7) iOS Assistant 브리지 스펙 (현행)

### 7.1 브리지 채널

- Flutter MethodChannel 이름: `babyai/assistant_intent`
- 메서드:
  - `getInitialAction`
  - `onAssistantAction`

### 7.2 URL 스킴

- scheme: `babyai`
- host: `assistant`
- path: `/query` 또는 `/open`
- payload key:
  - `feature`, `query`, `memo`, `diaper_type`, `amount_ml`, `duration_min`, `grams`, `dose`, `source`

### 7.3 iOS App Intents (현재 정의)

`apps/mobile/ios/Runner/AppDelegate.swift` 기준:

- `BabyAISendCommandIntent`
- `BabyAILogFormulaIntent`
- `BabyAILogDiaperIntent`
- `AppShortcutsProvider` 등록 완료

또한 `SceneDelegate`에서 `scene(_:openURLContexts:)`를 사용해 URL 인입을 처리한다.

## 8) 데이터 모델 핵심 (Prisma)

`packages/schema/prisma/schema.prisma` 기준 주요 엔티티:

- 계정/가정: `User`, `Household`, `HouseholdMember`, `Consent`, `AuditLog`
- 아이/기록: `Baby`, `Event`, `VoiceClip`, `Report`
- 채팅/AI: `ChatSession`, `ChatMessage`, `UserCreditWallet`, `AiUsageLog`, `UserCreditGrantLedger`
- 사진/구독: `Album`, `PhotoAsset`, `Subscription`
- 요약 집계: `DailySummary`, `WeeklySummary`, `MonthlyMedicalSummary` 외 의료/활동 이벤트 테이블

핵심 enum:

- EventType: `FORMULA`, `BREASTFEED`, `SLEEP`, `PEE`, `POO`, `GROWTH`, `MEMO`, `SYMPTOM`, `MEDICATION`
- EventState: `OPEN`, `CLOSED`, `CANCELED`
- SubscriptionPlan: `PHOTO_SHARE`, `AI_ONLY`, `AI_PHOTO`

## 9) 코드 리뷰로 확인된 계약 드리프트 (중요)

아래는 실제 코드 대조 + `git diff` 확인 결과다.

### 9.1 모바일/OpenAPI에는 있는데 Router에 없는 엔드포인트

- `/api/v1/photos/upload`
- `/api/v1/photos/recent`
- `/api/v1/quick/last-feeding`
- `/api/v1/quick/recent-sleep`
- `/api/v1/quick/last-diaper`
- `/api/v1/quick/last-medication`

근거:

- 모바일 호출 정의: `apps/mobile/lib/core/network/babyai_api.dart`
- OpenAPI 정의: `docs/api/openapi.yaml`
- Router 등록: `apps/backend/internal/server/app.go`

영향:

- iOS 네이티브 구현 시 위 경로를 그대로 사용하면 404 발생 가능.
- 전환 전에 API 계약 확정(서버 구현 vs 클라이언트 제거) 필요.

### 9.2 Router에는 있는데 OpenAPI에 누락된 항목

- `/api/v1/chat/sessions`
- `/api/v1/chat/sessions/:session_id/messages`
- `/api/v1/chat/query`
- `/api/v1/events/:event_id`(update)
- Siri 고정 intent path 3종

영향:

- OpenAPI 기반 코드 생성 시 chat/update API 누락 위험.

### 9.3 iOS 권한 키 누락 가능성

현재 Info.plist에는 `NSPhotoLibraryUsageDescription`, `NSSiriUsageDescription`만 있고, 음성 인식 기능에 필요한 키는 보이지 않는다.

- `NSMicrophoneUsageDescription`
- `NSSpeechRecognitionUsageDescription`

현재 앱은 chat 화면에서 STT 버튼을 제공하므로, 네이티브 전환 시 권한 키와 권한 플로우를 반드시 명시적으로 구성해야 한다.

## 10) iOS 네이티브 전환 구현 체크리스트

1. API 계약 동결
2. 인증 저장소를 Keychain으로 전환
3. 온보딩/프로필/오프라인 큐 상태머신 먼저 이식
4. 기록(Home) 이벤트 lifecycle 이식
5. Chat 세션/메시지/질의 + 날짜 스코프 이식
6. Report 일/주/월 + 수정/삭제/Undo 이식
7. Settings(개인화/구독/CSV) 이식
8. Assistant(AppIntents + URL scheme + 앱 내부 라우팅) 이식
9. 라우트 드리프트 항목 정리 후 QA 시나리오 고정
10. 기존 Flutter와 응답 비교 회귀 테스트(동일 입력/동일 출력)

## 11) Xcode 전달용 요약 프롬프트

아래 문장을 Xcode Assistant에 그대로 전달해도 된다.

```text
Build an iOS-native BabyAI app in SwiftUI that reproduces the behavior in docs/IOS_NATIVE_CONVERSION_HANDOFF.md.
Use the backend API contract from apps/backend/internal/server/app.go as runtime source-of-truth, not OpenAPI alone.
Implement onboarding->offline-first profile->online sync, event lifecycle (create/start/complete/update/cancel), chat sessions/messages/query with day/week/month date scope, daily/weekly/monthly reports, settings/subscription/CSV export, and App Intents deep-link bridge using babyai://assistant/query|open payload keys.
Before coding photo/quick endpoints, resolve the documented route drift section in the handoff doc.
```

## 12) 공식 레퍼런스 (Apple)

- App Intents: [App Intents](https://developer.apple.com/documentation/appintents)
- Intent 타입: [AppIntent](https://developer.apple.com/documentation/appintents/appintent)
- App Shortcuts: [AppShortcutsProvider](https://developer.apple.com/documentation/appintents/appshortcutsprovider)
- URL 구성: [URLComponents](https://developer.apple.com/documentation/foundation/urlcomponents)
- URL 열기(AppDelegate): [application(_:open:options:)](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/application(_:open:options:))
- URL 열기(Scene): [scene(_:openURLContexts:)](https://developer.apple.com/documentation/uikit/uiscenedelegate/scene(_:openurlcontexts:))
- 커스텀 URL 스킴 키: [CFBundleURLTypes](https://developer.apple.com/documentation/bundleresources/information_property_list/cfbundleurltypes), [CFBundleURLSchemes](https://developer.apple.com/documentation/bundleresources/information_property_list/cfbundleurltypes/cfbundleurlschemes)
- 사진 권한 키: [NSPhotoLibraryUsageDescription](https://developer.apple.com/documentation/bundleresources/information_property_list/nsphotolibraryusagedescription)
- 앱 전송 보안(ATS): [NSAppTransportSecurity](https://developer.apple.com/documentation/bundleresources/information_property_list/nsapptransportsecurity)
- Keychain 저장: [Keychain Services](https://developer.apple.com/documentation/security/keychain-services)
- 네트워크 업로드: [URLSession](https://developer.apple.com/documentation/foundation/urlsession)
- 공유 시트: [UIActivityViewController](https://developer.apple.com/documentation/uikit/uiactivityviewcontroller)
- 음성 인식 권한 키 설명: [Requesting authorization for speech recognition](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition), [Cocoa Keys: NSSpeechRecognitionUsageDescription](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CocoaKeys.html)

