import SwiftUI

public enum BabyAIGlassPalette {
    public static let accent = Color(red: 0.90, green: 0.70, blue: 0.24)
    public static let accentStrong = Color(red: 0.93, green: 0.56, blue: 0.25)
    public static let positive = Color(red: 0.21, green: 0.64, blue: 0.47)
    public static let warning = Color(red: 0.92, green: 0.56, blue: 0.23)
    public static let surfaceStart = Color(red: 0.95, green: 0.97, blue: 1.0)
    public static let surfaceMid = Color(red: 0.90, green: 0.94, blue: 1.0)
    public static let surfaceEnd = Color(red: 0.86, green: 0.92, blue: 0.99)
    public static let textPrimary = Color(red: 0.12, green: 0.14, blue: 0.18)
    public static let textMuted = Color(red: 0.37, green: 0.40, blue: 0.46)
}

public struct BabyAIGlassContainer<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    public init(spacing: CGFloat = 14, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            VStack(spacing: spacing) {
                content
            }
        }
    }
}

public extension View {
    @ViewBuilder
    func babyAIGlassBackground() -> some View {
        background(
            ZStack {
                LinearGradient(
                    colors: [
                        BabyAIGlassPalette.surfaceStart,
                        BabyAIGlassPalette.surfaceMid,
                        BabyAIGlassPalette.surfaceEnd,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(BabyAIGlassPalette.accent.opacity(0.14))
                    .frame(width: 320, height: 320)
                    .offset(x: -120, y: -260)

                Circle()
                    .fill(BabyAIGlassPalette.accentStrong.opacity(0.12))
                    .frame(width: 280, height: 280)
                    .offset(x: 160, y: 260)
            }
            .ignoresSafeArea()
        )
    }

    @ViewBuilder
    func babyAIGlassCard(cornerRadius: CGFloat = 22) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            padding(14)
                .glassEffect(
                    .regular
                        .tint(.white.opacity(0.12))
                        .interactive(),
                    in: .rect(cornerRadius: cornerRadius)
                )
        } else {
            padding(14)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        }
    }

    @ViewBuilder
    func babyAIGlassInset(cornerRadius: CGFloat = 14) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            padding(.horizontal, 12)
                .padding(.vertical, 10)
                .glassEffect(
                    .regular.tint(.white.opacity(0.08)),
                    in: .rect(cornerRadius: cornerRadius)
                )
        } else {
            padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    Color.white.opacity(0.45),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        }
    }

    @ViewBuilder
    func babyAIGlassPrimaryButtonStyle() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            buttonStyle(.glassProminent)
                .tint(BabyAIGlassPalette.accent)
        } else {
            buttonStyle(.borderedProminent)
                .tint(BabyAIGlassPalette.accent)
        }
    }

    @ViewBuilder
    func babyAIGlassSecondaryButtonStyle() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func babyAIGlassToolbar() -> some View {
        #if os(iOS)
        self
            .toolbarBackground(.clear, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        #else
        self
        #endif
    }

    @ViewBuilder
    func babyAIGlassTabBar() -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func babyAIGlassInlineTitleModeIfAvailable() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

public struct BabyAIGlassScreenFrame<Content: View>: View {
    private let title: String
    private let content: Content

    public init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(16)
        }
        .babyAIGlassBackground()
        .navigationTitle(title)
        .babyAIGlassInlineTitleModeIfAvailable()
        .babyAIGlassToolbar()
    }
}
