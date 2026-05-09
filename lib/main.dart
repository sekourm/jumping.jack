import 'package:flutter/material.dart';

import 'app.dart';
import 'services/preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Preferences.init();
  runApp(const JumpingJackApp());
}
