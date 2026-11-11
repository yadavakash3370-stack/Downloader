import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/download_item.dart';

/// Persisted list of finished downloads.
class LibraryStore {
  static const String _key = 'videograb_library_v1';

  static final ValueNotifier<List<DownloadItem>> items =
      ValueNotifier<List<DownloadItem>>(<DownloadItem>[]);

  static Future<void> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      items.value = decoded
          .whereType<Map<dynamic, dynamic>>()
          .map((Map<dynamic, dynamic> entry) =>
              DownloadItem.fromJson(Map<String, dynamic>.from(entry)))
          .toList();
    } catch (_) {
      items.value = <DownloadItem>[];
    }
  }

  static Future<void> _persist() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(items.value.map((DownloadItem item) => item.toJson()).toList()),
    );
  }

  static Future<void> add(DownloadItem item) async {
    items.value = <DownloadItem>[
      item,
      ...items.value.where((DownloadItem entry) => entry.id != item.id),
    ];
    await _persist();
  }

  static Future<void> update(DownloadItem item) async {
    items.value = items.value
        .map((DownloadItem entry) => entry.id == item.id ? item : entry)
        .toList();
    await _persist();
  }

  static Future<void> remove(String id) async {
    items.value =
        items.value.where((DownloadItem entry) => entry.id != id).toList();
    await _persist();
  }

  static Future<void> clear() async {
    items.value = <DownloadItem>[];
    await _persist();
  }
}
