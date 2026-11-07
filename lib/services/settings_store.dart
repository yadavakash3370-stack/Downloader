import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine.dart';

/// App level settings + engine status.
class SettingsStore {
  static const String _keySaveCopy = 'videograb_save_copy_v1';

  static final ValueNotifier<bool> saveCopy = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> engineReady = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> engineBooting = ValueNotifier<bool>(true);
  static final ValueNotifier<String> engineVersion = ValueNotifier<String>('');
  static final ValueNotifier<String> engineError = ValueNotifier<String>('');
  static final ValueNotifier<int> sdkInt = ValueNotifier<int>(0);

  static Future<void> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    saveCopy.value = prefs.getBool(_keySaveCopy) ?? true;
  }

  static Future<void> setSaveCopy(bool value) async {
    saveCopy.value = value;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySaveCopy, value);
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
    } else {
      engineReady.value = false;
      engineError.value = (result['error'] ?? 'Engine init failed') as String;
    }

    final Map<String, dynamic> info = await Engine.info();
    if (info['ok'] == true && info['sdkInt'] is num) {
      sdkInt.value = (info['sdkInt'] as num).toInt();
    } else if (result['sdkInt'] is num) {
      sdkInt.value = (result['sdkInt'] as num).toInt();
    }
  }
}
