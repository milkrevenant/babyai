# codex/test1 브랜치 대비 현재 작업본 상세 비교 분석

## 0. 비교 기준
- 비교 대상 원격: `https://github.com/milkrevenant/babyai/tree/codex/test1`
- 원격 기준 커밋: `origin/codex/test1` = `5378b2e`
- 현재 기준 커밋: `HEAD` = `de60f65`
- 현재 비교에는 `HEAD` 커밋 차이 + 워킹트리 미커밋 변경 + 언트래킹 파일(`apps/mobile/assets/icons/`, `apps/mobile/lib/core/widgets/app_svg_icon.dart`)을 포함
- 전체 추출 결과: `68`개 추적 파일 변경 (`+6317 / -12227`), 추가 언트래킹 항목 3개(`.runlogs/`, 아이콘 폴더, `app_svg_icon.dart`)

### 0.1 디렉토리 영향도
| 영역 | 변경 파일 수 |
|---|---:|
| `apps/mobile` | 44 |
| `apps/backend` | 18 |
| `docs` | 4 |
| 루트/기타 | 2 |

---

## 1. UI / UIX 변화

### 1.1 전역 컬러/테마 구조 변화
### 1.1.1 앱 전역 라이트 테마를 Seed 기반 -> 명시 팔레트로 전환
- 파일: `apps/mobile/lib/core/app.dart`
- 기존(`codex/test1`): `ColorScheme.fromSeed(seedColor: ...)` 기반
- 현재: 라이트 모드에서 고정 팔레트 직접 지정
- 신규 주요 색상
  - Primary: `#E4B347`
  - Secondary: `#8A7B66`
  - Surface: `#F7F4EF`
  - OnSurface: `#2D2924`
  - SurfaceContainerHighest: `#EFE8DE`
  - Outline: `#D8CFC4`
- 의미
  - 라이트 모드 비주얼이 테마 컨트롤러 accent seed보다 고정 브랜딩 톤에 더 강하게 고정됨
  - 화면 전체 톤이 베이지/웜 계열로 통일됨

### 1.1.2 리포트/기록 화면의 의미색(Semantic Color) 체계 재정의
- 파일: `apps/mobile/lib/features/report/report_page.dart`, `apps/mobile/lib/features/recording/recording_page.dart`
- 기존 리포트 카테고리색
  - sleep `#8C8ED4`, breastfeed `#E05A67`, formula `#E0B44C`, pee `#6FA8DC`, poo `#8A6A5A`, medication `#72B37E`
- 현재 리포트 카테고리색
  - sleep `#9B7AD8`, feed `#2D9CDB`, diaper `#1CA79A`, play `#F09819`, medication `#E84076`, hospital `#8E44AD`, memo `#A546C9`, other `#9AA4B2`
- 의미
  - 카테고리 분류가 기존 “이벤트 타입 중심”에서 “도메인 의미(병원/메모/기타)”까지 확장

### 1.2 아이콘 시스템 변화

### 1.2.1 커스텀 아이콘 자산 계층 신규 도입
- 신규 파일
  - `apps/mobile/lib/core/widgets/app_svg_icon.dart`
  - `apps/mobile/assets/icons/*`
- 도입 내용
  - SVG/PNG 통합 렌더링 위젯(`AppSvgIcon`) 추가
  - 바텀 네비/채팅 아바타/기록 타일/리포트 요소에 공통 적용

### 1.2.2 신규 아이콘 에셋 목록
| 파일 | 포맷 | 크기/해상도 |
|---|---|---|
| `icon_ai_chat_sparkles.svg` | SVG | 512 viewBox, gold fill(`#F2C14E`) |
| `icon_profile.svg` | SVG | 512 viewBox, gray fill(`#4B4B4B`) |
| `icon_stats.svg` | SVG | 512 viewBox, gray fill(`#4B4B4B`) |
| `icon_memo_lucide.svg` | SVG | 24 viewBox, stroke 기반 |
| `icon_bell.png` | PNG | 593x593 |
| `icon_clinic_stethoscope.png` | PNG | 616x616 |
| `icon_diaper.png` | PNG | 639x639 |
| `icon_feeding.png` | PNG | 581x581 |
| `icon_home.png` | PNG | 1024x1536 |
| `icon_medicine.png` | PNG | 564x564 |
| `icon_play_car.png` | PNG | 634x634 |
| `icon_sleep_crescent_purple.png` | PNG | 612x612 |
| `icon_sleep_crescent_yellow.png` | PNG | 617x617 |

### 1.2.3 바텀 네비게이션 아이콘 구성 변경
- 파일: `apps/mobile/lib/core/app.dart`
- 변경 포인트
  - `chat` 탭: `Icons.chat_bubble_outline` -> `AppSvgAsset.aiChatSparkles`
  - `statistics` 탭: `Icons.insert_chart_outlined` -> `AppSvgAsset.stats`
  - `market` 탭: `Icons.storefront_outlined` -> `AppSvgAsset.playCar`
  - `community` 탭: `Icons.groups_outlined` -> `AppSvgAsset.profile`
  - 탭 렌더러가 `IconData` 전용 -> `IconData + iconAsset` 하이브리드 구조

### 1.3 정보구조(IA) / 내비게이션 UX 변화

### 1.3.1 하단 탭 의미 변경 (중요)
- 파일: `apps/mobile/lib/core/app.dart`
- 기존
  - Home / Statistics / Chat / Photos / Market / Community
- 현재
  - Home / Chat / Statistics / Settings(photos 슬롯 재사용) / Market / Community
- 핵심 변화
  - Photos 탭이 사실상 사라지고 해당 슬롯이 Settings로 치환됨
  - Chat과 Statistics 탭 순서도 변경

### 1.3.2 상단 바 동작 변경
- 파일: `apps/mobile/lib/core/app.dart`
- 기존: 화면별 range 드롭다운/사진 뷰 토글/다양한 상단 액션
- 현재
  - 좌측 메뉴 버튼이 “채팅 히스토리 드로어” 오픈으로 통일
  - 통계 탭에서만 refresh 버튼 노출
  - Home은 Day/Week/Month 칩 유지
  - Settings/Chat은 힌트형 상단 텍스트로 단순화

### 1.3.3 드로어 목적 변경
- 기존: 일반 앱 메뉴 성격
- 현재: “Previous chats” 전용 패널
  - 세션 목록
  - 새 대화 생성 버튼
  - 세션 재진입 기능

### 1.4 화면 단위 UI 변화

### 1.4.1 Chat 화면
- 파일: `apps/mobile/lib/features/chat/chat_page.dart`
- 변경
  - 진입 시 쓰레드 로딩 우선 -> “새 대화 생성” 우선으로 초기화
  - 타이틀/아바타 아이콘을 커스텀 스파클/프로필 아이콘으로 교체
  - Markdown 렌더링 대폭 강화
    - 표(Table) soft-wrap 힌트 삽입
    - 긴 토큰 강제 분할
    - 코드블록/blockquote/table 스타일 세분화
    - 폰트 fallback 명시(`NotoSans` + `IBMPlexSans`)
  - 표 렌더 밀도 조정
    - table body/head 폰트 미세 축소(가독성 유지 + 정보 밀도 개선)
    - 셀 패딩 축소(`horizontal 10->8`, `vertical 8->6`)
    - 테이블 border/padding 미세 조정(`0.8->0.7`, bottom `8->6`)

### 1.4.2 Recording 화면
- 파일: `apps/mobile/lib/features/recording/recording_page.dart`
- 변경
  - 상단에 AI credit(잔액/그레이스 사용량) 배지 노출
  - 상단 대표 카드가 “현재 활동(수면)”에서 “타이머” 카드로 전환
  - 타이머 활동을 `수면/수유/모유/기저귀` 중 선택 가능(ChoiceChip)
  - `시작`/`종료` 버튼으로 타이머 구동 후 종료 시 기록 저장
  - 카드 내에 `시작시각`, `종료시각`, `총 시간(HH:MM:SS)` 표시
  - 빠른 기록 타일 아이콘을 커스텀 자산으로 통일
  - 전체가 대형 라운드 카드 중심 스타일로 재디자인

### 1.4.3 Report 화면
- 파일: `apps/mobile/lib/features/report/report_page.dart`
- 기존: 이벤트 파싱 + 수직 타임바 중심 구조
- 현재: `daily/weekly/monthly` 분리 렌더 구조로 전면 재작성
  - `_DayStats` 데이터 모델 중심 재집계
  - 시계형 타임라인 + 도넛 + 주/월 인사이트 분리
  - “hospital/memo/other” 범주 추가
  - 커스텀 아이콘 기반 하이라이트 카드

### 1.4.4 Photos 화면
- 파일: `apps/mobile/lib/features/photos/photos_page.dart`
- 변화가 매우 큼
  - 기존 실사용 갤러리 기능 제거
    - 서버 `recentPhotos` 로드
    - 이미지 타일/앨범 뷰
    - pinch 컬럼 변경
    - 뷰어/공유/링크복사
    - 갤러리 picker 업로드
  - 현재는 데모 성격의 정적 카드 + 업로드 URL 실험 패널로 단순화
    - `createUploadUrl` / `completeUpload` 응답 JSON 뷰

### 1.4.5 Settings / Child profile / Home tile settings
- 파일
  - `apps/mobile/lib/features/settings/settings_page.dart`
  - `apps/mobile/lib/features/settings/child_profile_page.dart`
  - `apps/mobile/lib/features/settings/home_tile_settings_page.dart`
- 공통 변화
  - 커스텀 드롭다운 데코/레이아웃 제거, 기본 `DropdownButtonFormField` 중심으로 단순화
- 기능 제거
  - Home tile columns 설정 제거
  - Home tile reorder(drag) 제거
  - Show special memo 토글 제거

### 1.4.6 Community 화면
- 파일: `apps/mobile/lib/features/community/community_page.dart`
- 기존: 상세 포스트 모델 + 상세 페이지 + 태그/본문
- 현재: 문자열 리스트 + 기본 ListTile 형태로 단순화

### 1.5 의존성/플랫폼 UI 관련 변화
- 파일: `apps/mobile/pubspec.yaml`, generated plugin registrants
- 추가
  - `flutter_svg`
- 제거
  - `image_picker`, `share_plus`
  - 플랫폼별 plugin registration에서 file_selector/share_plus/url_launcher 다수 제거
- 의미
  - 포토 picker/share UX 제거와 직접 연동

---

## 2. 로직 변화 (앱 전반)

### 2.1 API 표면 변화

### 2.1.1 제거된 API (현재 기준)
- `GET/POST /dev/local-token`
- `POST /api/v1/events/start`
- `PATCH /api/v1/events/{event_id}`
- `PATCH /api/v1/events/{event_id}/complete`
- `PATCH /api/v1/events/{event_id}/cancel`
- `GET /api/v1/events/open`
- `GET /api/v1/quick/last-feeding`
- `GET /api/v1/quick/recent-sleep`
- `GET /api/v1/quick/last-diaper`
- `GET /api/v1/quick/last-medication`
- `POST /api/v1/photos/upload`
- `GET /api/v1/photos/recent`

### 2.1.2 유지/강화된 API
- `POST /api/v1/events/manual`
- `GET /api/v1/quick/last-poo-time`
- `GET /api/v1/quick/next-feeding-eta`
- `GET /api/v1/quick/today-summary`
- `GET /api/v1/quick/landing-snapshot`
- `POST /api/v1/chat/*`, `POST /api/v1/ai/query` (호환 래퍼)

### 2.1.3 OpenAPI 문서와 실제 라우터 정합성 이슈
- 파일: `docs/api/openapi.yaml`, `apps/backend/internal/server/app.go`
- 현재 OpenAPI는
  - `GET /api/v1/chat/sessions`를 누락
  - `POST /api/v1/events/manual`를 누락
  - `UserSettingsResponse`를 `theme_mode` 단일 필드로 축소 표기
- 실제 백엔드는 위 항목들을 더 넓게 지원

### 2.2 이벤트/기록 로직 변화
- 파일: `apps/backend/internal/server/handlers_onboarding_events.go`, `apps/mobile/lib/features/recording/recording_page.dart`
- 변경 핵심
  - Event 수명주기(`OPEN -> CLOSED/CANCELED`) 기반 API 제거
  - 수동 기록은 완료형 insert만 남김
  - Event insert SQL에서 `status` 컬럼 사용 제거
  - 모바일 타이머도 `POST /api/v1/events/manual` 완료형 저장 모델에 맞춰 동작
  - 타이머 종료 시 `start_time/end_time`과 `duration_min/duration_sec`, `metadata.timer_activity`를 함께 저장
  - 수면 타이머는 `pending_sleep_start` 상태를 재사용해 앱 재진입 시 진행 상태 복원

### 2.3 세션/토큰 로직 변화 (모바일)
- 파일: `apps/mobile/lib/core/config/session_store.dart`
- 변경
  - 저장된 세션 복원 시, `--dart-define` 토큰과 로컬 저장 토큰이 다르면 JWT `sub` 비교 후 ID 복원 결정
  - 계정 전환 시 오래된 `baby_id/household_id/album_id` 오염 복원 방지
  - `pending_formula_start` 상태 저장 제거

### 2.4 온보딩 토큰 정책 변화
- 파일: `apps/mobile/lib/features/settings/child_profile_page.dart`, `apps/mobile/lib/core/network/babyai_api.dart`
- 변경
  - 로컬 `/dev/local-token` 자동 발급 fallback 제거
  - 초기 온보딩 시 토큰 미존재면 명시적으로 validation 에러 처리

### 2.5 급여 ETA 계산 로직 개선
- 파일: `apps/backend/internal/server/app.go`, `apps/backend/internal/server/helpers_unit_test.go`
- 개선
  - 미래 시각 feeding 이벤트 제외
  - 평균 간격 반올림 처리
  - ETA가 과거로 떨어지면 다음 주기로 projection
  - 테스트 기대값도 해당 동작에 맞춰 갱신

### 2.6 플랫폼 Assistant/Shortcut 로직 축소
- 파일: Android/iOS shortcut/intent 관련 파일 다수
- 제거
  - Android `actions.intent.GET_THING` capability 제거
  - `assistant/query` deep link 제거
  - iOS AppIntents/Siri Shortcut/AppDelegate 대규모 로직 제거

---

## 3. AI Chat 변화

### 3.1 엔드포인트/처리 파이프라인 재배치
- 파일: `apps/backend/internal/server/handlers_chat.go`, `apps/backend/internal/server/handlers_quick_ai_reports.go`
- 변화
  - `aiQuery` 처리 로직이 `handlers_chat.go`로 이동
  - `/api/v1/ai/query`는 `runChatQuery` 재사용 래퍼로 작동
  - 응답에 `intent`, `session_id`, `message_id`, `model`, `usage`, `credit`, `reference_text` 포함

### 3.2 세션 생성/선택 정책 강화
- 파일: `apps/backend/internal/server/handlers_chat.go`
- 추가 동작
  - 채팅 세션 생성 시 동일 user/household/child의 ACTIVE 세션을 자동 CLOSED로 회전
  - child 미지정 세션 생성 시 household의 primary child 자동 연결 시도
  - query 시 child 미지정 + personal data true면 household primary child fallback

### 3.3 인텐트 라우팅 정밀화
- 파일: `apps/backend/internal/server/handlers_chat.go`
- 추가
  - `loadFirstUserMessageIntent`, `saveFirstUserIntent`
  - 첫 사용자 메시지 intent를 DB(`ChatMessage.intent`)에 고정 저장
  - caregiver self-talk 감지(`isLikelyCaregiverSelfTalk`) 후 smalltalk 강제
  - 이후 턴에서도 첫 메시지 intent 일관성 유지

### 3.4 컨텍스트 생성 고도화
- 파일: `apps/backend/internal/server/handlers_chat.go`
- 추가
  - `loadChildProfileSnapshot`로 아동 프로필 스냅샷 결합
    - 이름, 생년월일, age_days, age_months(달력 기준), 체중/신장, 성장 이벤트 측정시점
  - `buildChatContext` 메타에 `profile_*` 및 `reference_now_utc` 포함
  - growth 이벤트(`type='GROWTH'`)에서 height/weight fallback 추출

### 3.5 답변 후처리(sanitize) 추가
- 파일: `apps/backend/internal/server/handlers_chat.go`
- `sanitizeUserFacingAnswer`
  - `<br>` 제거/줄바꿈 정리
  - RFC3339 datetime -> `YYYY-MM-DD HH:MM` 표준화
  - UTC 표기/잔여 토큰 제거
- `sanitizeSmalltalkAnswer`
  - markdown/list prefix 제거
  - 단문 합치기
  - 길이 제한(`90` rune)
- 추가 프롬프트 정책(응답 포맷)
  - 데이터 항목이 많거나 비교 포인트가 3개 이상이면 Markdown 표를 우선 사용
  - 항목 수가 적을 때는 짧은 요약 문단/불릿 우선
  - 표 사용 시 2열(`항목`, `요약`) 중심 유지, `항목`은 짧게/`요약`은 상대적으로 상세하게 작성
  - 요약은 `횟수`, `시간`, `ml 용량` 중심으로 제시하고 표 셀은 1~2줄 중심으로 압축

### 3.6 모바일 Chat UX 연계 강화
- 파일: `apps/mobile/lib/core/app.dart`, `apps/mobile/lib/features/chat/chat_page.dart`
- 변경
  - 앱 드로어에서 채팅 세션 히스토리 직접 관리
  - 드로어에서 세션 재개/새 대화 생성
  - 채팅 렌더가 Markdown 테이블/긴 텍스트 대응 강화

### 3.7 테스트 변화
- 파일: `apps/backend/internal/server/chat_credit_integration_test.go`, `quick_ai_reports_integration_test.go`
- 추가
  - `child_id` 누락 시 onboarding child fallback 검증 테스트
- 축소/변경
  - 기존 quick snapshot/ai query 상세 endpoint 테스트 대거 제거
  - AI query 테스트는 intent 라우팅/공통 응답 필드 중심으로 재구성

---

## 4. DB (백엔드) 변화

### 4.1 Event 테이블 사용 모델 전환
### 4.1.1 status 기반 이벤트 상태관리 제거 방향
- 코드/문서 변화 근거
  - `handlers_onboarding_events.go`: Event insert에서 `status` 제거
  - `handlers_quick_ai_reports.go`, `handlers_media_subscription_assistants.go`, `handlers_baby_profile.go`: `status='CLOSED'` 필터 제거
  - `docs/ARCHITECTURE.md`, `docs/DATA_CONTRACT.md`: Event 컬럼 정의에서 `status`, `updated_at` 제거

### 4.1.2 OPEN 이벤트 수명주기 API 및 쿼리 제거
- 제거된 함수
  - `startManualEvent`, `updateManualEvent`, `completeManualEvent`, `cancelManualEvent`, `listOpenEvents`
- 영향
  - DB 관점에서 Event 상태 전이 트랜잭션이 사라지고 완료형 단건 insert 중심으로 단순화

### 4.2 Chat 관련 DB 변화
- 파일: `apps/backend/internal/server/handlers_chat.go`
- 변화
  - 채팅 세션 생성 시 기존 ACTIVE 세션 일괄 CLOSED update
  - `ChatSession.childId` 자동 보정 update
  - 첫 user message intent를 `ChatMessage.intent`에 persist
  - 기존 session memory summary 컬럼 자동 보정 로직은 유지

### 4.3 PersonaProfile(app_settings) 저장 키 변화
- 파일: `apps/backend/internal/server/handlers_settings.go`
- 제거 키
  - `home_tile_columns`
  - `home_tile_order`
  - `show_special_memo`
- 기본값 변경
  - `highlight_font`: `ibmPlexSans` -> `notoSans`
  - home tile default: `weaning`, `medication` 기본 비활성

### 4.4 PhotoAsset/미디어 흐름 변화
- 파일: `apps/backend/internal/server/handlers_media_subscription_assistants.go`
- 제거
  - 로컬 파일 저장형 `uploadPhotoFromDevice` (`/uploads` 경로, 디스크 저장)
  - `listRecentPhotos`
- 유지
  - `createPhotoUploadURL` + `completePhotoUpload` 2단계 흐름
- 의미
  - 백엔드 DB는 완료 콜백 시점의 메타 등록 중심으로 단순화

### 4.5 테스트 하네스/계약 변화
- 파일: `apps/backend/internal/server/test_harness_test.go`
- `seedEvent`에서 `status` 컬럼 insert 제거
- `settings_integration_test.go`, `events_manual_lifecycle_integration_test.go` 등 상태 기반 테스트 대거 제거

---

## 5. 요청 항목별 핵심 정리 (요약)

### 5.1 UI/UIX
- 고정 라이트 팔레트 도입, 의미색 체계 재정의, 커스텀 아이콘 시스템 도입
- 탭 IA 변경(Photos -> Settings), Chat/Statistics 순서 변경
- Photos/Community/Settings/Report/Recording 화면 구조가 전면 재편
- Recording 상단 핵심 인터랙션이 “수면 상태 표시”에서 “활동 선택형 타이머 + 시작/종료 기록”으로 변경

### 5.2 로직 변화
- Event 수명주기 API, 일부 quick API, local dev token, 로컬 사진 업로드/최근조회 제거
- 세션 복원/온보딩 토큰/ETA 계산/Assistant shortcut 로직이 모두 단순화 또는 재설계

### 5.3 AI Chat
- `ai/query`가 chat 파이프라인 래퍼로 통합
- 인텐트 고정 저장 + self-talk 가드 + 프로필 스냅샷 결합 + 답변 sanitize 도입
- 데이터량이 많을 때 표 우선, 적을 때 요약 문단 우선이라는 포맷 정책이 강화됨
- 모바일에서도 채팅 히스토리 UX가 강화됨

### 5.4 DB(백엔드)
- Event를 status 전이 모델에서 사실상 단순 이벤트 로그 모델로 전환하는 방향
- Persona settings 저장 키 축소
- Chat 세션/메시지 메타 persist 강화

---

## 6. 참고: 핵심 변경 파일 인덱스
- `apps/mobile/lib/core/app.dart`
- `apps/mobile/lib/core/theme/app_theme_controller.dart`
- `apps/mobile/lib/core/network/babyai_api.dart`
- `apps/mobile/lib/core/config/session_store.dart`
- `apps/mobile/lib/core/widgets/app_svg_icon.dart` (신규)
- `apps/mobile/lib/features/chat/chat_page.dart`
- `apps/mobile/lib/features/recording/recording_page.dart`
- `apps/mobile/lib/features/report/report_page.dart`
- `apps/mobile/lib/features/photos/photos_page.dart`
- `apps/backend/internal/server/app.go`
- `apps/backend/internal/server/handlers_chat.go`
- `apps/backend/internal/server/handlers_onboarding_events.go`
- `apps/backend/internal/server/handlers_quick_ai_reports.go`
- `apps/backend/internal/server/handlers_settings.go`
- `apps/backend/internal/server/handlers_media_subscription_assistants.go`
- `docs/api/openapi.yaml`
- `docs/ARCHITECTURE.md`
- `docs/DATA_CONTRACT.md`
