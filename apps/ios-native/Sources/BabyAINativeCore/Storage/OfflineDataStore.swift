import Foundation

public enum OfflineMutationKind: String, Codable, Sendable, CaseIterable {
    case eventCreateClosed = "event_create_closed"
    case eventStart = "event_start"
    case eventComplete = "event_complete"
    case eventUpdate = "event_update"
    case eventCancel = "event_cancel"
}

public struct OfflineMutation: Codable, Sendable, Equatable {
    public let id: String
    public let kind: OfflineMutationKind
    public let payload: JSONObject
    public let queuedAt: Date

    public init(id: String, kind: OfflineMutationKind, payload: JSONObject, queuedAt: Date) {
        self.id = id
        self.kind = kind
        self.payload = payload
        self.queuedAt = queuedAt
    }
}

public struct OfflineCacheEntry: Codable, Sendable, Equatable {
    public let savedAt: Date
    public let data: JSONObject

    public init(savedAt: Date, data: JSONObject) {
        self.savedAt = savedAt
        self.data = data
    }
}

private struct OfflineStoreState: Codable, Sendable {
    var caches: [String: OfflineCacheEntry]
    var mutations: [OfflineMutation]

    static let empty = OfflineStoreState(caches: [:], mutations: [])
}

public actor OfflineDataStore {
    private let fileStore: ProtectedFileStore
    private let fileName: String
    private var loaded = false
    private var state: OfflineStoreState = .empty

    public init(
        fileStore: ProtectedFileStore = ProtectedFileStore(),
        fileName: String = "babyai_offline_store.json"
    ) {
        self.fileStore = fileStore
        self.fileName = fileName
    }

    public func readCache(
        namespace: String,
        babyID: String,
        key: String
    ) async throws -> JSONObject? {
        try await ensureLoaded()
        return state.caches[cacheKey(namespace: namespace, babyID: babyID, key: key)]?.data
    }

    public func writeCache(
        namespace: String,
        babyID: String,
        key: String,
        data: JSONObject
    ) async throws {
        try await ensureLoaded()
        state.caches[cacheKey(namespace: namespace, babyID: babyID, key: key)] = OfflineCacheEntry(
            savedAt: Date(),
            data: data
        )
        try persist()
    }

    public func enqueueMutation(
        kind: OfflineMutationKind,
        payload: JSONObject,
        id: String? = nil
    ) async throws {
        try await ensureLoaded()
        let mutation = OfflineMutation(
            id: id ?? "m-\(UInt64(Date().timeIntervalSince1970 * 1_000_000))",
            kind: kind,
            payload: payload,
            queuedAt: Date()
        )
        state.mutations.append(mutation)
        try persist()
    }

    public func listMutations() async throws -> [OfflineMutation] {
        try await ensureLoaded()
        return state.mutations
    }

    public func removeMutation(id: String) async throws {
        try await ensureLoaded()
        state.mutations.removeAll { $0.id == id }
        try persist()
    }

    public func clearAll() async throws {
        state = .empty
        loaded = true
        try persist()
    }

    private func cacheKey(namespace: String, babyID: String, key: String) -> String {
        "\(namespace.trimmingCharacters(in: .whitespacesAndNewlines))::\(babyID.trimmingCharacters(in: .whitespacesAndNewlines))::\(key.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    private func ensureLoaded() async throws {
        if loaded {
            return
        }
        loaded = true
        guard let data = try fileStore.read(fileName: fileName) else {
            state = .empty
            return
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            state = try decoder.decode(OfflineStoreState.self, from: data)
        } catch {
            state = .empty
        }
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        try fileStore.write(data, fileName: fileName)
    }
}
