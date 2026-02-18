import AppIntents
import Flutter
import UIKit

final class AssistantIntentDispatcher {
  static let shared = AssistantIntentDispatcher()

  private let channelName = "babyai/assistant_intent"
  private var methodChannel: FlutterMethodChannel?
  private var lastPayload: [String: Any]?

  private init() {}

  func configure(binaryMessenger: FlutterBinaryMessenger) {
    if methodChannel != nil {
      return
    }

    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }

      if call.method == "getInitialAction" {
        result(self.lastPayload)
        return
      }
      result(FlutterMethodNotImplemented)
    }
    methodChannel = channel
  }

  func configureIfNeeded(rootViewController: UIViewController?) {
    if methodChannel != nil {
      return
    }
    guard let flutterViewController = rootViewController as? FlutterViewController else {
      return
    }
    configure(binaryMessenger: flutterViewController.binaryMessenger)
  }

  func handle(url: URL) {
    guard let payload = parsePayload(from: url) else {
      return
    }
    lastPayload = payload
    methodChannel?.invokeMethod("onAssistantAction", arguments: payload)
  }

  func handleLaunchArguments(_ arguments: [String]) {
    for argument in arguments {
      guard let url = URL(string: argument) else {
        continue
      }
      guard url.scheme?.lowercased() == "babyai" else {
        continue
      }
      handle(url: url)
      break
    }
  }

  private func parsePayload(from url: URL) -> [String: Any]? {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return nil
    }
    guard components.scheme?.lowercased() == "babyai" else {
      return nil
    }
    guard components.host?.lowercased() == "assistant" else {
      return nil
    }

    let path = components.path.lowercased()
    if !path.isEmpty && path != "/query" && path != "/open" {
      return nil
    }

    let queryItems = components.queryItems ?? []

    func queryValue(keys: [String]) -> String? {
      for key in keys {
        if let raw = queryItems.first(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame })?.value {
          let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
          if !trimmed.isEmpty {
            return trimmed
          }
        }
      }
      return nil
    }

    func parsePositiveInt(_ raw: String?) -> Int? {
      guard let raw = raw else {
        return nil
      }
      guard let parsed = Int(raw), parsed > 0 else {
        return nil
      }
      return parsed
    }

    var payload: [String: Any] = [:]

    if let feature = queryValue(keys: ["feature", "app_feature"]) {
      payload["feature"] = feature.lowercased()
    }
    if let query = queryValue(keys: ["query", "utterance", "text", "prompt"]) {
      payload["query"] = query
    }
    if let memo = queryValue(keys: ["memo", "note", "content"]) {
      payload["memo"] = memo
    }
    if let diaperType = queryValue(keys: ["diaper_type", "diaperType"]) {
      payload["diaper_type"] = diaperType
    }
    if let amountMl = parsePositiveInt(queryValue(keys: ["amount_ml", "amountMl", "amount"])) {
      payload["amount_ml"] = amountMl
    }
    if let durationMin = parsePositiveInt(queryValue(keys: ["duration_min", "durationMin", "duration"])) {
      payload["duration_min"] = durationMin
    }
    if let grams = parsePositiveInt(queryValue(keys: ["grams", "amount_g", "amountG"])) {
      payload["grams"] = grams
    }
    if let dose = parsePositiveInt(queryValue(keys: ["dose", "dose_mg", "doseMg"])) {
      payload["dose"] = dose
    }

    if let source = queryValue(keys: ["source"]) {
      payload["source"] = source.lowercased()
    } else {
      payload["source"] = "assistant"
    }

    if payload.count == 1 {
      return nil
    }
    return payload
  }
}

private struct BabyAIAssistantURLBuilder {
  private init() {}

  static func makeURL(
    query: String?,
    feature: String?,
    amountML: Int?,
    durationMin: Int?,
    diaperType: String?
  ) -> URL? {
    var components = URLComponents()
    components.scheme = "babyai"
    components.host = "assistant"
    components.path = "/query"

    var items: [URLQueryItem] = [URLQueryItem(name: "source", value: "siri")]
    if let feature, !feature.isEmpty {
      items.append(URLQueryItem(name: "feature", value: feature))
    }
    if let query, !query.isEmpty {
      items.append(URLQueryItem(name: "query", value: query))
    }
    if let amountML, amountML > 0 {
      items.append(URLQueryItem(name: "amount_ml", value: String(amountML)))
    }
    if let durationMin, durationMin > 0 {
      items.append(URLQueryItem(name: "duration_min", value: String(durationMin)))
    }
    if let diaperType, !diaperType.isEmpty {
      items.append(URLQueryItem(name: "diaper_type", value: diaperType))
    }
    components.queryItems = items
    return components.url
  }
}

@available(iOS 16.0, *)
private enum BabyAISiriFeature: String, AppEnum {
  case formula = "formula"
  case breastfeed = "breastfeed"
  case weaning = "weaning"
  case diaper = "diaper"
  case sleep = "sleep"
  case medication = "medication"
  case memo = "memo"
  case lastFeeding = "last_feeding"
  case recentSleep = "recent_sleep"
  case lastDiaper = "last_diaper"
  case todaySummary = "today_summary"
  case nextFeedingEta = "next_feeding_eta"

  static var typeDisplayRepresentation: TypeDisplayRepresentation {
    "BabyAI Feature"
  }

  static var caseDisplayRepresentations: [BabyAISiriFeature: DisplayRepresentation] {
    [
      .formula: "Formula",
      .breastfeed: "Breastfeed",
      .weaning: "Weaning",
      .diaper: "Diaper",
      .sleep: "Sleep",
      .medication: "Medication",
      .memo: "Memo",
      .lastFeeding: "Last Feeding",
      .recentSleep: "Recent Sleep",
      .lastDiaper: "Last Diaper",
      .todaySummary: "Today Summary",
      .nextFeedingEta: "Next Feeding ETA",
    ]
  }
}

@available(iOS 16.0, *)
private enum BabyAIDiaperType: String, AppEnum {
  case pee = "PEE"
  case poo = "POO"

  static var typeDisplayRepresentation: TypeDisplayRepresentation {
    "Diaper Type"
  }

  static var caseDisplayRepresentations: [BabyAIDiaperType: DisplayRepresentation] {
    [
      .pee: "Pee",
      .poo: "Poo",
    ]
  }
}

@available(iOS 16.0, *)
private enum BabyAISiriIntentError: LocalizedError {
  case emptyCommand
  case invalidURL

  var errorDescription: String? {
    switch self {
    case .emptyCommand:
      return "Command is empty."
    case .invalidURL:
      return "Failed to open BabyAI command URL."
    }
  }
}

@available(iOS 16.0, *)
private struct BabyAISendCommandIntent: AppIntent {
  static var title: LocalizedStringResource = "Send BabyAI Command"
  static var description = IntentDescription(
    "Send a natural-language command to BabyAI and open the app."
  )
  static var openAppWhenRun = true

  @Parameter(title: "Command")
  var query: String

  @Parameter(title: "Feature")
  var feature: BabyAISiriFeature?

  @Parameter(title: "Amount (mL)")
  var amountML: Int?

  @Parameter(title: "Duration (min)")
  var durationMin: Int?

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog & OpensIntent {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedAmount = amountML.flatMap { $0 > 0 ? $0 : nil }
    let normalizedDuration = durationMin.flatMap { $0 > 0 ? $0 : nil }
    if normalizedQuery.isEmpty && normalizedAmount == nil && normalizedDuration == nil && feature == nil {
      throw BabyAISiriIntentError.emptyCommand
    }

    guard let url = BabyAIAssistantURLBuilder.makeURL(
      query: normalizedQuery,
      feature: feature?.rawValue,
      amountML: normalizedAmount,
      durationMin: normalizedDuration,
      diaperType: nil
    ) else {
      throw BabyAISiriIntentError.invalidURL
    }
    return .result(
      opensIntent: OpenURLIntent(url),
      dialog: IntentDialog("Opening BabyAI and sending your command.")
    )
  }
}

@available(iOS 16.0, *)
private struct BabyAILogFormulaIntent: AppIntent {
  static var title: LocalizedStringResource = "Log Formula in BabyAI"
  static var description = IntentDescription(
    "Log a formula feeding amount and open BabyAI."
  )
  static var openAppWhenRun = true

  @Parameter(title: "Amount (mL)")
  var amountML: Int

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog & OpensIntent {
    guard amountML > 0 else {
      throw BabyAISiriIntentError.emptyCommand
    }
    guard let url = BabyAIAssistantURLBuilder.makeURL(
      query: "formula \(amountML)ml record",
      feature: BabyAISiriFeature.formula.rawValue,
      amountML: amountML,
      durationMin: nil,
      diaperType: nil
    ) else {
      throw BabyAISiriIntentError.invalidURL
    }
    return .result(
      opensIntent: OpenURLIntent(url),
      dialog: IntentDialog("Opening BabyAI to log formula.")
    )
  }
}

@available(iOS 16.0, *)
private struct BabyAILogDiaperIntent: AppIntent {
  static var title: LocalizedStringResource = "Log Diaper in BabyAI"
  static var description = IntentDescription(
    "Log a pee/poo diaper event and open BabyAI."
  )
  static var openAppWhenRun = true

  @Parameter(title: "Type")
  var diaperType: BabyAIDiaperType

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog & OpensIntent {
    guard let url = BabyAIAssistantURLBuilder.makeURL(
      query: "diaper \(diaperType.rawValue.lowercased()) record",
      feature: BabyAISiriFeature.diaper.rawValue,
      amountML: nil,
      durationMin: nil,
      diaperType: diaperType.rawValue
    ) else {
      throw BabyAISiriIntentError.invalidURL
    }
    return .result(
      opensIntent: OpenURLIntent(url),
      dialog: IntentDialog("Opening BabyAI to log diaper.")
    )
  }
}

@available(iOS 16.0, *)
private struct BabyAIAppShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    return [
      AppShortcut(
        intent: BabyAISendCommandIntent(),
        phrases: [
          "Send command in \(.applicationName)",
          "Ask \(.applicationName) assistant",
        ],
        shortTitle: "Assistant",
        systemImageName: "sparkles"
      ),
      AppShortcut(
        intent: BabyAILogFormulaIntent(),
        phrases: [
          "Log formula in \(.applicationName)",
          "Record feeding in \(.applicationName)",
        ],
        shortTitle: "Formula",
        systemImageName: "drop.circle"
      ),
      AppShortcut(
        intent: BabyAILogDiaperIntent(),
        phrases: [
          "Log diaper in \(.applicationName)",
          "Record diaper in \(.applicationName)",
        ],
        shortTitle: "Diaper",
        systemImageName: "figure.child.circle"
      ),
    ]
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 16.0, *) {
      BabyAIAppShortcuts.updateAppShortcutParameters()
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if url.scheme?.lowercased() == "babyai" {
      AssistantIntentDispatcher.shared.handle(url: url)
      return true
    }
    return super.application(app, open: url, options: options)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    AssistantIntentDispatcher.shared.configure(
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
  }
}
