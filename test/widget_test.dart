import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jumping_jack/main.dart';

void main() {
  testWidgets('App boots and mounts the GameWidget', (tester) async {
    await tester.pumpWidget(const JumpingJackApp());
    await tester.pump();

    expect(find.byType(GameWidget<JumpingJackGame>), findsOneWidget);
  });
}
