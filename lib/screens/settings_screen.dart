import 'package:flutter/material.dart';

import '../services/engine.dart';
import '../services/library_store.dart';
import '../services/settings_store.dart';
import '../theme.dart';
import '../widgets/svg_icon.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _updating = false;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  Future<void> _updateEngine() async {
    setState(() => _updating = true);
    final Map<String, dynamic> result = await Engine.updateEngine();
    if (!mounted) return;
    setState(() => _updating = false);
    if (result['ok'] == true) {
      SettingsStore.engineVersion.value = (result['version'] ?? '') as String;
      _snack('yt-dlp updated: ${result['status']}');
    } else {
      _snack((result['error'] ?? 'Update failed') as String);
    }
  }

  Future<void> _clearLibrary() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Library clear karein?', style: TextStyle(fontSize: 17)),
          content: const Text(
            'List se saare items hat jayenge. Files device me rahengi.',
            style: TextStyle(fontSize: 13, color: AppColors.muted),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Clear', style: TextStyle(color: AppColors.danger)),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;
    await LibraryStore.clear();
    _snack('Library clear ho gayi');
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      children: <Widget>[
        Row(
          children: <Widget>[
            const IconBadge('settings', size: 40, iconSize: 19),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Settings',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 2),
                Text(
                  'Engine, storage aur app info',
                  style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        _engineCard(),
        const SizedBox(height: 12),
        _storageCard(),
        const SizedBox(height: 12),
        _howToCard(),
        const SizedBox(height: 12),
        _aboutCard(),
      ],
    );
  }

  Widget _engineCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const IconBadge('bolt', size: 36, iconSize: 17, gradient: true),
              const SizedBox(width: 11),
              const Expanded(
                child: Text(
                  'Downloader engine',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: SettingsStore.engineReady,
                builder: (BuildContext context, bool ready, Widget? child) {
                  return AppPill(
                    label: ready ? 'Active' : 'Setup',
                    color: ready ? AppColors.success : AppColors.warning,
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<String>(
            valueListenable: SettingsStore.engineVersion,
            builder: (BuildContext context, String version, Widget? child) {
              return Text(
                version.isEmpty
                    ? 'yt-dlp version: —'
                    : 'yt-dlp version: $version',
                style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
              );
            },
          ),
          const SizedBox(height: 6),
          const Text(
            'Extractor purana ho jaye to engine update karein — latest yt-dlp GitHub se download hota hai.',
            style: TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: AppOutlineButton(
                  label: _updating ? 'Updating…' : 'Update engine',
                  icon: 'refresh',
                  busy: _updating,
                  height: 46,
                  onPressed: _updating ? null : _updateEngine,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppOutlineButton(
                  label: 'Clear library',
                  icon: 'trash',
                  height: 46,
                  onPressed: _clearLibrary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _storageCard() {
    return AppCard(
      child: Row(
        children: <Widget>[
          const IconBadge('folder', size: 36, iconSize: 17),
          const SizedBox(width: 11),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Downloads folder me copy',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 3),
                Text(
                  'Har download ki ek copy Download/VideoGrab me bhi jayegi',
                  style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.4),
                ),
              ],
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: SettingsStore.saveCopy,
            builder: (BuildContext context, bool value, Widget? child) {
              return Switch(
                value: value,
                activeColor: AppColors.secondary,
                onChanged: (bool next) => SettingsStore.setSaveCopy(next),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _howToCard() {
    const List<List<String>> steps = <List<String>>[
      <String>['link', 'Video ka link copy karein'],
      <String>['paste', 'Home tab me paste karke Analyze dabayein'],
      <String>['download', 'Quality chun kar Download ya Play karein'],
      <String>['folder', 'Library tab se offline video dekhein'],
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Kaise use karein',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          ...steps.map((List<String> step) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: <Widget>[
                  IconBadge(
                    step[0],
                    size: 28,
                    iconSize: 14,
                    radius: 9,
                    color: AppColors.secondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      step[1],
                      style: const TextStyle(
                        fontSize: 11.8,
                        color: AppColors.muted,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _aboutCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const IconBadge('shield', size: 36, iconSize: 17),
              const SizedBox(width: 11),
              const Expanded(
                child: Text(
                  'VideoGrab 1.0.0',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
              const AppPill(label: 'Open source'),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Downloads sirf un videos ke liye karein jinke aap owner hain ya jinke liye platform ki terms allow karti hain. Sab kuch device par offline process hota hai — koi server nahi.',
            style: TextStyle(fontSize: 11.2, color: AppColors.muted, height: 1.55),
          ),
        ],
      ),
    );
  }
}
