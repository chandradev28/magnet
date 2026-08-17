import 'package:flutter_test/flutter_test.dart';
import 'package:magnet/main.dart';

void main() {
  testWidgets('app shell renders the magnet header', (tester) async {
    await tester.pumpWidget(const MagnetApp());
    await tester.pump();
    expect(find.text('magnet'), findsWidgets);
  });
}
