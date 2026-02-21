# BabyAI iOS Native Core

This folder adds iOS-native conversion code **without deleting or modifying** existing Flutter app code.

## Source-of-truth

- Router/API registration: `apps/backend/internal/server/app.go`
- Flutter runtime behavior: `apps/mobile/lib/core/network/babyai_api.dart`
- Session/offline behavior: `apps/mobile/lib/core/config/session_store.dart`, `apps/mobile/lib/core/storage/offline_data_store.dart`
- Assistant URL payload contract: `apps/mobile/ios/Runner/AppDelegate.swift`, `apps/mobile/lib/core/assistant/assistant_intent_bridge.dart`

## Included modules

- `SessionStore`: Keychain-backed session state (`token`, `baby_id`, `household_id`, pending timer start timestamps)
- `OfflineDataStore`: JSON cache/mutation queue in Application Support (iOS file protection applied)
- `BabyAIApiClient`: `/api/v1/*` client based on backend router
- `OfflineMutationSyncCoordinator`: flushes queued mutations (`event_create_closed`, `event_start`, `event_complete`, `event_update`, `event_cancel`)
- `OnboardingSyncCoordinator`: offline-first onboarding + optional online sync for Google-linked tokens
- `AssistantURLBridge`: `babyai://assistant/query|open` payload parser/builder

## Liquid Glass (SwiftUI)

Applied files:

- `Sources/BabyAINativeCore/UI/LiquidGlassTheme.swift`
- `Sources/BabyAINativeCore/UI/BabyAINativeShellView.swift`
- `Sources/BabyAINativeCore/UI/Components/GlassComponents.swift`
- `Sources/BabyAINativeCore/UI/Screens/HomeGlassView.swift`
- `Sources/BabyAINativeCore/UI/Screens/ChatGlassView.swift`
- `Sources/BabyAINativeCore/UI/Screens/StatisticsGlassView.swift`
- `Sources/BabyAINativeCore/UI/Screens/SettingsGlassView.swift`
- `Sources/BabyAINativeCore/UI/Screens/MarketGlassView.swift`
- `Sources/BabyAINativeCore/UI/Screens/CommunityGlassView.swift`

Applied items:

- Glass container (`GlassEffectContainer`) wrapper
- Glass cards (`.glassEffect(..., in: .rect(cornerRadius: ...))`)
- Glass primary/secondary button styles (`.buttonStyle(.glassProminent)`, `.buttonStyle(.glass)`)
- Tab shell with iOS-only minimize behavior (`.tabBarMinimizeBehavior(.onScrollDown)`)
- Glass styling across all tab screens (Home/Chat/Statistics/Settings/Market/Community)

Fallback behavior:

- On pre-iOS 26 (or unsupported platforms), theme falls back to Material styles.

## Route drift handling

The following endpoints are intentionally blocked and throw `BabyAIError.routeDrift(...)`:

- `/api/v1/photos/upload`
- `/api/v1/photos/recent`
- `/api/v1/quick/last-feeding`
- `/api/v1/quick/recent-sleep`
- `/api/v1/quick/last-diaper`
- `/api/v1/quick/last-medication`

This mirrors the documented drift in `docs/IOS_NATIVE_CONVERSION_HANDOFF.md`.

## Run tests

```bash
cd apps/ios-native
swift test
```

## Apple references

- [What’s new in SwiftUI (iOS 26)](https://developer.apple.com/documentation/updates/swiftui)
- [Migrating your app to use Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [View.glassEffect(_:in:isEnabled:)](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:isenabled:))
- [GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer)
- [ButtonStyle.glass](https://developer.apple.com/documentation/swiftui/buttonstyle/glass)
- [TabBarMinimizeBehavior](https://developer.apple.com/documentation/swiftui/tabbarminimizebehavior)
- [Keychain Services](https://developer.apple.com/documentation/security/keychain-services)
- [URLSession](https://developer.apple.com/documentation/foundation/urlsession)
- [URLComponents](https://developer.apple.com/documentation/foundation/urlcomponents)
- [App Intents](https://developer.apple.com/documentation/appintents)
