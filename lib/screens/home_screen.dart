import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/download_item.dart';
import '../models/media_info.dart';
import '../services/app_links.dart';
import '../services/engine.dart';
import '../services/library_store.dart';
import '../services/platform_detector.dart';
import '../services/settings_store.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/svg_icon.dart';
import 'player_screen.dart';

class _ActiveJob {
  _ActiveJob({required this.id, required this.title, required this.thumbnail});

  final String id;
  final String title;
  final String thumbnail;
  double progress = 0;
  int eta = 0;
  String status = 'Starting…';
  String? error;
  bool finished = false;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<_ActiveJob> _jobs = <_ActiveJob>[];

  StreamSubscription<EngineEvent>? _subscription;
  bool _analyzing = false;
  bool _resolvingStream = false;
  String? _error;
  MediaInfo? _info;
  int _quality = 0;
  Map<String, String> _headers = const <String, String>{};

  static const List<PlatformInfo> _platforms = <PlatformInfo>[
    PlatformDetector.youtube,
    PlatformDetector.instagram,
    PlatformDetector.facebook,
    PlatformDetector.tiktok,
    PlatformDetector.x,
    PlatformDetector.vimeo,
    PlatformDetector.dailymotion,
    PlatformDetector.pw,
    PlatformDetector.other,
  ];

  @override
  void initState() {
    super.initState();
    _subscription = Engine.events.listen(_onEngineEvent);
    _controller.addListener(_onUrlChanged);
    AppLinks.pending.addListener(_onPendingLink);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.removeListener(_onUrlChanged);
    AppLinks.pending.removeListener(_onPendingLink);
    _controller.dispose();
    super.dispose();
  }

  void _onUrlChanged() {
    if (mounted) setState(() {});
  }

  /// PW tab ne link bheja hai -> turant analyze karo.
  void _onPendingLink() {
    final PendingLink? link = AppLinks.take();
    if (link == null || !mounted) return;
    _controller.text = link.url;
    _headers = link.headers;
    setState(() {
      _info = null;
      _error = null;
      _quality = 0;
    });
    Future<void>.microtask(_analyze);
  }

  PlatformInfo? get _detected => PlatformDetector.detect(_controller.text);

  // ---------------------------------------------------------------- engine

  void _onEngineEvent(EngineEvent event) {
    if (!mounted) return;
    final int index =
        _jobs.indexWhere((_ActiveJob job) => job.id == event.jobId);
    if (index < 0) return;
    final _ActiveJob job = _jobs[index];

    if (event.type == 'done') {
      job.progress = 1;
      job.finished = true;
      job.status = 'Completed';
      _persist(job, event);
    }

    setState(() {
      switch (event.type) {
        case 'progress':
          job.progress = (event.progress / 100).clamp(0.0, 1.0).toDouble();
          job.eta = event.eta;
          job.status = 'Downloading';
          break;
        case 'stage':
          job.status = event.message.isEmpty ? 'Preparing…' : event.message;
          break;
        case 'failed':
          job.error = event.message;
          job.finished = true;
          job.status = 'Failed';
          break;
        case 'cancelled':
          job.finished = true;
          job.status = 'Cancelled';
          break;
        default:
          break;
      }
    });

    if (event.type == 'done') {
      _snack(
        event.publicPath.isEmpty
            ? 'Download complete — Library me saved'
            : 'Download complete — Downloads/VideoGrab me bhi saved',
      );
    } else if (event.type == 'failed') {
      _snack(event.message.isEmpty ? 'Download failed' : event.message);
    }
  }

  Future<void> _persist(_ActiveJob job, EngineEvent event) async {
    final String name = event.name.isEmpty ? event.path : event.name;
    final int dot = name.lastIndexOf('.');
    final String ext = dot >= 0 ? name.substring(dot + 1) : 'mp4';
    await LibraryStore.add(
      DownloadItem(
        id: job.id,
        title: job.title,
        path: event.path,
        ext: ext,
        sizeBytes: event.size,
        createdAt: DateTime.now(),
        thumbnail: job.thumbnail,
        publicPath: event.publicPath,
      ),
    );
  }

  // --------------------------------------------------------------- actions

  Future<void> _paste() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String text = (data?.text ?? '').trim();
    if (text.isEmpty) {
      _snack('Clipboard khali hai');
      return;
    }
    final RegExpMatch? match = RegExp(r'https?://[^\s]+').firstMatch(text);
    _controller.text = match?.group(0) ?? text;
    _headers = const <String, String>{};
    setState(() {
      _info = null;
      _error = null;
    });
  }

  Future<void> _analyze() async {
    final String url = _controller.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Pehle video ka link paste karein');
      return;
    }
    if (!url.startsWith('http')) {
      setState(() => _error = 'Link http:// ya https:// se shuru hona chahiye');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _analyzing = true;
      _error = null;
      _info = null;
      _quality = 0;
    });

    if (!SettingsStore.engineReady.value) {
      await SettingsStore.bootEngine();
    }

    final Map<String, dynamic> result =
        await Engine.probe(url, headers: _headers);
    if (!mounted) return;

    if (result['ok'] == true) {
      setState(() {
        _info = MediaInfo.fromMap(result);
        _analyzing = false;
      });
    } else {
      setState(() {
        _error = (result['error'] ?? 'Video info nahi mil paya') as String;
        _analyzing = false;
      });
    }
  }

  Future<void> _download() async {
    final MediaInfo? info = _info;
    if (info == null || _quality >= info.options.length) return;
    final QualityOption option = info.options[_quality];
    final String jobId = DateTime.now().microsecondsSinceEpoch.toString();

    setState(() {
      _jobs.insert(
        0,
        _ActiveJob(id: jobId, title: info.title, thumbnail: info.thumbnail),
      );
    });

    final Map<String, dynamic> result = await Engine.startDownload(
      jobId: jobId,
      url: info.url,
      format: option.format,
      audioOnly: option.audioOnly,
      alsoSave: SettingsStore.saveCopy.value,
      title: info.title,
      concurrency: SettingsStore.concurrency.value,
      headers: _headers,
    );

    if (!mounted) return;
    if (result['ok'] != true) {
      final String message =
          (result['error'] ?? 'Download start nahi hua') as String;
      final int index =
          _jobs.indexWhere((_ActiveJob job) => job.id == jobId);
      if (index >= 0 && !_jobs[index].finished) {
        setState(() {
          _jobs[index]
            ..error = message
            ..finished = true
            ..status = 'Failed';
        });
        _snack(message);
      }
    }
  }

  Future<void> _play() async {
    final MediaInfo? info = _info;
    if (info == null) return;
    setState(() => _resolvingStream = true);
    final Map<String, dynamic> result =
        await Engine.streamUrl(info.url, headers: _headers);
    if (!mounted) return;
    setState(() => _resolvingStream = false);

    if (result['ok'] == true && result['url'] is String) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlayerScreen(
            title: info.title,
            networkUrl: result['url'] as String,
            thumbnail: info.thumbnail,
          ),
        ),
      );
    } else {
      _snack((result['error'] ?? 'Stream available nahi hai') as String);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  // ------------------------------------------------------------------- ui

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: <Widget>[
        _header(),
        const SizedBox(height: 18),
        _urlCard(),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 12),
          _errorCard(_error!),
        ],
        if (_analyzing) ...<Widget>[
          const SizedBox(height: 12),
          _analyzingCard(),
        ],
        if (_info != null) ...<Widget>[
          const SizedBox(height: 12),
          _resultCard(_info!),
        ],
        if (_jobs.isNotEmpty) ...<Widget>[
          const SizedBox(height: 22),
          _sectionTitle('Downloads', 'bolt'),
          const SizedBox(height: 10),
          ..._jobs.map(_jobCard),
        ],
        const SizedBox(height: 22),
        _engineCard(),
        const SizedBox(height: 22),
        _sectionTitle('Supported platforms', 'globe'),
        const SizedBox(height: 10),
        _platformGrid(),
      ],
    );
  }

  Widget _header() {
    return Row(
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: SvgPicture.asset('assets/icons/logo.svg', width: 42, height: 42),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'VideoGrab',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'Download • Play • Offline',
                style: TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: SettingsStore.engineReady,
          builder: (BuildContext context, bool ready, Widget? child) {
            return AppPill(
              label: ready ? 'Ready' : 'Starting',
              color: ready ? AppColors.success : AppColors.warning,
              icon: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ready ? AppColors.success : AppColors.warning,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _urlCard() {
    final PlatformInfo? platform = _detected;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const IconBadge('link', size: 38, iconSize: 18, color: AppColors.secondary),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  maxLines: 1,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _analyze(),
                  style: const TextStyle(fontSize: 13, color: AppColors.text),
                  decoration: const InputDecoration(
                    hintText: 'Video link yahan paste karein…',
                    filled: false,
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              if (_controller.text.isNotEmpty)
                _miniButton('close', () {
                  _controller.clear();
                  _headers = const <String, String>{};
                  setState(() {
                    _info = null;
                    _error = null;
                  });
                }),
              const SizedBox(width: 6),
              _miniButton('paste', _paste, accent: AppColors.secondary),
            ],
          ),
          if (platform != null) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: <Widget>[
                  PlatformBadge(platform: platform),
                  const Spacer(),
                  const AppIcon('bolt', size: 12, color: AppColors.success),
                  const SizedBox(width: 5),
                  const Text(
                    'Instant detect',
                    style: TextStyle(fontSize: 10, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          GradientButton(
            label: 'Analyze link',
            icon: 'search',
            busy: _analyzing,
            onPressed: _analyzing ? null : _analyze,
          ),
        ],
      ),
    );
  }

  Widget _miniButton(String icon, VoidCallback onTap, {Color? accent}) {
    return Material(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: AppIcon(icon, size: 16, color: accent ?? AppColors.muted),
        ),
      ),
    );
  }

  Widget _errorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.danger.withOpacity(0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const AppIcon('info', size: 17, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, height: 1.45, color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }

  Widget _analyzingCard() {
    final PlatformInfo? platform = _detected;
    return AppCard(
      child: Row(
        children: <Widget>[
          const SizedBox(
            width: 17,
            height: 17,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Formats dhoondh rahe hain…',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  platform == null
                      ? 'Link analyze ho raha hai'
                      : '${platform.label} · quality list taiyaar ho rahi hai',
                  style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultCard(MediaInfo info) {
    final int safeIndex = _quality.clamp(0, info.options.length - 1).toInt();
    final QualityOption selected = info.options[safeIndex];
    final PlatformInfo? platform = _detected;

    return AppCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Stack(
              children: <Widget>[
                AspectRatio(aspectRatio: 16 / 9, child: _thumbnail(info.thumbnail)),
                Positioned(
                  left: 10,
                  top: 10,
                  child: AppPill(
                    label: info.extractor.isEmpty ? 'Video' : info.extractor,
                    color: AppColors.text,
                    background: Colors.black.withOpacity(0.55),
                  ),
                ),
                if (info.duration > 0)
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: AppPill(
                      label: formatDuration(info.duration),
                      color: AppColors.text,
                      background: Colors.black.withOpacity(0.55),
                      icon: const AppIcon('clock', size: 11, color: AppColors.text),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    info.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.35),
                  ),
                  if (info.uploader.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      info.uploader,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                    ),
                  ],
                  const SizedBox(height: 13),
                  Row(
                    children: <Widget>[
                      if (platform != null) ...<Widget>[
                        PlatformBadge(platform: platform),
                        const Spacer(),
                      ],
                      const AppIcon('hd', size: 13, color: AppColors.muted),
                      const SizedBox(width: 6),
                      const Text(
                        'Quality',
                        style: TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: List<Widget>.generate(info.options.length, (int i) {
                      return _qualityChip(info.options[i], i == safeIndex, () {
                        setState(() => _quality = i);
                      });
                    }),
                  ),
                  if (info.lite) ...<Widget>[
                    const SizedBox(height: 11),
                    const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        AppIcon('info', size: 13, color: AppColors.warning),
                        SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            'Lite APK me single-file formats milte hain (aksar 360–720p). 1080p/4K ke liye Full APK install karein.',
                            style: TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.45),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 15),
                  Row(
                    children: <Widget>[
                      Expanded(
                        flex: 3,
                        child: GradientButton(
                          label: selected.audioOnly ? 'Download audio' : 'Download',
                          icon: 'download',
                          onPressed: _download,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        flex: 2,
                        child: AppOutlineButton(
                          label: 'Play',
                          icon: 'play',
                          busy: _resolvingStream,
                          onPressed: _resolvingStream ? null : _play,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _qualityChip(QualityOption option, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? AppColors.primary : AppColors.stroke),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AppIcon(
              option.audioOnly ? 'music' : 'film',
              size: 12,
              color: active ? Colors.white : AppColors.muted,
            ),
            const SizedBox(width: 6),
            Text(
              option.label,
              style: TextStyle(
                fontSize: 11.8,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : AppColors.text,
              ),
            ),
            if (option.bytes > 0) ...<Widget>[
              const SizedBox(width: 5),
              Text(
                formatBytes(option.bytes),
                style: TextStyle(
                  fontSize: 10,
                  color: active ? Colors.white70 : AppColors.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _thumbnail(String url) {
    if (url.isEmpty) {
      return Container(
        color: AppColors.surfaceAlt,
        alignment: Alignment.center,
        child: const AppIcon('film', size: 32, color: AppColors.muted),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
        return Container(
          color: AppColors.surfaceAlt,
          alignment: Alignment.center,
          child: const AppIcon('film', size: 32, color: AppColors.muted),
        );
      },
      loadingBuilder: (
        BuildContext context,
        Widget child,
        ImageChunkEvent? progress,
      ) {
        if (progress == null) return child;
        return Container(
          color: AppColors.surfaceAlt,
          alignment: Alignment.center,
          child: const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
    );
  }

  Widget _jobCard(_ActiveJob job) {
    final String meta = job.finished
        ? (job.error ?? 'Saved to library')
        : '${(job.progress * 100).toStringAsFixed(0)}%  •  ${formatEta(job.eta)}';

    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              IconBadge(
                job.finished && job.error != null ? 'info' : 'film',
                size: 36,
                iconSize: 17,
                color: job.finished && job.error != null
                    ? AppColors.danger
                    : AppColors.secondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      job.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      meta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.8,
                        color: job.error != null ? AppColors.danger : AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              _miniButton('close', () {
                if (!job.finished) {
                  Engine.cancel(job.id);
                } else {
                  setState(() {
                    _jobs.removeWhere((_ActiveJob entry) => entry.id == job.id);
                  });
                }
              }),
            ],
          ),
          if (!job.finished) ...<Widget>[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: job.progress <= 0 ? null : job.progress,
                minHeight: 4,
                backgroundColor: AppColors.surfaceAlt,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.secondary),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Engine / build info, laid out so nothing can spill outside the screen.
  Widget _engineCard() {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Row(
            children: <Widget>[
              IconBadge('bolt', size: 32, iconSize: 16),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Engine & build',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
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
                    label: version.isEmpty ? 'yt-dlp —' : 'yt-dlp $version',
                    color: AppColors.muted,
                  );
                },
              ),
              ValueListenableBuilder<bool>(
                valueListenable: SettingsStore.hasFfmpeg,
                builder: (BuildContext context, bool full, Widget? child) {
                  return AppPill(
                    label: full ? 'Full build · 4K tak' : 'Lite build · 720p tak',
                    color: full ? AppColors.secondary : AppColors.warning,
                  );
                },
              ),
              ValueListenableBuilder<int>(
                valueListenable: SettingsStore.concurrency,
                builder: (BuildContext context, int value, Widget? child) {
                  return AppPill(
                    label: '$value parallel connections',
                    color: AppColors.primary,
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, String icon) {
    return Row(
      children: <Widget>[
        AppIcon(icon, size: 14, color: AppColors.secondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _platformGrid() {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: _platforms.map((PlatformInfo platform) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.stroke),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppIcon(platform.icon, size: 13, color: platform.color),
              const SizedBox(width: 6),
              Text(
                platform.short ?? platform.label,
                style: const TextStyle(fontSize: 10.5, color: AppColors.text),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
