import 'package:flutter/material.dart';

import '../services/app_links.dart';
import '../services/engine.dart';
import '../services/library_store.dart';
import '../services/settings_store.dart';
import '../theme.dart';
import '../widgets/svg_icon.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'settings_screen.dart';
import 'study_screen.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    Engine.bind();
    _boot();
  }

  Future<void> _boot() async {
    await SettingsStore.load();
    await LibraryStore.load();
    await SettingsStore.bootEngine();
    if (mounted) setState(() {});
  }

  void _openInDownload(PendingLink link) {
    AppLinks.openInDownloadTab(link);
    setState(() => _index = 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: <Widget>[
          const Positioned.fill(child: _Backdrop()),
          SafeArea(
            bottom: false,
            child: IndexedStack(
              index: _index,
              children: <Widget>[
                const HomeScreen(),
                const LibraryScreen(),
                const SettingsScreen(),
                StudyScreen(
                  active: _index == 3,
                  onOpenInDownload: _openInDownload,
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ValueListenableBuilder<bool>(
            valueListenable: SettingsStore.engineBooting,
            builder: (BuildContext context, bool booting, Widget? child) {
              return booting ? const _EngineBanner() : const SizedBox.shrink();
            },
          ),
          _BottomBar(
            index: _index,
            onChanged: (int value) => setState(() => _index = value),
          ),
        ],
      ),
    );
  }
}

/// Very subtle top tint - professional rather than neon.
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[Color(0xFF101219), AppColors.bg],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: <double>[0.0, 0.55],
        ),
      ),
    );
  }
}

class _EngineBanner extends StatelessWidget {
  const _EngineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      color: AppColors.surfaceAlt,
      child: Row(
        children: <Widget>[
          const SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 11),
          const Expanded(
            child: Text(
              'Engine taiyaar ho raha hai (pehli baar 10–20s)',
              style: TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  static const List<List<String>> _tabs = <List<String>>[
    <String>['search', 'Download'],
    <String>['folder', 'Library'],
    <String>['graduation', 'PW'],
    <String>['settings', 'Settings'],
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.stroke)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: List<Widget>.generate(_tabs.length, (int i) {
              final bool active = i == index;
              return Expanded(
                child: InkWell(
                  onTap: () => onChanged(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      AppIcon(
                        _tabs[i][0],
                        size: 20,
                        color: active ? AppColors.primary : AppColors.muted,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _tabs[i][1],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                          color: active ? AppColors.text : AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
