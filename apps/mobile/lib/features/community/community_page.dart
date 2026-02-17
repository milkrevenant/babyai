import "package:flutter/material.dart";

import "../../core/i18n/app_i18n.dart";

enum _CommunitySection { free, reviews, jobs, servicePromo, suggestions }

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  _CommunitySection _section = _CommunitySection.free;

  @override
  Widget build(BuildContext context) {
    final List<String> items = _itemsForSection(_section);
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _OvalIconChoice(
                selected: _section == _CommunitySection.free,
                icon: Icons.forum_outlined,
                label: tr(context,
                    ko: "자유게시판", en: "Free Board", es: "Foro libre"),
                onTap: () => setState(() => _section = _CommunitySection.free),
              ),
              _OvalIconChoice(
                selected: _section == _CommunitySection.reviews,
                icon: Icons.rate_review_outlined,
                label: tr(context, ko: "리뷰게시판", en: "Reviews", es: "Resenas"),
                onTap: () =>
                    setState(() => _section = _CommunitySection.reviews),
              ),
              _OvalIconChoice(
                selected: _section == _CommunitySection.jobs,
                icon: Icons.work_outline,
                label: tr(context, ko: "구인구직", en: "Jobs", es: "Empleo"),
                onTap: () => setState(() => _section = _CommunitySection.jobs),
              ),
              _OvalIconChoice(
                selected: _section == _CommunitySection.servicePromo,
                icon: Icons.campaign_outlined,
                label: tr(context,
                    ko: "업체/서비스 홍보", en: "Service Promo", es: "Promocion"),
                onTap: () =>
                    setState(() => _section = _CommunitySection.servicePromo),
              ),
              _OvalIconChoice(
                selected: _section == _CommunitySection.suggestions,
                icon: Icons.lightbulb_outline,
                label: tr(context,
                    ko: "건의게시판", en: "Suggestions", es: "Sugerencias"),
                onTap: () =>
                    setState(() => _section = _CommunitySection.suggestions),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (BuildContext context, int index) {
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: Text(items[index]),
                  subtitle: Text(tr(context,
                      ko: "상세 보기", en: "Open detail", es: "Ver detalle")),
                  trailing: const Icon(Icons.chevron_right),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<String> _itemsForSection(_CommunitySection section) {
    switch (section) {
      case _CommunitySection.free:
        return <String>[
          "4개월 아기 밤수유 팁 공유해요",
          "밤잠 루틴 잡는 방법 질문",
          "유모차 좋은 산책 코스 추천",
        ];
      case _CommunitySection.reviews:
        return <String>[
          "아기 침대 실사용 리뷰",
          "기저귀 발진크림 비교 후기",
          "아기 모니터 배터리 테스트",
        ];
      case _CommunitySection.jobs:
        return <String>[
          "주중 오후 베이비시터 구합니다",
          "주말 야간 케어 가능한 분",
          "육아 보조 인력 채용 공고",
        ];
      case _CommunitySection.servicePromo:
        return <String>[
          "영유아 마사지 프로그램 소개",
          "아기집 위생 케어 패키지",
          "산후조리 서비스 안내",
        ];
      case _CommunitySection.suggestions:
        return <String>[
          "예방접종 일정 타임라인 추가 요청",
          "기록 CSV 내보내기 기능 요청",
          "가족 알림 확인 UX 개선 건의",
        ];
    }
  }
}

class _OvalIconChoice extends StatelessWidget {
  const _OvalIconChoice({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme color = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? color.primaryContainer.withValues(alpha: 0.92)
          : color.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 18),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}
