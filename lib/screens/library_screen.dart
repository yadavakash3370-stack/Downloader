import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/download_item.dart';
import '../services/engine.dart';
import '../services/library_store.dart';
import '../services/settings_store.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/svg_icon.dart';
import 'player_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String? _busyId;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  Future<void> _play(DownloadItem item) async {
    final File file = File(item.path);
    if (!await file.exists()) {
      _snack('File device me nahi mili — delete karke dobara download karein');
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          title: item.title,
          filePath: item.path,
          thumbnail: item.thumbnail,
        ),
      ),
    );
  }

  Future<void> _saveCopy(DownloadItem item) async {
    if (Platform.isAndroid) {
      final int sdk = SettingsStore.sdkInt.value;
      if (sdk > 0 && sdk < 29) {
        final PermissionStatus status = await Permission.storage.request();
        if (!status.isGranted) {
          _snack('Save karne ke liye storage permission chahiye');
          return;
        }
      }
    }
    setState(() => _busyId = item.id);
    final Map<String, dynamic> result =
        await Engine.saveCopy(item.path, fileNameOf(item.path));
    if (!mounted) return;
    setState(() => _busyId = null);
    if (result['ok'] == true) {
      final String publicPath = (result['publicPath'] ?? '') as String;
      await LibraryStore.update(item.copyWith(publicPath: publicPath));
      _snack(publicPath.startsWith('content://')
          ? 'Downloads/VideoGrab folder me save ho gaya'
          : 'Saved: $publicPath');
    } else {
      _snack((result['error'] ?? 'Save nahi ho paya') as String);
    }
  }

  Future<void> _delete(DownloadItem item) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Delete video?', style: TextStyle(fontSize: 17)),
          content: Text(
            '${item.title}\n\nYe file device se hata di jayegi.',
            style: const TextStyle(fontSize: 13, color: AppColors.muted),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(
                'Delete',
                style: TextStyle(color: AppColors.danger),
              ),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;

    setState(() => _busyId = item.id);
    await Engine.deleteFile(item.path);
    if (item.publicPath.isNotEmpty) {
      await Engine.deleteFile(item.publicPath);
    }
    await LibraryStore.remove(item.id);
    if (!mounted) return;
    setState(() => _busyId = null);
    _snack('Deleted');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
          child: Row(
            children: <Widget>[
              const IconBadge('folder', size: 40, iconSize: 19),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Offline library',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Download ki hui videos, app ke andar',
                      style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              ValueListenableBuilder<List<DownloadItem>>(
                valueListenable: LibraryStore.items,
                builder: (
                  BuildContext context,
                  List<DownloadItem> items,
                  Widget? child,
                ) {
                  return AppPill(label: '${items.length}');
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: ValueListenableBuilder<List<DownloadItem>>(
            valueListenable: LibraryStore.items,
            builder: (
              BuildContext context,
              List<DownloadItem> items,
              Widget? child,
            ) {
              if (items.isEmpty) return const _EmptyLibrary();
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
                itemCount: items.length,
                separatorBuilder: (BuildContext context, int index) =>
                    const SizedBox(height: 10),
                itemBuilder: (BuildContext context, int index) {
                  return _tile(items[index]);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _tile(DownloadItem item) {
    final bool busy = _busyId == item.id;
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 96,
                  height: 68,
                  child: _thumb(item.thumbnail),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${formatBytes(item.sizeBytes)}  •  ${item.ext.toUpperCase()}  •  ${formatDate(item.createdAt)}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.muted,
                      ),
                    ),
                    if (item.publicPath.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 6),
                      const AppPill(
                        label: 'In Downloads/VideoGrab',
                        color: AppColors.success,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _action(
                  icon: 'play',
                  label: 'Play',
                  onTap: busy ? null : () => _play(item),
                  accent: AppColors.secondary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _action(
                  icon: 'folder',
                  label: busy ? 'Saving…' : 'Save copy',
                  onTap: busy ? null : () => _saveCopy(item),
                ),
              ),
              const SizedBox(width: 8),
              _action(
                icon: 'trash',
                label: '',
                onTap: busy ? null : () => _delete(item),
                accent: AppColors.danger,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _thumb(String url) {
    if (url.isEmpty) {
      return Container(
        color: AppColors.surfaceAlt,
        alignment: Alignment.center,
        child: const AppIcon('film', size: 22, color: AppColors.muted),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
        return Container(
          color: AppColors.surfaceAlt,
          alignment: Alignment.center,
          child: const AppIcon('film', size: 22, color: AppColors.muted),
        );
      },
    );
  }

  Widget _action({
    required String icon,
    required String label,
    required VoidCallback? onTap,
    Color? accent,
  }) {
    return Material(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 38,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.stroke),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppIcon(icon, size: 15, color: accent ?? AppColors.text),
              if (label.isNotEmpty) ...<Widget>[
                const SizedBox(width: 7),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppColors.stroke),
              ),
              alignment: Alignment.center,
              child: const AppIcon('film', size: 34, color: AppColors.muted),
            ),
            const SizedBox(height: 18),
            const Text(
              'Abhi koi download nahi',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Home tab se link paste karke\npehli video download karein',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.muted,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
