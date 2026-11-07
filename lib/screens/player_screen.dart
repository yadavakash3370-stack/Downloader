import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../theme.dart';
import '../utils/format.dart';
import '../widgets/svg_icon.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    required this.title,
    super.key,
    this.filePath,
    this.networkUrl,
    this.thumbnail = '',
  });

  final String title;
  final String? filePath;
  final String? networkUrl;
  final String thumbnail;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _controller;
  String? _error;
  bool _fullscreen = false;
  bool _showControls = true;
  bool _initializing = true;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final VideoPlayerController controller;
    if (widget.filePath != null) {
      controller = VideoPlayerController.file(File(widget.filePath!));
    } else {
      controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.networkUrl ?? ''),
      );
    }
    _controller = controller;

    try {
      await controller.initialize();
      await controller.setLooping(false);
      await controller.play();
      if (!mounted) return;
      setState(() => _initializing = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Video play nahi ho paya.\n$error';
      });
    }
  }

  Future<void> _toggleFullscreen() async {
    final bool next = !_fullscreen;
    setState(() => _fullscreen = next);
    if (next) {
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.portraitUp,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  Future<void> _showSpeedSheet(VideoPlayerController controller) async {
    const List<double> speeds = <double>[0.5, 0.75, 1, 1.25, 1.5, 2];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  'Playback speed',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              ...speeds.map((double speed) {
                final bool active = controller.value.playbackSpeed == speed;
                return ListTile(
                  dense: true,
                  title: Text('${speed}x'),
                  trailing: active
                      ? const AppIcon('check', size: 16, color: AppColors.secondary)
                      : null,
                  onTap: () {
                    controller.setPlaybackSpeed(speed);
                    Navigator.of(context).pop();
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _fullscreen
          ? null
          : AppBar(
              backgroundColor: Colors.black,
              title: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
      body: _body(controller),
    );
  }

  Widget _body(VideoPlayerController? controller) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const AppIcon('info', size: 34, color: AppColors.danger),
              const SizedBox(height: 14),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.muted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      );
    }

    if (controller == null || _initializing || !controller.value.isInitialized) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (BuildContext context, VideoPlayerValue value, Widget? child) {
        return GestureDetector(
          onTap: () => setState(() => _showControls = !_showControls),
          child: Stack(
            children: <Widget>[
              Center(
                child: AspectRatio(
                  aspectRatio: value.aspectRatio <= 0 ? 16 / 9 : value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
              ),
              if (!value.isPlaying && !_showControls)
                const Center(
                  child: AppIcon('play', size: 46, color: Colors.white70),
                ),
              AnimatedOpacity(
                opacity: _showControls ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: _controls(controller, value),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _controls(VideoPlayerController controller, VideoPlayerValue value) {
    final Duration duration = value.duration;
    final Duration position = value.position;
    final double max =
        duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
    final double current = position.inMilliseconds
        .clamp(0, duration.inMilliseconds <= 0 ? 0 : duration.inMilliseconds)
        .toDouble();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.black.withOpacity(0.55),
            Colors.transparent,
            Colors.black.withOpacity(0.8),
          ],
          stops: const <double>[0, 0.45, 1],
        ),
      ),
      child: Column(
        children: <Widget>[
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _circleButton(
                  value.isPlaying ? 'pause' : 'play',
                  () {
                    if (value.isPlaying) {
                      controller.pause();
                    } else {
                      controller.play();
                    }
                  },
                  size: 62,
                  iconSize: 26,
                ),
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: <Widget>[
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    activeTrackColor: AppColors.secondary,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: AppColors.secondary,
                    overlayColor: AppColors.secondary.withOpacity(0.2),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: current,
                    max: max,
                    onChanged: (double next) {
                      controller.seekTo(Duration(milliseconds: next.round()));
                    },
                  ),
                ),
                Row(
                  children: <Widget>[
                    Text(
                      formatDuration(position.inSeconds),
                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                    const Text(
                      '  /  ',
                      style: TextStyle(fontSize: 11, color: Colors.white38),
                    ),
                    Text(
                      formatDuration(duration.inSeconds),
                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                    const Spacer(),
                    _textButton(
                      '${value.playbackSpeed}x',
                      () => _showSpeedSheet(controller),
                    ),
                    const SizedBox(width: 6),
                    _textButton(
                      '',
                      _toggleFullscreen,
                      icon: _fullscreen ? 'close' : 'film',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleButton(String icon, VoidCallback onTap,
      {double size = 48, double iconSize = 20}) {
    return Material(
      color: Colors.black.withOpacity(0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: AppIcon(icon, size: iconSize, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _textButton(String label, VoidCallback onTap, {String? icon}) {
    return Material(
      color: Colors.black.withOpacity(0.4),
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: label.isEmpty ? 9 : 11,
            vertical: 7,
          ),
          child: icon != null
              ? AppIcon(icon, size: 15, color: Colors.white)
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }
}
