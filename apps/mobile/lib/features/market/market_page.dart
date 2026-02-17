import "package:flutter/material.dart";

import "../../core/i18n/app_i18n.dart";

enum _MarketSection { used, newProduct, promotion }

class MarketPage extends StatefulWidget {
  const MarketPage({super.key});

  @override
  State<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends State<MarketPage> {
  _MarketSection _section = _MarketSection.used;

  @override
  Widget build(BuildContext context) {
    final List<_BoardItem> items = _itemsForSection(_section);
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _OvalIconChoice(
                selected: _section == _MarketSection.used,
                icon: Icons.swap_horiz,
                label: tr(context, ko: "중고장터", en: "Used Market", es: "Usado"),
                onTap: () => setState(() => _section = _MarketSection.used),
              ),
              _OvalIconChoice(
                selected: _section == _MarketSection.newProduct,
                icon: Icons.new_releases_outlined,
                label: tr(context, ko: "신상품", en: "New Products", es: "Nuevos"),
                onTap: () =>
                    setState(() => _section = _MarketSection.newProduct),
              ),
              _OvalIconChoice(
                selected: _section == _MarketSection.promotion,
                icon: Icons.campaign_outlined,
                label: tr(context, ko: "홍보", en: "Promotion", es: "Promocion"),
                onTap: () =>
                    setState(() => _section = _MarketSection.promotion),
              ),
            ],
          ),
        ),
        Expanded(child: _BoardList(items: items)),
      ],
    );
  }

  List<_BoardItem> _itemsForSection(_MarketSection section) {
    switch (section) {
      case _MarketSection.used:
        return <_BoardItem>[
          const _BoardItem(
              title: "유모차 중고 판매", subtitle: "판매자: 민수맘 | 가격: 120,000원"),
          const _BoardItem(
              title: "아기 침대 팝니다", subtitle: "판매자: 별이아빠 | 가격: 35,000원"),
          const _BoardItem(
              title: "아기띠 3개월 사용", subtitle: "판매자: 서울부모 | 가격: 60,000원"),
        ];
      case _MarketSection.newProduct:
        return <_BoardItem>[
          const _BoardItem(
              title: "엄마표 보온병 세트", subtitle: "브랜드: BabyHeat | 출시 할인 15%"),
          const _BoardItem(
              title: "저자극 기저귀 세트", subtitle: "브랜드: GentleCare | 무료 배송 이벤트"),
          const _BoardItem(
              title: "AI 수면 모니터", subtitle: "브랜드: MoonSleep | 체험단 모집"),
        ];
      case _MarketSection.promotion:
        return <_BoardItem>[
          const _BoardItem(title: "2주 특가 방한복", subtitle: "이번 주 최대 40% 할인"),
          const _BoardItem(title: "영유아 영양 플러스 프로그램", subtitle: "지역별 상담 진행 중"),
          const _BoardItem(title: "육아용품 제휴 캠페인", subtitle: "예방접종 + 성장검진 패키지"),
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

class _BoardList extends StatelessWidget {
  const _BoardList({required this.items});

  final List<_BoardItem> items;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final _BoardItem item = items[index];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.article_outlined),
            title: Text(item.title),
            subtitle: Text(item.subtitle),
            trailing: const Icon(Icons.chevron_right),
          ),
        );
      },
    );
  }
}

class _BoardItem {
  const _BoardItem({required this.title, required this.subtitle});

  final String title;
  final String subtitle;
}
