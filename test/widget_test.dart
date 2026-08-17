import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:magnet/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('renders the magnet landing screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MagnetApp());
    await tester.pump();

    expect(find.text('magnet'), findsOneWidget);
    expect(find.text('Start streaming'), findsOneWidget);
    expect(find.text('Ready when you are'), findsOneWidget);
  });

  testWidgets('shows the library tab', (WidgetTester tester) async {
    await tester.pumpWidget(const MagnetApp());
    await tester.pump();

    await tester.tap(find.text('Library'));
    await tester.pump();

    expect(find.text('Saved for later.'), findsOneWidget);
  });
}
