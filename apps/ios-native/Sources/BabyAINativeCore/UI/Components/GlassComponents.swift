import SwiftUI

public struct BabyAIGlassSectionHeader: View {
    private let title: String
    private let subtitle: String?

    public init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(BabyAIGlassPalette.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(BabyAIGlassPalette.textMuted)
            }
        }
    }
}

public struct BabyAIGlassMetricCard: View {
    private let title: String
    private let value: String
    private let trend: String

    public init(title: String, value: String, trend: String) {
        self.title = title
        self.value = value
        self.trend = trend
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(BabyAIGlassPalette.textMuted)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(BabyAIGlassPalette.textPrimary)
            Text(trend)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .babyAIGlassCard(cornerRadius: 18)
    }
}

public struct BabyAIGlassTag: View {
    private let text: String
    private let color: Color

    public init(_ text: String, color: Color = BabyAIGlassPalette.accent) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.16), in: Capsule())
    }
}

public struct BabyAIGlassInputRow: View {
    private let title: String
    @Binding private var text: String
    private let prompt: String

    public init(title: String, text: Binding<String>, prompt: String) {
        self.title = title
        self._text = text
        self.prompt = prompt
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            TextField(prompt, text: $text)
                .babyAIGlassInset(cornerRadius: 12)
        }
    }
}

public struct BabyAIGlassToggleRow: View {
    private let title: String
    private let subtitle: String?
    @Binding private var isOn: Bool

    public init(title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    public var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .babyAIGlassInset(cornerRadius: 14)
    }
}

public struct BabyAIGlassActionGrid: View {
    private let items: [ActionItem]

    public struct ActionItem: Identifiable {
        public let id = UUID()
        public let title: String
        public let systemImage: String
        public let action: () -> Void

        public init(title: String, systemImage: String, action: @escaping () -> Void) {
            self.title = title
            self.systemImage = systemImage
            self.action = action
        }
    }

    public init(items: [ActionItem]) {
        self.items = items
    }

    public var body: some View {
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
        ]
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(items) { item in
                Button {
                    item.action()
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: item.systemImage)
                            .font(.headline)
                        Text(item.title)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .babyAIGlassSecondaryButtonStyle()
            }
        }
    }
}
