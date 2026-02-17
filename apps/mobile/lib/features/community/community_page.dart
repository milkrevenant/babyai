import "package:flutter/material.dart";

enum CommunitySection { free, reviews, jobs, servicePromo, suggestions }

class CommunityPage extends StatefulWidget {
  const CommunityPage({
    super.key,
    required this.section,
  });

  final CommunitySection section;

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  @override
  Widget build(BuildContext context) {
    final List<String> items = _itemsForSection(widget.section);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        return Card(
          child: ListTile(
            leading: const Icon(Icons.article_outlined),
            title: Text(items[index]),
            subtitle: const Text("Open detail"),
            trailing: const Icon(Icons.chevron_right),
          ),
        );
      },
    );
  }

  List<String> _itemsForSection(CommunitySection section) {
    switch (section) {
      case CommunitySection.free:
        return <String>[
          "Night feeding tips for 4-month baby",
          "How to stabilize sleep routine?",
          "Good stroller walking routes",
        ];
      case CommunitySection.reviews:
        return <String>[
          "Baby bed real usage review",
          "Diaper rash cream comparison",
          "Baby monitor battery test",
        ];
      case CommunitySection.jobs:
        return <String>[
          "Looking for weekday babysitter",
          "Night-time care available this weekend",
          "Childcare support job post",
        ];
      case CommunitySection.servicePromo:
        return <String>[
          "Infant massage program",
          "Home hygiene care package",
          "Postpartum helper service",
        ];
      case CommunitySection.suggestions:
        return <String>[
          "Add vaccination timeline",
          "Request CSV export for records",
          "Improve family alert UX",
        ];
    }
  }
}
