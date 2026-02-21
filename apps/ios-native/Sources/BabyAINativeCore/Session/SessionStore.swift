import Foundation

public actor SessionStore {
    private let keychain: KeychainStore
    private let accountKey: String
    private var cached: SessionCredentials?

    public init(
        keychain: KeychainStore,
        accountKey: String = "session_credentials_v1"
    ) {
        self.keychain = keychain
        self.accountKey = accountKey
    }

    public init(serviceName: String = "babyai.native.session") {
        self.keychain = SystemKeychainStore(service: serviceName)
        self.accountKey = "session_credentials_v1"
    }

    public func load() throws -> SessionCredentials {
        if let cached {
            return cached
        }
        guard let raw = try keychain.readData(account: accountKey) else {
            let empty = SessionCredentials()
            cached = empty
            return empty
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let value = try decoder.decode(SessionCredentials.self, from: raw)
        cached = value
        return value
    }

    public func persist(_ next: SessionCredentials) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(next)
        try keychain.writeData(data, account: accountKey)
        cached = next
    }

    public func updateToken(_ token: String) throws {
        var value = try load()
        value.bearerToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        try persist(value)
    }

    public func setRuntimeIDs(
        babyID: String? = nil,
        householdID: String? = nil,
        albumID: String? = nil
    ) throws {
        var value = try load()
        if let babyID {
            value.babyID = babyID.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let householdID {
            value.householdID = householdID.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let albumID {
            value.albumID = albumID.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        try persist(value)
    }

    public func setPendingSleepStart(_ date: Date?) throws {
        var value = try load()
        value.pendingSleepStart = date
        try persist(value)
    }

    public func setPendingFormulaStart(_ date: Date?) throws {
        var value = try load()
        value.pendingFormulaStart = date
        try persist(value)
    }

    public func clear() throws {
        try keychain.deleteData(account: accountKey)
        cached = SessionCredentials()
    }
}
