import 'package:flutter_test/flutter_test.dart';

import 'package:babyai/core/app.dart';

void main() {
  testWidgets('app boots to recording screen', (WidgetTester tester) async {
    await tester.pumpWidget(const BabyAIApp());
    expect(find.text('Voice Recording'), findsOneWidget);
    expect(find.text('Parse Voice'), findsOneWidget);
  });
}
