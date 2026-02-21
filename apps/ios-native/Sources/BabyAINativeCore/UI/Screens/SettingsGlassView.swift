import SwiftUI

public struct SettingsGlassView: View {
    @State private var language = "ko"
    @State private var themeMode = "system"
    @State private var showStatisticsTab = true
    @State private var showChatTab = true
    @State private var showMarketTab = true
    @State private var showCommunityTab = true
    @State private var showPhotosTab = false

    public init() {}

    public var body: some View {
        BabyAIGlassScreenFrame(title: "Settings") {
            VStack(alignment: .leading, spacing: 10) {
                BabyAIGlassSectionHeader("Personalization")
                pickerRow(title: "Language", selection: $language, options: ["ko", "en", "es"])
                pickerRow(title: "Theme", selection: $themeMode, options: ["system", "light", "dark"])
            }
            .babyAIGlassCard(cornerRadius: 24)

            VStack(alignment: .leading, spacing: 10) {
                BabyAIGlassSectionHeader("Bottom Menu", subtitle: "photos index is settings alias")
                BabyAIGlassToggleRow(title: "Chat", isOn: $showChatTab)
                BabyAIGlassToggleRow(title: "Statistics", isOn: $showStatisticsTab)
                BabyAIGlassToggleRow(title: "Market", isOn: $showMarketTab)
                BabyAIGlassToggleRow(title: "Community", isOn: $showCommunityTab)
                BabyAIGlassToggleRow(title: "Photos", subtitle: "Keep off to match current Flutter behavior", isOn: $showPhotosTab)
            }
            .babyAIGlassCard(cornerRadius: 24)

            VStack(alignment: .leading, spacing: 10) {
                BabyAIGlassSectionHeader("Account & Child Profile")
                HStack(spacing: 10) {
                    Button("Edit Baby Profile") {}
                        .babyAIGlassSecondaryButtonStyle()
                    Button("Subscription") {}
                        .babyAIGlassSecondaryButtonStyle()
                }
                Button("Export CSV") {}
                    .babyAIGlassPrimaryButtonStyle()
            }
            .babyAIGlassCard(cornerRadius: 24)
        }
    }

    private func pickerRow(
        title: String,
        selection: Binding<String>,
        options: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
        .babyAIGlassInset(cornerRadius: 14)
    }
}
