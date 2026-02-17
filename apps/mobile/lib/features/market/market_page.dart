import "package:flutter/material.dart";

class MarketPage extends StatelessWidget {
  const MarketPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 3,
      child: Column(
        children: <Widget>[
          TabBar(
            isScrollable: true,
            tabs: <Tab>[
              Tab(icon: Icon(Icons.swap_horiz), text: "Used Market"),
              Tab(
                  icon: Icon(Icons.new_releases_outlined),
                  text: "New Products"),
              Tab(icon: Icon(Icons.campaign_outlined), text: "Promotion"),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                _BoardList(
                  items: <_BoardItem>[
                    _BoardItem(
                      title: "Used stroller - clean condition",
                      subtitle: "Seller: Hana | Price: 120,000 KRW",
                    ),
                    _BoardItem(
                      title: "Bottle sterilizer",
                      subtitle: "Seller: MilkMom | Price: 35,000 KRW",
                    ),
                    _BoardItem(
                      title: "Baby carrier (3 months)",
                      subtitle: "Seller: SeoulParent | Price: 60,000 KRW",
                    ),
                  ],
                ),
                _BoardList(
                  items: <_BoardItem>[
                    _BoardItem(
                      title: "Smart bottle warmer launch",
                      subtitle: "Brand: BabyHeat | Intro discount 15%",
                    ),
                    _BoardItem(
                      title: "Organic diaper set",
                      subtitle: "Brand: GentleCare | Free shipping event",
                    ),
                    _BoardItem(
                      title: "AI sleep monitor",
                      subtitle: "Brand: MoonSleep | New product review open",
                    ),
                  ],
                ),
                _BoardList(
                  items: <_BoardItem>[
                    _BoardItem(
                      title: "February family care fair",
                      subtitle: "Up to 40% discount this week",
                    ),
                    _BoardItem(
                      title: "Nutrition webinar for infants",
                      subtitle: "Online session, registration open",
                    ),
                    _BoardItem(
                      title: "Clinic partnership campaign",
                      subtitle: "Vaccination info + growth check package",
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
      padding: const EdgeInsets.all(12),
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
  const _BoardItem({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;
}
