import SwiftUI

public struct ChatGlassView: View {
    @State private var mode: ChatDateMode = .day
    @State private var prompt = ""
    @State private var usePersonalData = true

    public init() {}

    public var body: some View {
        BabyAIGlassScreenFrame(title: "Chat") {
            VStack(alignment: .leading, spacing: 10) {
                BabyAIGlassSectionHeader("Scope", subtitle: "day / week / month + anchor_date + tz_offset")
                Picker("Mode", selection: $mode) {
                    Text("Day").tag(ChatDateMode.day)
                    Text("Week").tag(ChatDateMode.week)
                    Text("Month").tag(ChatDateMode.month)
                }
                .pickerStyle(.segmented)

                BabyAIGlassToggleRow(
                    title: "Use Personal Data",
                    subtitle: "chat/query -> use_personal_data",
                    isOn: $usePersonalData
                )
            }
            .babyAIGlassCard(cornerRadius: 24)

            VStack(alignment: .leading, spacing: 10) {
                BabyAIGlassSectionHeader("Session", subtitle: "create/list/messages/query")
                ForEach(sampleMessages, id: \.id) { message in
                    HStack {
                        if message.role == "assistant" {
                            Image(systemName: "sparkles")
                                .foregroundStyle(BabyAIGlassPalette.accent)
                        }
                        Text(message.content)
                            .font(.subheadline)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: message.role == "assistant" ? .leading : .trailing)
                    .babyAIGlassInset(cornerRadius: 14)
                }
            }
            .babyAIGlassCard(cornerRadius: 24)

            VStack(alignment: .leading, spacing: 10) {
                BabyAIGlassSectionHeader("Composer")
                BabyAIGlassInputRow(title: "Prompt", text: $prompt, prompt: "Ask BabyAI")
                HStack(spacing: 10) {
                    Button("Send") {}
                        .babyAIGlassPrimaryButtonStyle()
                    Button {
                    } label: {
                        Label("Voice", systemImage: "mic.fill")
                    }
                    .babyAIGlassSecondaryButtonStyle()
                }
                Text("STT requires NSSpeechRecognitionUsageDescription + NSMicrophoneUsageDescription")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .babyAIGlassCard(cornerRadius: 24)
        }
    }

    private var sampleMessages: [(id: String, role: String, content: String)] {
        [
            ("1", "user", "오늘 수유 패턴 요약해줘"),
            ("2", "assistant", "최근 24시간 기준 수유 6회, 평균 간격 3시간 5분입니다."),
        ]
    }
}
