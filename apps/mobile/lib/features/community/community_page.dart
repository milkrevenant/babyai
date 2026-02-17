import "package:flutter/material.dart";

class CommunityPage extends StatelessWidget {
  const CommunityPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 5,
      child: Column(
        children: <Widget>[
          TabBar(
            isScrollable: true,
            tabs: <Tab>[
              Tab(text: "Free Board"),
              Tab(text: "Reviews"),
              Tab(text: "Jobs"),
              Tab(text: "Service Promo"),
              Tab(text: "Suggestions"),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                _CommunityList(
                  icon: Icons.forum_outlined,
                  items: <String>[
                    "Night feeding tips for 4-month baby",
                    "How to improve nap consistency?",
                    "Recommended stroller-friendly places",
                  ],
                ),
                _CommunityList(
                  icon: Icons.rate_review_outlined,
                  items: <String>[
                    "Bottle warmer review: pros/cons",
                    "Diaper rash cream comparison",
                    "Baby monitor real-world battery test",
                  ],
                ),
                _CommunityList(
                  icon: Icons.work_outline,
                  items: <String>[
                    "Part-time nanny in Gangnam (weekday PM)",
                    "Night nurse available (newborn specialist)",
                    "Pediatric clinic hiring assistant staff",
                  ],
                ),
                _CommunityList(
                  icon: Icons.campaign_outlined,
                  items: <String>[
                    "Local infant massage program",
                    "Home sanitization package for babies",
                    "Postpartum care center introduction",
                  ],
                ),
                _CommunityList(
                  icon: Icons.lightbulb_outline,
                  items: <String>[
                    "Please add vaccine reminder timeline",
                    "Need CSV export for feeding records",
                    "Would like shared family notifications",
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

class _CommunityList extends StatelessWidget {
  const _CommunityList({
    required this.icon,
    required this.items,
  });

  final IconData icon;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        return Card(
          child: ListTile(
            leading: Icon(icon),
            title: Text(items[index]),
            subtitle: const Text("Tap to open detail"),
            trailing: const Icon(Icons.chevron_right),
          ),
        );
      },
    );
  }
}
