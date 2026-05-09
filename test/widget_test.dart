import 'package:flutter_test/flutter_test.dart';

import 'package:jumping_jack/app.dart';
import 'package:jumping_jack/ui/screens/home_screen.dart';

void main() {
  testWidgets('App boots and shows the home screen', (tester) async {
    await tester.pumpWidget(const JumpingJackApp());
    await tester.pump();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('JOUER'), findsOneWidget);
    expect(find.text('PARAMÈTRES'), findsOneWidget);
  });
}
