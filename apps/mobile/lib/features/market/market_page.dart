import "package:flutter/material.dart";

enum MarketSection { used, newProduct, promotion }

class MarketPage extends StatefulWidget {
  const MarketPage({
    super.key,
    required this.section,
  });

  final MarketSection section;

  @override
  State<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends State<MarketPage> {
  @override
  Widget build(BuildContext context) {
    final List<_BoardItem> items = _itemsForSection(widget.section);
    return _BoardList(items: items);
  }

  List<_BoardItem> _itemsForSection(MarketSection section) {
    switch (section) {
      case MarketSection.used:
        return const <_BoardItem>[
          _BoardItem(
              title: "Used stroller", subtitle: "Seller: user01 | 120,000 KRW"),
          _BoardItem(
              title: "Baby bed", subtitle: "Seller: user02 | 35,000 KRW"),
          _BoardItem(
              title: "Carrier (3 months)",
              subtitle: "Seller: user03 | 60,000 KRW"),
        ];
      case MarketSection.newProduct:
        return const <_BoardItem>[
          _BoardItem(
              title: "Thermo bottle set",
              subtitle: "Brand: BabyHeat | Launch discount 15%"),
          _BoardItem(
              title: "Hypoallergenic diaper set",
              subtitle: "Brand: GentleCare | Free shipping event"),
          _BoardItem(
              title: "AI sleep monitor",
              subtitle: "Brand: MoonSleep | Trial group open"),
        ];
      case MarketSection.promotion:
        return const <_BoardItem>[
          _BoardItem(
              title: "2-week special sale", subtitle: "Up to 40% this week"),
          _BoardItem(
              title: "Infant nutrition program",
              subtitle: "Regional counseling in progress"),
          _BoardItem(
              title: "Care campaign",
              subtitle: "Vaccination + growth check package"),
        ];
    }
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
