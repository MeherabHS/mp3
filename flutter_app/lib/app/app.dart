import 'package:flutter/material.dart';
import 'main_scaffold.dart';
import 'theme.dart';

class MusicPlayerApp extends StatelessWidget {
  const MusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Personal Hi-Fi Music',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: const MainScaffold(),
    );
  }
}
