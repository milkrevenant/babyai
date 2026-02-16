import "package:flutter/material.dart";

import "../../core/network/babyai_api.dart";

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _daily;
  Map<String, dynamic>? _weekly;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  DateTime _toWeekStart(DateTime day) {
    final DateTime utc = DateTime.utc(day.year, day.month, day.day);
    return utc.subtract(Duration(days: utc.weekday - DateTime.monday));
  }

  Future<void> _loadReports() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final DateTime now = DateTime.now().toUtc();
    try {
      final Map<String, dynamic> daily = await BabyAIApi.instance.dailyReport(now);
      final Map<String, dynamic> weekly = await BabyAIApi.instance.weeklyReport(_toWeekStart(now));
      setState(() {
        _daily = daily;
        _weekly = weekly;
      });
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Reports"),
        actions: <Widget>[
          IconButton(
            onPressed: _loading ? null : _loadReports,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _SectionCard(
            title: "Daily Summary",
            child: _ReportList(
              items: ((_daily?["summary"] as List<dynamic>?) ?? <dynamic>[])
                  .map((dynamic item) => item.toString())
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: "Weekly Trend",
            child: _TrendView(
              trend: ((_weekly?["trend"] as Map<dynamic, dynamic>?) ?? <dynamic, dynamic>{}).map(
                (dynamic key, dynamic value) => MapEntry(key.toString(), value.toString()),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: "Weekly Suggestions",
            child: _ReportList(
              items: ((_weekly?["suggestions"] as List<dynamic>?) ?? <dynamic>[])
                  .map((dynamic item) => item.toString())
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _ReportList extends StatelessWidget {
  const _ReportList({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text("No data available.");
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items
          .map(
            (String item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text("- $item"),
            ),
          )
          .toList(),
    );
  }
}

class _TrendView extends StatelessWidget {
  const _TrendView({required this.trend});

  final Map<String, String> trend;

  @override
  Widget build(BuildContext context) {
    if (trend.isEmpty) {
      return const Text("No trend data available.");
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: trend.entries
          .map(
            (MapEntry<String, String> entry) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text("${entry.key}: ${entry.value}"),
            ),
          )
          .toList(),
    );
  }
}
