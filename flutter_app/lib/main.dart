import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'app/app.dart';
import 'bridge/rust_bridge.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set dark system navigation bar & status bar
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF08080A),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  try {
    final appDocDir = await getApplicationDocumentsDirectory();
    Directory? externalDir;
    try {
      externalDir = await getExternalStorageDirectory();
    } catch (_) {
      externalDir = appDocDir;
    }
    final sdPath = externalDir?.path ?? appDocDir.path;

    // yt-dlp binary is extracted from assets into the app filesDir by MainActivity
    // On Android: /data/data/com.hifi.flutter_app/files/yt-dlp
    // On other platforms: no-op (empty string — downloader unavailable)
    String ytdlpPath = '';
    if (Platform.isAndroid) {
      final filesDir = await getApplicationSupportDirectory();
      ytdlpPath = '${filesDir.path}/yt-dlp';
    }

    RustBridge.instance.init(appDocDir.path, sdPath, ytdlpPath);
  } catch (e) {
    debugPrint('RustBridge init error: $e');
  }

  runApp(
    const ProviderScope(
      child: MusicPlayerApp(),
    ),
  );
}
