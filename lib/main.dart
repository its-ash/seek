import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import 'screens/home_screen.dart';
import 'seek/seek_platform.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(SeekApp(platform: MethodChannelSeekPlatform()));
}

class SeekApp extends StatelessWidget {
  const SeekApp({super.key, required this.platform});

  final SeekPlatform platform;

  @override
  Widget build(BuildContext context) {
    return UiApp(
      title: 'Seek',
      home: HomeScreen(platform: platform),
    );
  }
}
