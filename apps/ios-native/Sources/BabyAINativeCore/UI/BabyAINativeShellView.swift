import SwiftUI

public enum BabyAINativeTab: Int, CaseIterable, Hashable {
    case home = 0
    case chat = 1
    case statistics = 2
    case settingsAliasPhotos = 3
    case market = 4
    case community = 5

    var title: String {
        switch self {
        case .home:
            return "Home"
        case .chat:
            return "Chat"
        case .statistics:
            return "Statistics"
        case .settingsAliasPhotos:
            return "Settings"
        case .market:
            return "Market"
        case .community:
            return "Community"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            return "house.fill"
        case .chat:
            return "bubble.left.and.bubble.right.fill"
        case .statistics:
            return "chart.xyaxis.line"
        case .settingsAliasPhotos:
            return "gearshape.fill"
        case .market:
            return "cart.fill"
        case .community:
            return "person.3.fill"
        }
    }
}

public struct BabyAINativeShellView: View {
    @State private var selectedTab: BabyAINativeTab = .home

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            tab(.home) { HomeGlassView() }
            tab(.chat) { ChatGlassView() }
            tab(.statistics) { StatisticsGlassView() }
            tab(.settingsAliasPhotos) { SettingsGlassView() }
            tab(.market) { MarketGlassView() }
            tab(.community) { CommunityGlassView() }
        }
        .babyAIGlassTabBar()
    }

    private func tab<Content: View>(
        _ tab: BabyAINativeTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack {
            content()
        }
        .tabItem {
            Label(tab.title, systemImage: tab.systemImage)
        }
        .tag(tab)
    }
}

#Preview {
    BabyAINativeShellView()
}
