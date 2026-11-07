import 'package:flutter/material.dart';

import '../services/engine.dart';
import '../services/library_store.dart';
import '../services/settings_store.dart';
import '../theme.dart';
import '../widgets/svg_icon.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'settings_screen.dart';

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
              children: const <Widget>[
                HomeScreen(),
                LibraryScreen(),
                SettingsScreen(),
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

class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[Color(0xFF0C0C16), AppColors.bg],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            top: -160,
            left: -110,
            child: _Glow(color: AppColors.primary, size: 340),
          ),
          Positioned(
            top: 20,
            right: -140,
            child: _Glow(color: AppColors.secondary, size: 300),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[color.withOpacity(0.18), color.withOpacity(0.0)],
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      color: AppColors.surfaceAlt,
      child: Row(
        children: <Widget>[
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Downloader engine taiyaar ho raha hai (first launch me 10-20s)',
              style: TextStyle(color: AppColors.muted, fontSize: 11.5),
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
    <String>['settings', 'Settings'],
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0B0B14),
        border: Border(top: BorderSide(color: AppColors.stroke)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
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
                        size: 22,
                        color: active ? AppColors.secondary : AppColors.muted,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _tabs[i][1],
                        style: TextStyle(
                          fontSize: 10.5,
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
