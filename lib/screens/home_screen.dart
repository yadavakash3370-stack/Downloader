import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/download_item.dart';
import '../models/media_info.dart';
import '../services/engine.dart';
import '../services/library_store.dart';
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

  static const List<List<String>> _platforms = <List<String>>[
    <String>['brand-youtube', 'YouTube', '0xFFFF0033'],
    <String>['brand-instagram', 'Instagram', '0xFFE1306C'],
    <String>['brand-facebook', 'Facebook', '0xFF1877F2'],
    <String>['brand-tiktok', 'TikTok', '0xFFFFFFFF'],
    <String>['brand-x', 'X', '0xFFFFFFFF'],
    <String>['brand-vimeo', 'Vimeo', '0xFF1AB7EA'],
    <String>['brand-dailymotion', 'Dailymotion', '0xFF00AAFF'],
    <String>['globe', '1000+ sites', '0xFF22D3EE'],
  ];

  @override
  void initState() {
    super.initState();
    _subscription = Engine.events.listen(_onEngineEvent);
    _controller.addListener(_onUrlChanged);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.removeListener(_onUrlChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onUrlChanged() {
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------- engine

  void _onEngineEvent(EngineEvent event) {
    if (!mounted) return;
    final int index = _jobs.indexWhere((_ActiveJob job) => job.id == event.jobId);
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
    setState(() {});
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

    final Map<String, dynamic> result = await Engine.probe(url);
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
    if (info == null) return;
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
    );

    if (!mounted) return;
    if (result['ok'] != true) {
      final String message = (result['error'] ?? 'Download start nahi hua') as String;
      final int index = _jobs.indexWhere((_ActiveJob job) => job.id == jobId);
      // The 'failed' event already updates the card - only handle the case
      // where the job never started (invalid url, engine error, ...).
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
    final Map<String, dynamic> result = await Engine.streamUrl(info.url);
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
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      children: <Widget>[
        _header(),
        const SizedBox(height: 20),
        _urlCard(),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 12),
          _errorCard(_error!),
        ],
        if (_analyzing) ...<Widget>[
          const SizedBox(height: 14),
          const _AnalyzingCard(),
        ],
        if (_info != null) ...<Widget>[
          const SizedBox(height: 14),
          _resultCard(_info!),
        ],
        if (_jobs.isNotEmpty) ...<Widget>[
          const SizedBox(height: 22),
          _sectionTitle('Downloads in progress', 'bolt'),
          const SizedBox(height: 10),
          ..._jobs.map(_jobCard),
        ],
        const SizedBox(height: 24),
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
          borderRadius: BorderRadius.circular(15),
          child: SvgPicture.asset('assets/icons/logo.svg', width: 46, height: 46),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'VideoGrab',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Download • Play • Offline',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.muted,
                  letterSpacing: 0.4,
                ),
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
                width: 7,
                height: 7,
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
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              const IconBadge(
                'link',
                size: 38,
                iconSize: 18,
                color: AppColors.secondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _analyze(),
                  style: const TextStyle(fontSize: 13.5, color: AppColors.text),
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
                  setState(() {
                    _info = null;
                    _error = null;
                  });
                }),
              const SizedBox(width: 6),
              _miniButton('paste', _paste, accent: AppColors.secondary),
            ],
          ),
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
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: AppIcon(icon, size: 17, color: accent ?? AppColors.muted),
        ),
      ),
    );
  }

  Widget _errorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.danger.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const AppIcon('info', size: 18, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppColors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultCard(MediaInfo info) {
    final QualityOption selected = info.options[_quality];
    return AppCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Stack(
              children: <Widget>[
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _thumbnail(info.thumbnail),
                ),
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
                      icon: const AppIcon(
                        'clock',
                        size: 11,
                        color: AppColors.text,
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    info.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.32,
                    ),
                  ),
                  if (info.uploader.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 5),
                    Text(
                      info.uploader,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      const AppIcon('film', size: 14, color: AppColors.muted),
                      const SizedBox(width: 6),
                      Text(
                        'Quality chunein',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.muted,
                          letterSpacing: 0.3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List<Widget>.generate(info.options.length, (int i) {
                      return _qualityChip(info.options[i], i == _quality, () {
                        setState(() => _quality = i);
                      });
                    }),
                  ),
                  if (info.lite) ...<Widget>[
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        const AppIcon(
                          'info',
                          size: 13,
                          color: AppColors.warning,
                        ),
                        const SizedBox(width: 7),
                        const Expanded(
                          child: Text(
                            'Lite build: single-file formats (720p tak). Full APK me zyada quality milegi.',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: AppColors.muted,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: GradientButton(
                          label: selected.audioOnly
                              ? 'Download audio'
                              : 'Download',
                          icon: 'download',
                          onPressed: _download,
                        ),
                      ),
                      const SizedBox(width: 10),
                      AppOutlineButton(
                        label: 'Play',
                        icon: 'play',
                        busy: _resolvingStream,
                        onPressed: _resolvingStream ? null : _play,
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          gradient: active ? AppColors.gradient : null,
          color: active ? null : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: active ? Colors.transparent : AppColors.stroke,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AppIcon(
              option.audioOnly ? 'music' : 'film',
              size: 13,
              color: active ? const Color(0xFF08080F) : AppColors.muted,
            ),
            const SizedBox(width: 7),
            Text(
              option.label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: active ? const Color(0xFF08080F) : AppColors.text,
              ),
            ),
            if (option.bytes > 0) ...<Widget>[
              const SizedBox(width: 6),
              Text(
                formatBytes(option.bytes),
                style: TextStyle(
                  fontSize: 10.5,
                  color: active
                      ? const Color(0xFF08080F).withOpacity(0.7)
                      : AppColors.muted,
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
        child: const AppIcon('film', size: 34, color: AppColors.muted),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
        return Container(
          color: AppColors.surfaceAlt,
          alignment: Alignment.center,
          child: const AppIcon('film', size: 34, color: AppColors.muted),
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
            width: 22,
            height: 22,
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
      padding: const EdgeInsets.all(13),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              IconBadge(
                job.finished && job.error != null ? 'info' : 'film',
                size: 38,
                iconSize: 18,
                color: job.finished && job.error != null
                    ? AppColors.danger
                    : AppColors.secondary,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      job.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      meta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: job.error != null
                            ? AppColors.danger
                            : AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (!job.finished)
                _miniButton('close', () {
                  Engine.cancel(job.id);
                })
              else
                _miniButton('close', () {
                  setState(() {
                    _jobs.removeWhere((_ActiveJob entry) => entry.id == job.id);
                  });
                }),
            ],
          ),
          if (!job.finished) ...<Widget>[
            const SizedBox(height: 11),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: job.progress <= 0 ? null : job.progress,
                minHeight: 5,
                backgroundColor: AppColors.surfaceAlt,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.secondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, String icon) {
    return Row(
      children: <Widget>[
        AppIcon(icon, size: 15, color: AppColors.secondary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _platformGrid() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _platforms.map((List<String> platform) {
        final Color color = Color(int.parse(platform[2]));
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.stroke),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppIcon(platform[0], size: 15, color: color),
              const SizedBox(width: 8),
              Text(
                platform[1],
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _AnalyzingCard extends StatelessWidget {
  const _AnalyzingCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: <Widget>[
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Link analyze ho raha hai…',
              style: TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}
