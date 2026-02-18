import "package:flutter_test/flutter_test.dart";

import "package:babyai/core/assistant/assistant_query_router.dart";

void main() {
  test("routes last feeding question", () {
    final AssistantQuickRoute route =
        AssistantQueryRouter.resolve("last feeding time");
    expect(route, AssistantQuickRoute.lastFeeding);
  });

  test("routes recent sleep question", () {
    final AssistantQuickRoute route = AssistantQueryRouter.resolve("최근 수면");
    expect(route, AssistantQuickRoute.recentSleep);
  });

  test("routes next feeding eta question", () {
    final AssistantQuickRoute route =
        AssistantQueryRouter.resolve("when is next feeding eta");
    expect(route, AssistantQuickRoute.nextFeedingEta);
  });

  test("routes last diaper question", () {
    final AssistantQuickRoute route =
        AssistantQueryRouter.resolve("last diaper");
    expect(route, AssistantQuickRoute.lastDiaper);
  });

  test("returns none for unrelated text", () {
    final AssistantQuickRoute route =
        AssistantQueryRouter.resolve("show community posts");
    expect(route, AssistantQuickRoute.none);
  });
}
