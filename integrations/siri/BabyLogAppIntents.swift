import AppIntents
import Foundation

enum BabyLogTone: String, AppEnum {
    case friendly
    case neutral
    case formal
    case brief
    case coach

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "AI Tone")
    static var caseDisplayRepresentations: [BabyLogTone: DisplayRepresentation] = [
        .friendly: "친근",
        .neutral: "중립",
        .formal: "격식",
        .brief: "한 줄",
        .coach: "코치형",
    ]
}

struct SiriBackendClient {
    let baseURL: URL

    func execute(intentName: String, babyId: String, tone: BabyLogTone) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/v1/assistants/siri/\(intentName)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "baby_id": babyId,
            "tone": tone.rawValue,
        ])

        let (data, _) = try await URLSession.shared.data(for: request)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return decoded?["dialog"] as? String ?? "응답을 가져오지 못했습니다."
    }
}

struct GetLastPooTimeIntent: AppIntent {
    static var title: LocalizedStringResource = "마지막 대변 시간"
    static var description = IntentDescription("아기의 마지막 대변 기록 시각을 조회합니다.")

    @Parameter(title: "아기 ID")
    var babyId: String

    @Parameter(title: "톤")
    var tone: BabyLogTone

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let client = SiriBackendClient(baseURL: URL(string: "https://api.babylog.ai")!)
        let dialog = try await client.execute(intentName: "GetLastPooTime", babyId: babyId, tone: tone)
        return .result(dialog: "\(dialog)")
    }
}

struct GetNextFeedingEtaIntent: AppIntent {
    static var title: LocalizedStringResource = "다음 수유 ETA"
    static var description = IntentDescription("최근 수유 텀 평균 기반으로 다음 수유 ETA를 조회합니다.")

    @Parameter(title: "아기 ID")
    var babyId: String

    @Parameter(title: "톤")
    var tone: BabyLogTone

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let client = SiriBackendClient(baseURL: URL(string: "https://api.babylog.ai")!)
        let dialog = try await client.execute(intentName: "GetNextFeedingEta", babyId: babyId, tone: tone)
        return .result(dialog: "\(dialog)")
    }
}

struct GetTodaySummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "오늘 요약"
    static var description = IntentDescription("오늘의 수유/수면/배변 요약을 조회합니다.")

    @Parameter(title: "아기 ID")
    var babyId: String

    @Parameter(title: "톤")
    var tone: BabyLogTone

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let client = SiriBackendClient(baseURL: URL(string: "https://api.babylog.ai")!)
        let dialog = try await client.execute(intentName: "GetTodaySummary", babyId: babyId, tone: tone)
        return .result(dialog: "\(dialog)")
    }
}

struct StartRecordFlowIntent: AppIntent {
    static var title: LocalizedStringResource = "기록 시작"
    static var description = IntentDescription("앱 내 음성 기록 플로우를 시작합니다.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        return .result(dialog: "기록 화면을 열었습니다.")
    }
}

