import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

enum PerformanceMode { light, balanced, visual }

class AppSettings {
  final String userName;
  final PerformanceMode performanceMode;
  final String storagePath;
  /// Musixmatch unofficial usertoken for synced-lyrics fetching.
  /// Obtained from the Musixmatch desktop app's internal network requests.
  /// Empty string = tier skipped.
  final String musixmatchToken;

  const AppSettings({
    this.userName = 'Listener',
    this.performanceMode = PerformanceMode.balanced,
    this.storagePath = '',
    this.musixmatchToken = '',
  });

  AppSettings copyWith({
    String? userName,
    PerformanceMode? performanceMode,
    String? storagePath,
    String? musixmatchToken,
  }) =>
      AppSettings(
        userName: userName ?? this.userName,
        performanceMode: performanceMode ?? this.performanceMode,
        storagePath: storagePath ?? this.storagePath,
        musixmatchToken: musixmatchToken ?? this.musixmatchToken,
      );

  Map<String, dynamic> toJson() => {
        'userName': userName,
        'performanceMode': performanceMode.name,
        'storagePath': storagePath,
        'musixmatchToken': musixmatchToken,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        userName: json['userName'] as String? ?? 'Listener',
        performanceMode: PerformanceMode.values.firstWhere(
          (e) => e.name == json['performanceMode'],
          orElse: () => PerformanceMode.balanced,
        ),
        storagePath: json['storagePath'] as String? ?? '',
        musixmatchToken: json['musixmatchToken'] as String? ?? '',
      );
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings()) {
    _load();
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/app_settings.json');
  }

  Future<void> _load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        state = AppSettings.fromJson(json);
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(state.toJson()));
    } catch (_) {}
  }

  Future<void> setUserName(String name) async {
    state = state.copyWith(userName: name.isEmpty ? 'Listener' : name);
    await _save();
  }

  Future<void> setPerformanceMode(PerformanceMode mode) async {
    state = state.copyWith(performanceMode: mode);
    await _save();
  }

  Future<void> setStoragePath(String path) async {
    state = state.copyWith(storagePath: path);
    await _save();
  }

  Future<void> setMusixmatchToken(String token) async {
    state = state.copyWith(musixmatchToken: token.trim());
    await _save();
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>(
  (_) => SettingsNotifier(),
);
