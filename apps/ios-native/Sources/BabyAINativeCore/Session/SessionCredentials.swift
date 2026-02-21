import Foundation

public struct SessionCredentials: Codable, Sendable, Equatable {
    public var bearerToken: String
    public var babyID: String
    public var householdID: String
    public var albumID: String
    public var pendingSleepStart: Date?
    public var pendingFormulaStart: Date?

    public init(
        bearerToken: String = "",
        babyID: String = "",
        householdID: String = "",
        albumID: String = "",
        pendingSleepStart: Date? = nil,
        pendingFormulaStart: Date? = nil
    ) {
        self.bearerToken = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.babyID = babyID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.householdID = householdID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.albumID = albumID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.pendingSleepStart = pendingSleepStart
        self.pendingFormulaStart = pendingFormulaStart
    }

    public var isConfigured: Bool {
        !bearerToken.isEmpty && !babyID.isEmpty
    }

    public var tokenProvider: String? {
        let parts = bearerToken.split(separator: ".")
        guard parts.count >= 2 else {
            return nil
        }
        var payload = String(parts[1])
        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        guard let decoded = Data(base64Encoded: payload, options: [.ignoreUnknownCharacters]),
              let object = try? JSONSerialization.jsonObject(with: decoded),
              let json = object as? [String: Any] else {
            return nil
        }

        if let provider = (json["provider"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !provider.isEmpty {
            return provider.lowercased()
        }

        if let issuer = (json["iss"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           issuer == "accounts.google.com" || issuer == "https://accounts.google.com" {
            return "google"
        }

        return nil
    }

    public var isGoogleLinked: Bool {
        tokenProvider == "google"
    }

    public var hasServerLinkedProfile: Bool {
        isGoogleLinked &&
            !babyID.isEmpty &&
            !babyID.lowercased().hasPrefix("offline_")
    }
}
