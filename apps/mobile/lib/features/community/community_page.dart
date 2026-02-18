import "package:flutter/material.dart";

enum CommunitySection { free, reviews, jobs, servicePromo, suggestions }

class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.title,
    required this.preview,
    required this.body,
    required this.author,
    required this.publishedLabel,
    this.tags = const <String>[],
  });

  final String id;
  final String title;
  final String preview;
  final String body;
  final String author;
  final String publishedLabel;
  final List<String> tags;
}

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
    final List<CommunityPost> posts = _postsForSection(widget.section);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: posts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final CommunityPost post = posts[index];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) =>
                    _CommunityPostDetailPage(post: post),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.article_outlined),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          post.title,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    post.preview,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: post.tags
                        .map(
                          (String tag) => Chip(
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            label: Text(tag),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "${post.author} • ${post.publishedLabel}",
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<CommunityPost> _postsForSection(CommunitySection section) {
    switch (section) {
      case CommunitySection.free:
        return const <CommunityPost>[
          CommunityPost(
            id: "free-1",
            title: "Night feeding tips for 4-month baby",
            preview: "How to reduce wakeups while keeping healthy intake.",
            body:
                "We tested 3 routines over 2 weeks: fixed bedtime feed, dream feed, and flexible cue-based feed. The best balance came from fixed bedtime + one dream feed before midnight. Keep feed logs consistent for 5 days before evaluating changes.",
            author: "Mina K",
            publishedLabel: "2h ago",
            tags: <String>["Feeding", "Sleep", "4M"],
          ),
          CommunityPost(
            id: "free-2",
            title: "How to stabilize sleep routine?",
            preview: "Practical timing windows for naps and bedtime.",
            body:
                "Start from wake-up anchor time, then keep first nap within 90-120 minutes. Limit late-evening stimulation and avoid introducing a new bottle size on the same day you adjust bedtime.",
            author: "Alex P",
            publishedLabel: "7h ago",
            tags: <String>["Routine", "Nap", "Guide"],
          ),
          CommunityPost(
            id: "free-3",
            title: "Good stroller walking routes",
            preview: "Flat paths with clean diaper-changing facilities nearby.",
            body:
                "Parents shared routes with smooth sidewalks, shade, and nearby restrooms. Keep feeding timing in mind before leaving home, and prepare a quick diaper kit in a side pocket.",
            author: "J. Lee",
            publishedLabel: "1d ago",
            tags: <String>["Outdoor", "Stroller"],
          ),
        ];
      case CommunitySection.reviews:
        return const <CommunityPost>[
          CommunityPost(
            id: "review-1",
            title: "Baby bed real usage review",
            preview: "Heat, noise, and mattress cleanup after 30 days.",
            body:
                "Measured surface temperature and wipe-cleaning effort across 3 products. Models with removable side mesh performed best for midnight diaper checks.",
            author: "Product Lab",
            publishedLabel: "3h ago",
            tags: <String>["Review", "Bed"],
          ),
          CommunityPost(
            id: "review-2",
            title: "Diaper rash cream comparison",
            preview: "Texture, spreadability, and overnight effect.",
            body:
                "Thicker zinc-based creams held better overnight, while lighter cream worked faster during daytime changes. Apply thin layers and monitor irritation after each wash.",
            author: "Care Team",
            publishedLabel: "11h ago",
            tags: <String>["Review", "Diaper"],
          ),
          CommunityPost(
            id: "review-3",
            title: "Baby monitor battery test",
            preview: "Continuous use runtime by brightness mode.",
            body:
                "Low-brightness mode extended average runtime by 31%. For night shifts, keep charging station near feeding area to avoid monitor dropouts.",
            author: "Tech Parent",
            publishedLabel: "2d ago",
            tags: <String>["Review", "Monitor"],
          ),
        ];
      case CommunitySection.jobs:
        return const <CommunityPost>[
          CommunityPost(
            id: "job-1",
            title: "Looking for weekday babysitter",
            preview: "Mon-Fri 09:00-16:00, infant care experience required.",
            body:
                "Need support for feeding records, diaper changes, and nap tracking. Please share verification and expected hourly range in direct message.",
            author: "Family A",
            publishedLabel: "4h ago",
            tags: <String>["Hiring", "Weekday"],
          ),
          CommunityPost(
            id: "job-2",
            title: "Night-time care available this weekend",
            preview: "Certified caregiver, references available.",
            body:
                "Available Fri/Sat nights for newborn care, bottle prep, and sleep logs. I can also update BabyAI events for handoff transparency.",
            author: "Caregiver H",
            publishedLabel: "9h ago",
            tags: <String>["Available", "Night"],
          ),
          CommunityPost(
            id: "job-3",
            title: "Childcare support job post",
            preview: "Part-time support for twins in downtown area.",
            body:
                "Looking for 3 days/week support focused on feeding and stroller walks. Experience with bottle sterilization workflow is preferred.",
            author: "Family B",
            publishedLabel: "1d ago",
            tags: <String>["Hiring", "Part-time"],
          ),
        ];
      case CommunitySection.servicePromo:
        return const <CommunityPost>[
          CommunityPost(
            id: "promo-1",
            title: "Infant massage program",
            preview: "Guided routine for better evening wind-down.",
            body:
                "Certified coach sessions with weekly progress notes. Includes 15-minute routines that can be logged as memo/sleep support activities.",
            author: "CalmCare Center",
            publishedLabel: "6h ago",
            tags: <String>["Program", "Massage"],
          ),
          CommunityPost(
            id: "promo-2",
            title: "Home hygiene care package",
            preview: "Bottle station and baby room sanitization service.",
            body:
                "Monthly package includes deep clean around feeding and diaper areas. Safe product list is provided before service starts.",
            author: "CleanNest",
            publishedLabel: "1d ago",
            tags: <String>["Service", "Hygiene"],
          ),
          CommunityPost(
            id: "promo-3",
            title: "Postpartum helper service",
            preview: "Meal prep + feeding handoff support.",
            body:
                "Support sessions focus on reducing overnight stress and keeping record consistency for feeding and medication events.",
            author: "Helper Link",
            publishedLabel: "2d ago",
            tags: <String>["Service", "Postpartum"],
          ),
        ];
      case CommunitySection.suggestions:
        return const <CommunityPost>[
          CommunityPost(
            id: "suggestion-1",
            title: "Add vaccination timeline",
            preview: "Need reminder cards by age milestone.",
            body:
                "Proposed timeline view grouped by month. It should support custom reminders and medical-note attachments per checkpoint.",
            author: "Feature Board",
            publishedLabel: "8h ago",
            tags: <String>["Suggestion", "Health"],
          ),
          CommunityPost(
            id: "suggestion-2",
            title: "Request CSV export for records",
            preview: "For pediatric clinic sharing and backup.",
            body:
                "Export should include timestamp, event type, and key numeric fields. Optional anonymized mode would help for research groups.",
            author: "Feature Board",
            publishedLabel: "13h ago",
            tags: <String>["Suggestion", "Export"],
          ),
          CommunityPost(
            id: "suggestion-3",
            title: "Improve family alert UX",
            preview: "Need clearer urgency levels for notifications.",
            body:
                "Suggested tri-level alerts: info/warning/critical with separate mute windows. This can reduce notification fatigue during night shifts.",
            author: "Feature Board",
            publishedLabel: "2d ago",
            tags: <String>["Suggestion", "Notification"],
          ),
        ];
    }
  }
}

class _CommunityPostDetailPage extends StatelessWidget {
  const _CommunityPostDetailPage({required this.post});

  final CommunityPost post;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Post Detail")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        children: <Widget>[
          Text(
            post.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            "${post.author} • ${post.publishedLabel}",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: post.tags
                .map(
                  (String tag) => Chip(
                    label: Text(tag),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          Text(
            post.body,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}
