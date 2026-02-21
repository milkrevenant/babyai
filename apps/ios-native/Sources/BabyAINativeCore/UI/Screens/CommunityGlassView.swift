import SwiftUI

public struct CommunityGlassView: View {
    public init() {}

    public var body: some View {
        BabyAIGlassScreenFrame(title: "Community") {
            BabyAIGlassSectionHeader("Community Feed", subtitle: "UI mirror target")

            ForEach(posts, id: \.id) { post in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(post.author)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        BabyAIGlassTag(post.tag, color: BabyAIGlassPalette.positive)
                    }
                    Text(post.body)
                        .font(.subheadline)
                        .foregroundStyle(BabyAIGlassPalette.textPrimary)
                    HStack(spacing: 10) {
                        Button("Like") {}
                            .babyAIGlassSecondaryButtonStyle()
                        Button("Reply") {}
                            .babyAIGlassSecondaryButtonStyle()
                    }
                }
                .babyAIGlassCard(cornerRadius: 24)
            }
        }
    }

    private var posts: [(id: String, author: String, body: String, tag: String)] {
        [
            ("1", "Parent A", "새벽 수면 루틴 이렇게 맞췄더니 안정적이었어요.", "sleep"),
            ("2", "Parent B", "이유식 도입 첫 주 기록 템플릿 공유합니다.", "weaning"),
        ]
    }
}
