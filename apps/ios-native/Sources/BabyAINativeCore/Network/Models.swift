import Foundation

public struct OnboardingParentRequest: Codable, Sendable {
    public var provider: String
    public var babyName: String
    public var babyBirthDate: String
    public var babySex: String
    public var babyWeightKg: Double?
    public var feedingMethod: String
    public var formulaBrand: String
    public var formulaProduct: String
    public var formulaType: String
    public var formulaContainsStarch: Bool?
    public var requiredConsents: [String]

    public init(
        provider: String,
        babyName: String,
        babyBirthDate: String,
        babySex: String,
        babyWeightKg: Double? = nil,
        feedingMethod: String,
        formulaBrand: String = "",
        formulaProduct: String = "",
        formulaType: String = "",
        formulaContainsStarch: Bool? = nil,
        requiredConsents: [String] = []
    ) {
        self.provider = provider
        self.babyName = babyName
        self.babyBirthDate = babyBirthDate
        self.babySex = babySex
        self.babyWeightKg = babyWeightKg
        self.feedingMethod = feedingMethod
        self.formulaBrand = formulaBrand
        self.formulaProduct = formulaProduct
        self.formulaType = formulaType
        self.formulaContainsStarch = formulaContainsStarch
        self.requiredConsents = requiredConsents
    }
}

public struct ManualEventCreateRequest: Codable, Sendable {
    public var babyID: String
    public var type: String
    public var startTime: Date
    public var endTime: Date?
    public var value: JSONObject
    public var metadata: JSONObject?

    public init(
        babyID: String,
        type: String,
        startTime: Date,
        endTime: Date? = nil,
        value: JSONObject = [:],
        metadata: JSONObject? = nil
    ) {
        self.babyID = babyID
        self.type = type
        self.startTime = startTime
        self.endTime = endTime
        self.value = value
        self.metadata = metadata
    }
}

public struct ManualEventStartRequest: Codable, Sendable {
    public var babyID: String
    public var type: String
    public var startTime: Date
    public var value: JSONObject
    public var metadata: JSONObject?

    public init(
        babyID: String,
        type: String,
        startTime: Date,
        value: JSONObject = [:],
        metadata: JSONObject? = nil
    ) {
        self.babyID = babyID
        self.type = type
        self.startTime = startTime
        self.value = value
        self.metadata = metadata
    }
}

public struct ManualEventUpdateRequest: Codable, Sendable {
    public var type: String?
    public var startTime: Date?
    public var endTime: Date?
    public var value: JSONObject?
    public var metadata: JSONObject?

    public init(
        type: String? = nil,
        startTime: Date? = nil,
        endTime: Date? = nil,
        value: JSONObject? = nil,
        metadata: JSONObject? = nil
    ) {
        self.type = type
        self.startTime = startTime
        self.endTime = endTime
        self.value = value
        self.metadata = metadata
    }
}

public struct ManualEventCompleteRequest: Codable, Sendable {
    public var endTime: Date?
    public var value: JSONObject?
    public var metadata: JSONObject?

    public init(endTime: Date? = nil, value: JSONObject? = nil, metadata: JSONObject? = nil) {
        self.endTime = endTime
        self.value = value
        self.metadata = metadata
    }
}

public struct ManualEventCancelRequest: Codable, Sendable {
    public var reason: String?

    public init(reason: String? = nil) {
        self.reason = reason
    }
}

public struct ChatSessionCreateRequest: Codable, Sendable {
    public var childID: String?

    public init(childID: String?) {
        self.childID = childID
    }
}

public struct ChatMessageCreateRequest: Codable, Sendable {
    public var role: String
    public var content: String
    public var intent: String?
    public var contextJSON: JSONObject?
    public var childID: String?

    public init(
        role: String,
        content: String,
        intent: String? = nil,
        contextJSON: JSONObject? = nil,
        childID: String? = nil
    ) {
        self.role = role
        self.content = content
        self.intent = intent
        self.contextJSON = contextJSON
        self.childID = childID
    }
}

public struct ChatQueryPayload: Codable, Sendable {
    public var sessionID: String
    public var childID: String?
    public var query: String
    public var tone: String
    public var usePersonalData: Bool
    public var dateMode: String
    public var anchorDate: String
    public var tzOffset: String

    public init(
        sessionID: String,
        childID: String? = nil,
        query: String,
        tone: String,
        usePersonalData: Bool,
        dateMode: String,
        anchorDate: String,
        tzOffset: String
    ) {
        self.sessionID = sessionID
        self.childID = childID
        self.query = query
        self.tone = tone
        self.usePersonalData = usePersonalData
        self.dateMode = dateMode
        self.anchorDate = anchorDate
        self.tzOffset = tzOffset
    }
}

public struct AIQueryPayload: Codable, Sendable {
    public var babyID: String
    public var question: String
    public var tone: String
    public var usePersonalData: Bool

    public init(
        babyID: String,
        question: String,
        tone: String,
        usePersonalData: Bool
    ) {
        self.babyID = babyID
        self.question = question
        self.tone = tone
        self.usePersonalData = usePersonalData
    }
}

public struct PhotoCompletePayload: Codable, Sendable {
    public var albumID: String
    public var objectKey: String
    public var downloadable: Bool

    public init(albumID: String, objectKey: String, downloadable: Bool) {
        self.albumID = albumID
        self.objectKey = objectKey
        self.downloadable = downloadable
    }
}

public struct SubscriptionCheckoutPayload: Codable, Sendable {
    public var householdID: String
    public var plan: String

    public init(householdID: String, plan: String) {
        self.householdID = householdID
        self.plan = plan
    }
}

public struct SiriIntentPayload: Codable, Sendable {
    public var babyID: String
    public var tone: String

    public init(babyID: String, tone: String = "neutral") {
        self.babyID = babyID
        self.tone = tone
    }
}

public struct BixbyQueryPayload: Codable, Sendable {
    public var capsuleAction: String
    public var babyID: String
    public var tone: String

    public init(capsuleAction: String, babyID: String, tone: String = "neutral") {
        self.capsuleAction = capsuleAction
        self.babyID = babyID
        self.tone = tone
    }
}
