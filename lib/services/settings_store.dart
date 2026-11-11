import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine.dart';

/// App level settings + engine status.
class SettingsStore {
  static const String _keySaveCopy = 'videograb_save_copy_v1';
  static const String _keyConcurrency = 'videograb_concurrency_v1';

  static final ValueNotifier<bool> saveCopy = ValueNotifier<bool>(true);

  /// Parallel fragments / HTTP connections used by yt-dlp (speed control).
  static final ValueNotifier<int> concurrency = ValueNotifier<int>(8);
  static final ValueNotifier<bool> engineReady = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> engineBooting = ValueNotifier<bool>(true);
  static final ValueNotifier<String> engineVersion = ValueNotifier<String>('');
  static final ValueNotifier<String> engineError = ValueNotifier<String>('');
  static final ValueNotifier<int> sdkInt = ValueNotifier<int>(0);

  /// True when the installed APK bundles the ffmpeg natives (full build).
  static final ValueNotifier<bool> hasFfmpeg = ValueNotifier<bool>(true);

  static Future<void> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    saveCopy.value = prefs.getBool(_keySaveCopy) ?? true;
    concurrency.value = (prefs.getInt(_keyConcurrency) ?? 8).clamp(1, 24).toInt();
  }

  static Future<void> setSaveCopy(bool value) async {
    saveCopy.value = value;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySaveCopy, value);
  }

  static Future<void> setConcurrency(int value) async {
    concurrency.value = value.clamp(1, 24).toInt();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyConcurrency, concurrency.value);
  }

  /// Extracts and prepares the bundled python + yt-dlp runtime (first run is slow).
  static Future<void> bootEngine() async {
    engineBooting.value = true;
    final Map<String, dynamic> result = await Engine.init();
    engineBooting.value = false;
    if (result['ok'] == true) {
      engineReady.value = true;
      engineError.value = '';
      engineVersion.value = (result['version'] ?? '') as String;
      if (result['hasFfmpeg'] is bool) {
        hasFfmpeg.value = result['hasFfmpeg'] as bool;
      }
    } else {
      engineReady.value = false;
      engineError.value = (result['error'] ?? 'Engine init failed') as String;
    }

    final Map<String, dynamic> info = await Engine.info();
    if (info['hasFfmpeg'] is bool) {
      hasFfmpeg.value = info['hasFfmpeg'] as bool;
    }
    if (info['ok'] == true && info['sdkInt'] is num) {
      sdkInt.value = (info['sdkInt'] as num).toInt();
    } else if (result['sdkInt'] is num) {
      sdkInt.value = (result['sdkInt'] as num).toInt();
    }
  }
}
