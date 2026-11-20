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

  static const List<int> _speeds = <int>[1, 4, 8, 16];

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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Library clear karein?', style: TextStyle(fontSize: 16)),
          content: const Text(
            'List se saare items hat jayenge. Files device me rahengi.',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted),
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
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: <Widget>[
        _header(),
        const SizedBox(height: 18),
        _sectionLabel('PERFORMANCE', 'bolt'),
        const SizedBox(height: 9),
        _speedCard(),
        const SizedBox(height: 18),
        _sectionLabel('DOWNLOADER ENGINE', 'refresh'),
        const SizedBox(height: 9),
        _engineCard(),
        const SizedBox(height: 18),
        _sectionLabel('STORAGE', 'folder'),
        const SizedBox(height: 9),
        _storageCard(),
        const SizedBox(height: 18),
        _sectionLabel('GUIDE', 'info'),
        const SizedBox(height: 9),
        _howToCard(),
        const SizedBox(height: 18),
        _aboutCard(),
      ],
    );
  }

  Widget _header() {
    return const Row(
      children: <Widget>[
        IconBadge('settings', size: 38, iconSize: 18),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Settings', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              SizedBox(height: 3),
              Text('Speed, engine, storage', style: TextStyle(fontSize: 11, color: AppColors.muted)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text, String icon) {
    return Row(
      children: <Widget>[
        AppIcon(icon, size: 12, color: AppColors.muted),
        const SizedBox(width: 7),
        Text(
          text,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: AppColors.muted,
          ),
        ),
      ],
    );
  }

  Widget _speedCard() {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Row(
            children: <Widget>[
              IconBadge('bolt', size: 34, iconSize: 16, gradient: true),
              SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Download speed', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    SizedBox(height: 3),
                    Text(
                      'Parallel fragments + chunked HTTP requests',
                      style: TextStyle(fontSize: 10.5, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          ValueListenableBuilder<int>(
            valueListenable: SettingsStore.concurrency,
            builder: (BuildContext context, int value, Widget? child) {
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _speeds.map((int speed) {
                  final bool active = speed == value;
                  return GestureDetector(
                    onTap: () => SettingsStore.setConcurrency(speed),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: active ? AppColors.primary : AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: active ? AppColors.primary : AppColors.stroke,
                        ),
                      ),
                      child: Text(
                        speed == 16 ? '16 • Turbo' : '$speed×',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: active ? Colors.white : AppColors.text,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 11),
          const Text(
            'Zyada connections = tez download. Slow network par 4× behtar ho sakta hai.',
            style: TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _engineCard() {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const IconBadge('refresh', size: 34, iconSize: 16),
              const SizedBox(width: 11),
              const Expanded(
                child: Text(
                  'yt-dlp extractor',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ValueListenableBuilder<String>(
                valueListenable: SettingsStore.engineVersion,
                builder: (BuildContext context, String version, Widget? child) {
                  return AppPill(
                    label: version.isEmpty ? 'version —' : 'v$version',
                    color: AppColors.muted,
                  );
                },
              ),
              ValueListenableBuilder<bool>(
                valueListenable: SettingsStore.hasFfmpeg,
                builder: (BuildContext context, bool full, Widget? child) {
                  return AppPill(
                    label: full ? 'Full build · HD merge' : 'Lite build',
                    color: full ? AppColors.secondary : AppColors.warning,
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Extractor purana ho jaye to update karein — latest yt-dlp GitHub se aata hai.',
            style: TextStyle(fontSize: 10.8, color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 13),
          // Full-width stacked buttons: kabhi bhi screen ke bahar nahi jayenge.
          AppOutlineButton(
            label: _updating ? 'Updating…' : 'Update engine',
            icon: 'refresh',
            busy: _updating,
            height: 44,
            onPressed: _updating ? null : _updateEngine,
          ),
          const SizedBox(height: 9),
          AppOutlineButton(
            label: 'Clear library',
            icon: 'trash',
            height: 44,
            onPressed: _clearLibrary,
          ),
        ],
      ),
    );
  }

  Widget _storageCard() {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          const IconBadge('folder', size: 34, iconSize: 16),
          const SizedBox(width: 11),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Downloads folder me copy', style: TextStyle(fontSize: 12.8, fontWeight: FontWeight.w700)),
                SizedBox(height: 3),
                Text(
                  'Har file ki copy Download/VideoGrab me bhi jayegi',
                  style: TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
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
      <String>['search', 'Download tab me Analyze dabayein'],
      <String>['hd', 'Quality chun kar Download ya Play karein'],
      <String>['folder', 'Library tab se offline dekhein'],
      <String>['graduation', 'PW tab me login karke lectures dekhein / save karein'],
    ];

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ...steps.map((List<String> step) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: <Widget>[
                  IconBadge(step[0], size: 26, iconSize: 13, radius: 8, color: AppColors.secondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      step[1],
                      style: const TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.4),
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
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Row(
            children: <Widget>[
              IconBadge('logo', size: 34, iconSize: 17),
              SizedBox(width: 11),
              Expanded(
                child: Text(
                  'VideoGrab 1.1.0',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
              AppPill(label: 'Open source', color: AppColors.secondary),
            ],
          ),
          const SizedBox(height: 11),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              AppPill(label: 'SVG icons only', color: AppColors.muted),
              AppPill(label: 'On-device', color: AppColors.muted),
              AppPill(label: 'No watermark', color: AppColors.muted),
            ],
          ),
          const SizedBox(height: 11),
          const Text(
            'Sab kuch phone par offline process hota hai — koi server nahi. 1000+ sites ke links, in-app player aur PW study browser ek hi app me.',
            style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.55),
          ),
        ],
      ),
    );
  }
}
