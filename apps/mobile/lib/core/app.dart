import "package:flutter/material.dart";

import "../features/chat/chat_page.dart";
import "../features/photos/photos_page.dart";
import "../features/recording/recording_page.dart";
import "../features/report/report_page.dart";

class BabyAIApp extends StatelessWidget {
  const BabyAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "BabyAI",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2A6F97)),
        useMaterial3: true,
      ),
      home: const _HomeShell(),
    );
  }
}

class _HomeShell extends StatefulWidget {
  const _HomeShell();

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int _index = 0;

  final List<Widget> _pages = const <Widget>[
    RecordingPage(),
    ChatPage(),
    ReportPage(),
    PhotosPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int i) => setState(() => _index = i),
        destinations: const <NavigationDestination>[
          NavigationDestination(icon: Icon(Icons.mic), label: "Record"),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: "AI"),
          NavigationDestination(icon: Icon(Icons.analytics_outlined), label: "Report"),
          NavigationDestination(icon: Icon(Icons.photo_library_outlined), label: "Photos"),
        ],
      ),
    );
  }
}
