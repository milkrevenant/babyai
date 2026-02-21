import SwiftUI

public struct MarketGlassView: View {
    public init() {}

    public var body: some View {
        BabyAIGlassScreenFrame(title: "Market") {
            BabyAIGlassSectionHeader("Plans", subtitle: "subscription/me + subscription/checkout")

            planCard(
                title: "AI_ONLY",
                price: "$4.99 / month",
                bullets: ["Chat sessions", "AI query", "Siri/Bixby assistant"],
                tint: BabyAIGlassPalette.accent
            )

            planCard(
                title: "AI_PHOTO",
                price: "$8.99 / month",
                bullets: ["All AI_ONLY features", "Photo upload-url flow", "Album sharing"],
                tint: BabyAIGlassPalette.accentStrong
            )

            VStack(alignment: .leading, spacing: 8) {
                BabyAIGlassSectionHeader("Route Drift Notice")
                Text("/photos/upload, /photos/recent are blocked until router contract is resolved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                BabyAIGlassTag("route drift blocked", color: BabyAIGlassPalette.warning)
            }
            .babyAIGlassCard(cornerRadius: 22)
        }
    }

    private func planCard(title: String, price: String, bullets: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                BabyAIGlassTag("TRIALING", color: tint)
            }
            Text(price)
                .font(.title3.weight(.bold))
                .foregroundStyle(BabyAIGlassPalette.textPrimary)

            ForEach(bullets, id: \.self) { bullet in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(tint)
                    Text(bullet)
                        .font(.subheadline)
                }
            }

            Button("Checkout") {}
                .babyAIGlassPrimaryButtonStyle()
        }
        .babyAIGlassCard(cornerRadius: 24)
    }
}
