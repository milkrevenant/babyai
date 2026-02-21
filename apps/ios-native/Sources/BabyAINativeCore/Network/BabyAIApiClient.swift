import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
}

public actor BabyAIApiClient {
    private let environment: AppEnvironment
    private let sessionStore: SessionStore
    private let urlSession: URLSession
    private let additionalHeaders: [String: String]

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        environment: AppEnvironment,
        sessionStore: SessionStore,
        urlSession: URLSession = .shared,
        additionalHeaders: [String: String] = [:]
    ) {
        self.environment = environment
        self.sessionStore = sessionStore
        self.urlSession = urlSession
        self.additionalHeaders = additionalHeaders

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    public func health() async throws -> JSONObject {
        try await requestJSON(path: "/health", method: .get, requiresAuth: false)
    }

    public func issueLocalDevToken(
        sub: String,
        name: String,
        provider: String
    ) async throws -> JSONObject {
        struct Payload: Codable {
            let sub: String
            let name: String
            let provider: String
        }
        return try await requestJSON(
            path: "/dev/local-token",
            method: .post,
            body: Payload(sub: sub, name: name, provider: provider),
            requiresAuth: false
        )
    }

    public func testLogin(email: String, password: String, name: String? = nil) async throws -> JSONObject {
        struct Payload: Codable {
            let email: String
            let password: String
            let name: String?
        }
        return try await requestJSON(
            path: "/auth/test-login",
            method: .post,
            body: Payload(email: email, password: password, name: name),
            requiresAuth: false
        )
    }

    public func onboardingParent(_ request: OnboardingParentRequest) async throws -> JSONObject {
        try await requestJSON(path: "/api/v1/onboarding/parent", method: .post, body: request)
    }

    public func parseVoice(transcriptHint: String? = nil, babyID: String? = nil) async throws -> JSONObject {
        let resolvedBabyID = try await requireBabyID(explicit: babyID)
        struct Payload: Codable {
            let babyID: String
            let transcriptHint: String?
        }
        return try await requestJSON(
            path: "/api/v1/events/voice",
            method: .post,
            body: Payload(babyID: resolvedBabyID, transcriptHint: transcriptHint)
        )
    }

    public func confirmVoiceEvents(clipID: String, events: [JSONObject]) async throws -> JSONObject {
        struct Payload: Codable {
            let clipID: String
            let events: [JSONObject]
        }
        return try await requestJSON(
            path: "/api/v1/events/confirm",
            method: .post,
            body: Payload(clipID: clipID, events: events)
        )
    }

    public func createManualEvent(_ request: ManualEventCreateRequest) async throws -> JSONObject {
        try await requestJSON(path: "/api/v1/events/manual", method: .post, body: request)
    }

    public func startManualEvent(_ request: ManualEventStartRequest) async throws -> JSONObject {
        try await requestJSON(path: "/api/v1/events/start", method: .post, body: request)
    }

    public func completeManualEvent(eventID: String, _ request: ManualEventCompleteRequest) async throws -> JSONObject {
        let path = "/api/v1/events/\(urlPathComponent(eventID))/complete"
        return try await requestJSON(path: path, method: .patch, body: request)
    }

    public func updateManualEvent(eventID: String, _ request: ManualEventUpdateRequest) async throws -> JSONObject {
        let path = "/api/v1/events/\(urlPathComponent(eventID))"
        return try await requestJSON(path: path, method: .patch, body: request)
    }

    public func cancelManualEvent(eventID: String, reason: String? = nil) async throws -> JSONObject {
        let path = "/api/v1/events/\(urlPathComponent(eventID))/cancel"
        return try await requestJSON(path: path, method: .patch, body: ManualEventCancelRequest(reason: reason))
    }

    public func listOpenEvents(babyID: String? = nil, type: String? = nil) async throws -> JSONObject {
        let resolvedBabyID = try await requireBabyID(explicit: babyID)
        return try await requestJSON(
            path: "/api/v1/events/open",
            method: .get,
            query: [
                "baby_id": resolvedBabyID,
                "type": type,
            ]
        )
    }

    public func getMySettings() async throws -> JSONObject {
        try await requestJSON(path: "/api/v1/settings/me", method: .get)
    }

    public func upsertMySettings(_ payload: JSONObject) async throws -> JSONObject {
        try await requestJSON(path: "/api/v1/settings/me", method: .patch, body: payload)
    }

    public func exportDataCSV(babyID: String? = nil) async throws -> Data {
        let resolvedBabyID = try await requireBabyID(explicit: babyID)
        return try await requestData(
            path: "/api/v1/data/export.csv",
            method: .get,
            query: ["baby_id": resolvedBabyID]
        )
    }

    public func getBabyProfile(babyID: String? = nil) async throws -> JSONObject {
        let resolvedBabyID = try await requireBabyID(explicit: babyID)
        return try await requestJSON(
            path: "/api/v1/babies/profile",
            method: .get,
            query: ["baby_id": resolvedBabyID]
        )
    }

    public func upsertBabyProfile(_ payload: JSONObject) async throws -> JSONObject {
        try await requestJSON(path: "/api/v1/babies/profile", method: .patch, body: payload)
    }

    public func quickLastPooTime(babyID: String? = nil, tone: String = "neutral") async throws -> JSONObject {
        let resolvedBabyID = try await requireBabyID(explicit: babyID)
        return try await requestJSON(
            path: "/api/v1/quick/last-poo-time",
            method: .get,
            query: [
                "baby_id": resolvedBabyID,
                "tone": tone,
                "tz_offset": DateScope.timezoneOffsetString(referenceDate: Date()),
            ]
        )
    }

    public func quickNextFeedingETA(babyID: String? = nil, tone: String = "neutral") async throws -> JSONObject {
        let resolvedBabyID = try await requireBabyID(explicit: babyID)
        return try await requestJSON(
            path: "/api/v1/quick/next-feeding-eta",
            method: .get,
            query: [
                "baby_id": resolvedBabyID,
                "tone": tone,
                "tz_offset": DateScope.timezoneOffsetString(referenceDate: Date()),
            ]
        )
    }

    public func quickTodaySummary(babyID: String? = nil) async throws -> JSONObject {
        let resolvedBabyID = try await requireBabyID(explicit: babyID)
        return try await requestJSON(
            path: "/api/v1/quick/today-summary",
            method: .get,
            query: [
                "baby_id": resolvedBabyID,
                "tz_offset": DateScope.timezoneOffsetString(referenceDate: Date()),
            ]
        )
    }

    public func quickLandingSnapshot(
        babyID: String? = nil,
        range: String = "day",
        anchorDate: Date? = nil
    ) async throws -> JSONObject {
        let resolvedBabyID = try await requireBabyID(explicit: babyID)
        let anchor = anchorDate.map { DateScope.ymdLocal($0) }
        return try await requestJSON(
            path: "/api/v1/quick/landing-snapshot",
            method: .get,
            query: [
                "baby_id": resolvedBabyID,
                "range": range,
                "anchor_date": anchor,
                "tz_offset": DateScope.timezoneOffsetString(referenceDate: Date()),
            ]
        )
    }

    public func aiQuery(
        question: String,
        babyID: String? = nil,
        tone: String = "neutral",
        usePersonalData: Bool = true
    ) async throws -> JSONObject {
        let resolvedBabyID = try await requireBabyID(explicit: babyID)
        return try await requestJSON(
            path: "/api/v1/ai/query",
            method: .post,
            body: AIQueryPayload(
                babyID: resolvedBabyID,
                question: question,
                tone: tone,
                usePersonalData: usePersonalData
            )
        )
    }

    public func createChatSession(childID: String? = nil) async throws -> JSONObject {
        let resolvedChildID = childID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? childID
            : try await requireBabyID(explicit: nil)
        return try await requestJSON(
            path: "/api/v1/chat/sessions",
            method: .post,
            body: ChatSessionCreateRequest(childID: resolvedChildID)
        )
    }

    public func listChatSessions(childID: String? = nil, limit: Int = 50) async throws -> JSONObject {
        let resolvedChildID = childID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? childID
            : try await requireBabyID(explicit: nil)

        return try await requestJSON(
            path: "/api/v1/chat/sessions",
            method: .get,
            query: [
                "child_id": resolvedChildID,
                "limit": String(max(1, min(100, limit))),
            ]
        )
    }

    public func createChatMessage(sessionID: String, request: ChatMessageCreateRequest) async throws -> JSONObject {
        let path = "/api/v1/chat/sessions/\(urlPathComponent(sessionID))/messages"
        return try await requestJSON(path: path, method: .post, body: request)
    }

    public func getChatMessages(sessionID: String) async throws -> JSONObject {
        let path = "/api/v1/chat/sessions/\(urlPathComponent(sessionID))/messages"
        return try await requestJSON(path: path, method: .get)
    }

    public func chatQuery(
        sessionID: String,
        query: String,
        tone: String = "neutral",
        usePersonalData: Bool = true,
        childID: String? = nil,
        dateMode: ChatDateMode = .day,
        anchorDate: Date = Date()
    ) async throws -> JSONObject {
        let resolvedChildID = childID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? childID
            : try await requireBabyID(explicit: nil)
        let localNoon = DateScope.localNoon(anchorDate)
        let payload = ChatQueryPayload(
            sessionID: sessionID,
            childID: resolvedChildID,
            query: query,
            tone: tone,
            usePersonalData: usePersonalData,
            dateMode: dateMode.rawValue,
            anchorDate: DateScope.ymdLocal(anchorDate),
            tzOffset: DateScope.timezoneOffsetString(referenceDate: localNoon)
        )
        return try await requestJSON(path: "/api/v1/chat/query", method: .post, body: payload)
    }

    public func dailyReport(date: Date, babyID: String? = nil) async throws -> JSONObject {
        let resolvedBabyID = try await requireBabyID(explicit: babyID)
        let localNoon = DateScope.localNoon(date)
        return try await requestJSON(
            path: "/api/v1/reports/daily",
            method: .get,
            query: [
                "baby_id": resolvedBabyID,
                "date": DateScope.ymdLocal(date),
                "tz_offset": DateScope.timezoneOffsetString(referenceDate: localNoon),
            ]
        )
    }

    public func weeklyReport(weekStart: Date, babyID: String? = nil) async throws -> JSONObject {
        let resolvedBabyID = try await requireBabyID(explicit: babyID)
        let start = DateScope.weekStartMonday(weekStart)
        let localNoon = DateScope.localNoon(start)
        return try await requestJSON(
            path: "/api/v1/reports/weekly",
            method: .get,
            query: [
                "baby_id": resolvedBabyID,
                "week_start": DateScope.ymdLocal(start),
                "tz_offset": DateScope.timezoneOffsetString(referenceDate: localNoon),
            ]
        )
    }

    public func monthlyReport(monthStart: Date, babyID: String? = nil) async throws -> JSONObject {
        let resolvedBabyID = try await requireBabyID(explicit: babyID)
        let start = DateScope.monthStart(monthStart)
        let localNoon = DateScope.localNoon(start)
        return try await requestJSON(
            path: "/api/v1/reports/monthly",
            method: .get,
            query: [
                "baby_id": resolvedBabyID,
                "month_start": DateScope.ymdLocal(start),
                "tz_offset": DateScope.timezoneOffsetString(referenceDate: localNoon),
            ]
        )
    }

    public func createPhotoUploadURL(albumID: String? = nil) async throws -> JSONObject {
        let resolvedAlbumID = try await requireAlbumID(explicit: albumID)
        return try await requestJSON(
            path: "/api/v1/photos/upload-url",
            method: .post,
            query: ["album_id": resolvedAlbumID]
        )
    }

    public func completePhotoUpload(
        objectKey: String,
        downloadable: Bool,
        albumID: String? = nil
    ) async throws -> JSONObject {
        let resolvedAlbumID = try await requireAlbumID(explicit: albumID)
        return try await requestJSON(
            path: "/api/v1/photos/complete",
            method: .post,
            body: PhotoCompletePayload(albumID: resolvedAlbumID, objectKey: objectKey, downloadable: downloadable)
        )
    }

    public func uploadPhotoFromDeviceRouteDrift() async throws -> JSONObject {
        throw BabyAIError.routeDrift(.photosUpload)
    }

    public func recentPhotosRouteDrift() async throws -> JSONObject {
        throw BabyAIError.routeDrift(.photosRecent)
    }

    public func quickLastFeedingRouteDrift() async throws -> JSONObject {
        throw BabyAIError.routeDrift(.quickLastFeeding)
    }

    public func quickRecentSleepRouteDrift() async throws -> JSONObject {
        throw BabyAIError.routeDrift(.quickRecentSleep)
    }

    public func quickLastDiaperRouteDrift() async throws -> JSONObject {
        throw BabyAIError.routeDrift(.quickLastDiaper)
    }

    public func quickLastMedicationRouteDrift() async throws -> JSONObject {
        throw BabyAIError.routeDrift(.quickLastMedication)
    }

    public func subscriptionMe(householdID: String? = nil) async throws -> JSONObject {
        let resolvedHouseholdID = try await requireHouseholdID(explicit: householdID)
        return try await requestJSON(
            path: "/api/v1/subscription/me",
            method: .get,
            query: ["household_id": resolvedHouseholdID]
        )
    }

    public func checkoutSubscription(plan: String, householdID: String? = nil) async throws -> JSONObject {
        let resolvedHouseholdID = try await requireHouseholdID(explicit: householdID)
        return try await requestJSON(
            path: "/api/v1/subscription/checkout",
            method: .post,
            body: SubscriptionCheckoutPayload(householdID: resolvedHouseholdID, plan: plan.uppercased())
        )
    }

    public func siriIntent(
        intentName: String,
        babyID: String? = nil,
        tone: String = "neutral"
    ) async throws -> JSONObject {
        let resolvedBabyID = try await requireBabyID(explicit: babyID)
        return try await requestJSON(
            path: "/api/v1/assistants/siri/\(urlPathComponent(intentName))",
            method: .post,
            body: SiriIntentPayload(babyID: resolvedBabyID, tone: tone)
        )
    }

    public func bixbyQuery(
        capsuleAction: String,
        babyID: String? = nil,
        tone: String = "neutral"
    ) async throws -> JSONObject {
        let resolvedBabyID = try await requireBabyID(explicit: babyID)
        return try await requestJSON(
            path: "/api/v1/assistants/bixby/query",
            method: .post,
            body: BixbyQueryPayload(capsuleAction: capsuleAction, babyID: resolvedBabyID, tone: tone)
        )
    }

    private func requestJSON(
        path: String,
        method: HTTPMethod,
        query: [String: String?] = [:],
        requiresAuth: Bool = true
    ) async throws -> JSONObject {
        try await requestJSON(path: path, method: method, query: query, bodyData: nil, requiresAuth: requiresAuth)
    }

    private func requestJSON<T: Encodable>(
        path: String,
        method: HTTPMethod,
        query: [String: String?] = [:],
        body: T,
        requiresAuth: Bool = true
    ) async throws -> JSONObject {
        let bodyData = try encoder.encode(body)
        return try await requestJSON(path: path, method: method, query: query, bodyData: bodyData, requiresAuth: requiresAuth)
    }

    private func requestJSON(
        path: String,
        method: HTTPMethod,
        query: [String: String?] = [:],
        bodyData: Data?,
        requiresAuth: Bool = true
    ) async throws -> JSONObject {
        let data = try await requestData(path: path, method: method, query: query, bodyData: bodyData, requiresAuth: requiresAuth)
        if data.isEmpty {
            return [:]
        }
        guard let object = try? decoder.decode(JSONObject.self, from: data) else {
            throw BabyAIError.invalidResponseShape
        }
        return object
    }

    private func requestData(
        path: String,
        method: HTTPMethod,
        query: [String: String?] = [:],
        bodyData: Data? = nil,
        requiresAuth: Bool = true
    ) async throws -> Data {
        let url = try makeURL(path: path, query: query)
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = environment.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if requiresAuth {
            let token = try await requireBearerToken()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let bodyData {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await urlSession.data(for: request)
        } catch {
            throw BabyAIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw BabyAIError.invalidResponseShape
        }

        guard (200 ... 299).contains(http.statusCode) else {
            throw BabyAIError.unexpectedStatusCode(http.statusCode, extractErrorMessage(from: responseData))
        }

        return responseData
    }

    private func makeURL(path: String, query: [String: String?]) throws -> URL {
        guard var components = URLComponents(url: environment.baseURL, resolvingAgainstBaseURL: false) else {
            throw BabyAIError.invalidURL
        }

        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = basePath + normalizedPath

        var items = components.queryItems ?? []
        for (key, value) in query {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            items.append(URLQueryItem(name: key, value: value))
        }
        components.queryItems = items.isEmpty ? nil : items

        guard let url = components.url else {
            throw BabyAIError.invalidURL
        }
        return url
    }

    private func extractErrorMessage(from data: Data) -> String? {
        if let object = try? decoder.decode(JSONObject.self, from: data) {
            return object.string("detail") ?? object.string("message") ?? object.string("error")
        }
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let text, !text.isEmpty {
            return text
        }
        return nil
    }

    private func urlPathComponent(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
    }

    private func requireBearerToken() async throws -> String {
        let credentials = try await sessionStore.load()
        let token = credentials.bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw BabyAIError.missingBearerToken
        }
        return token
    }

    private func requireBabyID(explicit: String?) async throws -> String {
        if let explicit = explicit?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            return explicit
        }
        let credentials = try await sessionStore.load()
        guard !credentials.babyID.isEmpty else {
            throw BabyAIError.missingBabyID
        }
        return credentials.babyID
    }

    private func requireHouseholdID(explicit: String?) async throws -> String {
        if let explicit = explicit?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            return explicit
        }
        let credentials = try await sessionStore.load()
        guard !credentials.householdID.isEmpty else {
            throw BabyAIError.missingHouseholdID
        }
        return credentials.householdID
    }

    private func requireAlbumID(explicit: String?) async throws -> String {
        if let explicit = explicit?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            return explicit
        }
        let credentials = try await sessionStore.load()
        guard !credentials.albumID.isEmpty else {
            throw BabyAIError.missingAlbumID
        }
        return credentials.albumID
    }
}
