import Foundation

public struct OfflineOnboardingProfile: Sendable {
    public var babyName: String
    public var babyBirthDate: String
    public var babySex: String
    public var babyWeightKg: Double?
    public var feedingMethod: String
    public var formulaBrand: String
    public var formulaProduct: String
    public var formulaType: String
    public var formulaContainsStarch: Bool

    public init(
        babyName: String,
        babyBirthDate: String,
        babySex: String,
        babyWeightKg: Double? = nil,
        feedingMethod: String,
        formulaBrand: String,
        formulaProduct: String,
        formulaType: String,
        formulaContainsStarch: Bool
    ) {
        self.babyName = babyName
        self.babyBirthDate = babyBirthDate
        self.babySex = babySex
        self.babyWeightKg = babyWeightKg
        self.feedingMethod = feedingMethod
        self.formulaBrand = formulaBrand
        self.formulaProduct = formulaProduct
        self.formulaType = formulaType
        self.formulaContainsStarch = formulaContainsStarch
    }
}

public actor OnboardingSyncCoordinator {
    private let apiClient: BabyAIApiClient
    private let sessionStore: SessionStore
    private let offlineStore: OfflineDataStore

    private let babyProfileNamespace = "baby_profile"

    public init(
        apiClient: BabyAIApiClient,
        sessionStore: SessionStore,
        offlineStore: OfflineDataStore
    ) {
        self.apiClient = apiClient
        self.sessionStore = sessionStore
        self.offlineStore = offlineStore
    }

    @discardableResult
    public func createOfflineOnboarding(_ profile: OfflineOnboardingProfile) async throws -> SessionCredentials {
        let offlineBabyID = "offline_baby_\(UInt64(Date().timeIntervalSince1970 * 1_000_000))"
        let offlineHouseholdID = "offline_household_\(UInt64(Date().timeIntervalSince1970 * 1_000_000))"

        var credentials = try await sessionStore.load()
        credentials.babyID = offlineBabyID
        credentials.householdID = offlineHouseholdID
        try await sessionStore.persist(credentials)

        let payload = buildOfflineProfilePayload(babyID: offlineBabyID, profile: profile)
        try await offlineStore.writeCache(
            namespace: babyProfileNamespace,
            babyID: offlineBabyID,
            key: "profile",
            data: payload
        )

        return credentials
    }

    @discardableResult
    public func syncOnboardingParentIfGoogleLinked(_ request: OnboardingParentRequest) async throws -> JSONObject? {
        let current = try await sessionStore.load()
        if !current.isGoogleLinked {
            return nil
        }

        let response = try await apiClient.onboardingParent(request)
        let nextBabyID = response.string("baby_id") ?? ""
        let nextHouseholdID = response.string("household_id") ?? ""

        if !nextBabyID.isEmpty || !nextHouseholdID.isEmpty {
            try await sessionStore.setRuntimeIDs(
                babyID: nextBabyID.isEmpty ? nil : nextBabyID,
                householdID: nextHouseholdID.isEmpty ? nil : nextHouseholdID,
                albumID: nil
            )
        }

        return response
    }

    private func buildOfflineProfilePayload(babyID: String, profile: OfflineOnboardingProfile) -> JSONObject {
        let now = Date()
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"

        let birthDate = formatter.date(from: profile.babyBirthDate) ?? now
        let ageDays = max(0, Calendar.current.dateComponents([.day], from: birthDate, to: now).day ?? 0)

        let formulaDisplay = [profile.formulaBrand, profile.formulaProduct]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return [
            "baby_id": .string(babyID),
            "baby_name": .string(profile.babyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "우리 아기" : profile.babyName),
            "birth_date": .string(profile.babyBirthDate),
            "age_days": .number(Double(ageDays)),
            "sex": .string(profile.babySex.isEmpty ? "unknown" : profile.babySex),
            "weight_kg": profile.babyWeightKg.map(JSONValue.number) ?? .null,
            "feeding_method": .string(profile.feedingMethod.isEmpty ? "mixed" : profile.feedingMethod),
            "formula_brand": .string(profile.formulaBrand),
            "formula_product": .string(profile.formulaProduct),
            "formula_type": .string(profile.formulaType.isEmpty ? "standard" : profile.formulaType),
            "formula_contains_starch": .bool(profile.formulaContainsStarch),
            "formula_display_name": .string(formulaDisplay.isEmpty ? "기본 분유" : formulaDisplay),
            "recommended_formula_daily_ml": .null,
            "recommended_formula_per_feed_ml": .null,
            "recommended_feed_interval_min": .number(180),
            "recommended_next_feeding_time": .null,
            "recommended_next_feeding_in_min": .null,
            "recommendation_reference_text": .string(""),
            "recommendation_note": .string(""),
            "formula_catalog": .array([]),
            "offline_cached": .bool(true),
        ]
    }
}
