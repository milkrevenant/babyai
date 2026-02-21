import SwiftUI

public struct StatisticsGlassView: View {
    private enum Range: String, CaseIterable, Hashable {
        case daily = "Daily"
        case weekly = "Weekly"
        case monthly = "Monthly"
    }

    @State private var range: Range = .daily

    public init() {}

    public var body: some View {
        BabyAIGlassScreenFrame(title: "Statistics") {
            VStack(alignment: .leading, spacing: 10) {
                BabyAIGlassSectionHeader("Report Range")
                Picker("Range", selection: $range) {
                    ForEach(Range.allCases, id: \.self) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .pickerStyle(.segmented)
            }
            .babyAIGlassCard(cornerRadius: 24)

            HStack(spacing: 10) {
                BabyAIGlassMetricCard(title: "Feedings", value: "6", trend: "+1 vs prev")
                BabyAIGlassMetricCard(title: "Sleep", value: "11h 42m", trend: "-18m vs prev")
            }

            HStack(spacing: 10) {
                BabyAIGlassMetricCard(title: "Pee", value: "7", trend: "stable")
                BabyAIGlassMetricCard(title: "Poo", value: "2", trend: "stable")
            }

            VStack(alignment: .leading, spacing: 10) {
                BabyAIGlassSectionHeader("Event Edit/Delete/Undo")
                HStack(spacing: 8) {
                    Button("Edit Time") {}
                        .babyAIGlassSecondaryButtonStyle()
                    Button("Delete") {}
                        .babyAIGlassSecondaryButtonStyle()
                    Button("Undo Delete") {}
                        .babyAIGlassPrimaryButtonStyle()
                }
                Text("Undo uses metadata.undo_delete=true on PATCH /events/{event_id}")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .babyAIGlassCard(cornerRadius: 24)

            VStack(alignment: .leading, spacing: 10) {
                BabyAIGlassSectionHeader("Trend Preview")
                ForEach(0..<5, id: \.self) { idx in
                    HStack(spacing: 8) {
                        Text("D\(idx + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .leading)
                        Capsule()
                            .fill(BabyAIGlassPalette.accent.opacity(0.5))
                            .frame(height: 10)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(BabyAIGlassPalette.accent)
                                    .frame(width: CGFloat(70 + idx * 26), height: 10)
                            }
                    }
                }
            }
            .babyAIGlassCard(cornerRadius: 24)
        }
    }
}
