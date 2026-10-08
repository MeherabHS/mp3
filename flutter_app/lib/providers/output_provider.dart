import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../bridge/rust_bridge.dart';
import '../models/audio_quality.dart';

final outputProvider = StateNotifierProvider<OutputNotifier, OutputStatus>((ref) {
  return OutputNotifier();
});

class OutputNotifier extends StateNotifier<OutputStatus> {
  static const MethodChannel _channel = MethodChannel('com.hifi.musicplayer/output');

  OutputNotifier() : super(const OutputStatus()) {
    _initPlatformListener();
  }

  void _initPlatformListener() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onOutputChanged') {
        final jsonStr = call.arguments as String;
        final jsonMap = jsonDecode(jsonStr) as Map<String, dynamic>;
        final status = OutputStatus.fromJson(jsonMap);
        updateOutput(status);
      }
    });

    _fetchCurrentOutput();
  }

  Future<void> _fetchCurrentOutput() async {
    try {
      final res = await _channel.invokeMethod<String>('getCurrentOutput');
      if (res != null && res.isNotEmpty && res != '{}') {
        final jsonMap = jsonDecode(res) as Map<String, dynamic>;
        final status = OutputStatus.fromJson(jsonMap);
        updateOutput(status);
      }
    } catch (_) {
      // Running on non-Android host fallback
    }
  }

  void updateOutput(OutputStatus newStatus) {
    state = newStatus;
    RustBridge.instance.updateOutputStatus(newStatus);
  }
}
