import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "package:babyai/core/app.dart";

void main() {
  testWidgets("app boots without crashing", (WidgetTester tester) async {
    await tester.pumpWidget(const BabyAIApp());
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsWidgets);
  });
}
