import 'package:flutter_test/flutter_test.dart';

import 'package:hfsconnectapp/main.dart';

void main() {
  testWidgets('App starts on login page', (WidgetTester tester) async {
    await tester.pumpWidget(const HfsConnectApp());

    expect(find.text('HFSConnect - Admin'), findsOneWidget);
    expect(find.text('Home Page Placeholder'), findsNothing);
  });
}
