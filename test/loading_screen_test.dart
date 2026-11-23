import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/widgets/loading_screen.dart';

void main() {
  testWidgets('loading tips rotate and stop when the screen closes', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoadingScreen()));
    final before = tester.widgetList<Text>(find.byType(Text)).map((w) => w.data).toList();
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 700));
    final after = tester.widgetList<Text>(find.byType(Text)).map((w) => w.data).toList();
    expect(after, isNot(equals(before)));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });
}
