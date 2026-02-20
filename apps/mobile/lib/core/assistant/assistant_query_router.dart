enum AssistantQuickRoute {
  none,
  lastPooTime,
  lastFeeding,
  recentSleep,
  nextFeedingEta,
  todaySummary,
  lastDiaper,
  lastMedication,
}

class AssistantQueryRouter {
  const AssistantQueryRouter._();

  static AssistantQuickRoute resolve(String question) {
    final String normalized = question.toLowerCase().trim();
    if (normalized.isEmpty) {
      return AssistantQuickRoute.none;
    }

    final bool asksLast = _containsAny(normalized, const <String>[
      "last",
      "latest",
      "recent",
      "마지막",
      "최근",
      "최신",
    ]);
    final bool asksFeed = _containsAny(normalized, const <String>[
      "feeding",
      "feed",
      "formula",
      "breastfeed",
      "수유",
      "분유",
      "모유",
    ]);
    final bool asksSleep = _containsAny(normalized, const <String>[
      "sleep",
      "nap",
      "잠",
      "수면",
      "잠든",
    ]);
    final bool asksDiaper = _containsAny(normalized, const <String>[
      "diaper",
      "pee",
      "poo",
      "poop",
      "stool",
      "기저귀",
      "소변",
      "대변",
      "오줌",
      "응가",
      "똥",
    ]);
    final bool asksMedication = _containsAny(normalized, const <String>[
      "medication",
      "medicine",
      "dose",
      "투약",
      "약",
      "복용",
    ]);
    final bool asksTodaySummary = _containsAny(normalized, const <String>[
      "today summary",
      "today",
      "daily summary",
      "오늘 요약",
      "오늘",
      "요약",
    ]);
    final bool asksNextEta = _containsAny(normalized, const <String>[
      "eta",
      "next",
      "when",
      "다음",
      "언제",
      "예정",
    ]);
    final bool asksPoo = _containsAny(normalized, const <String>[
      "poo",
      "poop",
      "stool",
      "대변",
      "응가",
      "똥",
    ]);

    if (asksFeed && asksNextEta) {
      return AssistantQuickRoute.nextFeedingEta;
    }
    if (asksTodaySummary) {
      return AssistantQuickRoute.todaySummary;
    }
    if (asksPoo && asksLast) {
      return AssistantQuickRoute.lastPooTime;
    }
    if (asksFeed && asksLast) {
      return AssistantQuickRoute.lastFeeding;
    }
    if (asksSleep && asksLast) {
      return AssistantQuickRoute.recentSleep;
    }
    if (asksDiaper && asksLast) {
      return AssistantQuickRoute.lastDiaper;
    }
    if (asksMedication && asksLast) {
      return AssistantQuickRoute.lastMedication;
    }
    return AssistantQuickRoute.none;
  }

  static bool _containsAny(String text, List<String> keywords) {
    for (final String keyword in keywords) {
      if (text.contains(keyword)) {
        return true;
      }
    }
    return false;
  }
}
