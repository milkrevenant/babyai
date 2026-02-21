import Foundation

public actor OfflineMutationSyncCoordinator {
    private let apiClient: BabyAIApiClient
    private let sessionStore: SessionStore
    private let offlineStore: OfflineDataStore

    private var syncInProgress = false

    private let mapNamespace = "sync_event_ids"
    private let mapCacheKey = "event_id_map"

    public init(
        apiClient: BabyAIApiClient,
        sessionStore: SessionStore,
        offlineStore: OfflineDataStore
    ) {
        self.apiClient = apiClient
        self.sessionStore = sessionStore
        self.offlineStore = offlineStore
    }

    public func flush() async throws {
        if syncInProgress {
            return
        }

        let credentials = try await sessionStore.load()
        if !credentials.hasServerLinkedProfile {
            return
        }
        let babyID = credentials.babyID

        syncInProgress = true
        defer { syncInProgress = false }

        var eventIDMap = try await readEventIDMap(babyID: babyID)
        var mapChanged = false

        let mutations = try await offlineStore.listMutations()
        for mutation in mutations {
            do {
                try await applyMutation(mutation, eventIDMap: &eventIDMap)
                try await offlineStore.removeMutation(id: mutation.id)
                mapChanged = true
            } catch let error as BabyAIError {
                if case .transport = error {
                    break
                }
                break
            } catch {
                break
            }
        }

        if mapChanged {
            try await writeEventIDMap(eventIDMap, babyID: babyID)
        }
    }

    private func applyMutation(
        _ mutation: OfflineMutation,
        eventIDMap: inout [String: String]
    ) async throws {
        let payload = mutation.payload
        switch mutation.kind {
        case .eventCreateClosed:
            let babyID = payload.string("baby_id") ?? ""
            let type = payload.string("type") ?? ""
            let startTime = payloadDate(payload, key: "start_time") ?? Date()
            let endTime = payloadDate(payload, key: "end_time")
            let value = payload.object("value") ?? [:]
            let metadata = payload.object("metadata")

            let response = try await apiClient.createManualEvent(
                ManualEventCreateRequest(
                    babyID: babyID,
                    type: type,
                    startTime: startTime,
                    endTime: endTime,
                    value: value,
                    metadata: metadata
                )
            )
            if let localID = payload.string("event_id"),
               let remoteID = response.string("event_id"),
               localID.hasPrefix("local-") {
                eventIDMap[localID] = remoteID
            }

        case .eventStart:
            let babyID = payload.string("baby_id") ?? ""
            let type = payload.string("type") ?? ""
            let startTime = payloadDate(payload, key: "start_time") ?? Date()
            let value = payload.object("value") ?? [:]
            let metadata = payload.object("metadata")

            let response = try await apiClient.startManualEvent(
                ManualEventStartRequest(
                    babyID: babyID,
                    type: type,
                    startTime: startTime,
                    value: value,
                    metadata: metadata
                )
            )
            if let localID = payload.string("event_id"),
               let remoteID = response.string("event_id"),
               localID.hasPrefix("local-") {
                eventIDMap[localID] = remoteID
            }

        case .eventComplete:
            let rawID = payload.string("event_id") ?? ""
            let resolvedID = resolvedRemoteEventID(rawID, eventIDMap: eventIDMap)
            let endTime = payloadDate(payload, key: "end_time")
            let value = payload.object("value")
            let metadata = payload.object("metadata")

            _ = try await apiClient.completeManualEvent(
                eventID: resolvedID,
                ManualEventCompleteRequest(endTime: endTime, value: value, metadata: metadata)
            )

        case .eventUpdate:
            let rawID = payload.string("event_id") ?? ""
            let resolvedID = resolvedRemoteEventID(rawID, eventIDMap: eventIDMap)
            let type = payload.string("type")
            let startTime = payloadDate(payload, key: "start_time")
            let endTime = payloadDate(payload, key: "end_time")
            let value = payload.object("value")
            let metadata = payload.object("metadata")

            _ = try await apiClient.updateManualEvent(
                eventID: resolvedID,
                ManualEventUpdateRequest(
                    type: type,
                    startTime: startTime,
                    endTime: endTime,
                    value: value,
                    metadata: metadata
                )
            )

        case .eventCancel:
            let rawID = payload.string("event_id") ?? ""
            let resolvedID = resolvedRemoteEventID(rawID, eventIDMap: eventIDMap)
            _ = try await apiClient.cancelManualEvent(eventID: resolvedID, reason: payload.string("reason"))
        }
    }

    private func resolvedRemoteEventID(_ rawID: String, eventIDMap: [String: String]) -> String {
        let trimmed = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        if let mapped = eventIDMap[trimmed], !mapped.isEmpty {
            return mapped
        }
        return trimmed
    }

    private func readEventIDMap(babyID: String) async throws -> [String: String] {
        guard let cached = try await offlineStore.readCache(namespace: mapNamespace, babyID: babyID, key: mapCacheKey) else {
            return [:]
        }
        guard let mappingObject = cached.object("mapping") else {
            return [:]
        }

        var out: [String: String] = [:]
        for (key, value) in mappingObject {
            if let remote = value.stringValue, !remote.isEmpty {
                out[key] = remote
            }
        }
        return out
    }

    private func writeEventIDMap(_ map: [String: String], babyID: String) async throws {
        let mapping = map.mapValues { JSONValue.string($0) }
        try await offlineStore.writeCache(
            namespace: mapNamespace,
            babyID: babyID,
            key: mapCacheKey,
            data: ["mapping": .object(mapping)]
        )
    }

    private func payloadDate(_ payload: JSONObject, key: String) -> Date? {
        guard let text = payload.string(key)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) {
            return date
        }
        return nil
    }
}
