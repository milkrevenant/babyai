import Foundation

public struct AssistantActionPayload: Sendable, Equatable {
    public var feature: String?
    public var query: String?
    public var memo: String?
    public var diaperType: String?
    public var amountML: Int?
    public var durationMin: Int?
    public var grams: Int?
    public var dose: Int?
    public var source: String?

    public init(
        feature: String? = nil,
        query: String? = nil,
        memo: String? = nil,
        diaperType: String? = nil,
        amountML: Int? = nil,
        durationMin: Int? = nil,
        grams: Int? = nil,
        dose: Int? = nil,
        source: String? = nil
    ) {
        self.feature = feature
        self.query = query
        self.memo = memo
        self.diaperType = diaperType
        self.amountML = amountML
        self.durationMin = durationMin
        self.grams = grams
        self.dose = dose
        self.source = source
    }

    public var isEmpty: Bool {
        let hasText = [feature, query, memo].contains { value in
            guard let value else {
                return false
            }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !hasText && diaperType == nil && amountML == nil && durationMin == nil && grams == nil && dose == nil
    }

    public var prefillMap: JSONObject {
        var out: JSONObject = [:]
        if let query { out["query"] = .string(query) }
        if let memo { out["memo"] = .string(memo) }
        if let diaperType { out["diaper_type"] = .string(diaperType) }
        if let amountML { out["amount_ml"] = .number(Double(amountML)) }
        if let durationMin { out["duration_min"] = .number(Double(durationMin)) }
        if let grams { out["grams"] = .number(Double(grams)) }
        if let dose { out["dose"] = .number(Double(dose)) }
        return out
    }
}

public enum AssistantURLBridge {
    public static func parse(url: URL) -> AssistantActionPayload? {
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

        let items = components.queryItems ?? []
        func queryValue(_ keys: [String]) -> String? {
            for key in keys {
                if let value = items.first(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame })?.value {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }
            }
            return nil
        }

        func parsePositiveInt(_ raw: String?) -> Int? {
            guard let raw, let value = Int(raw), value > 0 else {
                return nil
            }
            return value
        }

        let payload = AssistantActionPayload(
            feature: queryValue(["feature", "app_feature"])?.lowercased(),
            query: queryValue(["query", "utterance", "text", "prompt"]),
            memo: queryValue(["memo", "note", "content"]),
            diaperType: queryValue(["diaper_type", "diaperType"]),
            amountML: parsePositiveInt(queryValue(["amount_ml", "amountMl", "amount"])),
            durationMin: parsePositiveInt(queryValue(["duration_min", "durationMin", "duration"])),
            grams: parsePositiveInt(queryValue(["grams", "amount_g", "amountG"])),
            dose: parsePositiveInt(queryValue(["dose", "dose_mg", "doseMg"])),
            source: queryValue(["source"])?.lowercased() ?? "assistant"
        )

        return payload.isEmpty ? nil : payload
    }

    public static func buildURL(
        query: String?,
        feature: String?,
        amountML: Int? = nil,
        durationMin: Int? = nil,
        diaperType: String? = nil,
        source: String = "siri"
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "babyai"
        components.host = "assistant"
        components.path = "/query"

        var items: [URLQueryItem] = [URLQueryItem(name: "source", value: source)]
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
