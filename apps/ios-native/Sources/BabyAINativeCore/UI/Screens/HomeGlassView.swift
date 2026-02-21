import SwiftUI

public struct HomeGlassView: View {
    @State private var formulaML = "140"
    @State private var memoText = ""
    @State private var timerRunning = false

    public init() {}

    public var body: some View {
        BabyAIGlassScreenFrame(title: "Home") {
            BabyAIGlassSectionHeader("Quick Record", subtitle: "createClosed / startOnly / completeOpen")

            BabyAIGlassActionGrid(items: [
                .init(title: "Formula", systemImage: "drop.fill", action: {}),
                .init(title: "Breast", systemImage: "heart.fill", action: {}),
                .init(title: "Sleep", systemImage: "moon.fill", action: {}),
                .init(title: "Diaper", systemImage: "figure.and.child.holdinghands", action: {}),
                .init(title: "Medication", systemImage: "pills.fill", action: {}),
                .init(title: "Memo", systemImage: "note.text", action: {}),
            ])
            .babyAIGlassCard(cornerRadius: 24)

            VStack(alignment: .leading, spacing: 10) {
                BabyAIGlassSectionHeader("Manual Input")
                BabyAIGlassInputRow(title: "Formula (ml)", text: $formulaML, prompt: "e.g. 120")
                BabyAIGlassInputRow(title: "Memo", text: $memoText, prompt: "special memo")
                HStack(spacing: 10) {
                    Button("Create Closed") {}
                        .babyAIGlassPrimaryButtonStyle()
                    Button(timerRunning ? "Complete Open" : "Start Only") {
                        timerRunning.toggle()
                    }
                    .babyAIGlassSecondaryButtonStyle()
                }
            }
            .babyAIGlassCard()

            VStack(alignment: .leading, spacing: 10) {
                BabyAIGlassSectionHeader("Open Events", subtitle: "GET /events/open")
                ForEach(sampleOpenEvents, id: \.id) { event in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.type)
                                .font(.subheadline.weight(.semibold))
                            Text(event.start)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        BabyAIGlassTag("OPEN", color: BabyAIGlassPalette.warning)
                    }
                    .babyAIGlassInset(cornerRadius: 16)
                }
            }
            .babyAIGlassCard(cornerRadius: 24)

            HStack(spacing: 10) {
                BabyAIGlassTag("offline queue", color: BabyAIGlassPalette.positive)
                Text("event_create_closed / start / complete / update / cancel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .babyAIGlassCard(cornerRadius: 20)
        }
    }

    private var sampleOpenEvents: [(id: String, type: String, start: String)] {
        [
            ("1", "SLEEP", "2026-02-21T12:08:00Z"),
            ("2", "FORMULA", "2026-02-21T13:31:00Z"),
        ]
    }
}
