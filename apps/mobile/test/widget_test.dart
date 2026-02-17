import "package:flutter_test/flutter_test.dart";

import "package:babyai/core/app.dart";

void main() {
  testWidgets("app boots to home landing screen", (WidgetTester tester) async {
    await tester.pumpWidget(const BabyAIApp());
    expect(find.text("오늘의 아이 기록"), findsOneWidget);
    expect(find.text("일"), findsWidgets);
  });
}
