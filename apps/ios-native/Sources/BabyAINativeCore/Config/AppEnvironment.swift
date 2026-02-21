import Foundation

public struct AppEnvironment: Sendable, Equatable {
    public let baseURL: URL
    public let requestTimeout: TimeInterval

    public init(baseURL: URL, requestTimeout: TimeInterval = 30) {
        self.baseURL = baseURL
        self.requestTimeout = requestTimeout
    }

    public static func fromProcessEnvironment(
        env: [String: String] = ProcessInfo.processInfo.environment,
        defaultBaseURL: URL = URL(string: "http://127.0.0.1:8080")!
    ) -> AppEnvironment {
        if let raw = env["API_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let parsed = URL(string: raw) {
            return AppEnvironment(baseURL: parsed)
        }
        return AppEnvironment(baseURL: defaultBaseURL)
    }
}
