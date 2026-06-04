import 'package:flutter_test/flutter_test.dart';

import 'package:dsp/main.dart';

void main() {
  testWidgets('DSP controller renders disconnected state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    expect(find.text('DSP408 Controller'), findsOneWidget);
    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.text('Not Connected'), findsOneWidget);
  });
}
