class QualityOption {
  const QualityOption({
    required this.label,
    required this.format,
    this.audioOnly = false,
    this.height = 0,
    this.bytes = 0,
  });

  /// Text shown on the chip, e.g. "1080p".
  final String label;

  /// yt-dlp `-f` selector.
  final String format;
  final bool audioOnly;
  final int height;
  final int bytes;
}

class MediaInfo {
  const MediaInfo({
    required this.url,
    required this.title,
    required this.uploader,
    required this.thumbnail,
    required this.extractor,
    required this.duration,
    required this.options,
    this.lite = false,
  });

  final String url;
  final String title;
  final String uploader;
  final String thumbnail;
  final String extractor;
  final int duration;
  final List<QualityOption> options;

  /// True when the installed APK is the "lite" build (no ffmpeg natives), so
  /// only single-file (progressive) formats can be offered.
  final bool lite;

  factory MediaInfo.fromMap(Map<String, dynamic> map) {
    final bool hasFfmpeg = map['hasFfmpeg'] == true;

    // Full build: separate high-resolution video + best audio are merged, so all
    // reported heights are usable. Lite build: only progressive formats.
    final Object? rawHeights =
        hasFfmpeg ? map['heights'] : map['combinedHeights'];

    final List<int> heights = <int>[];
    if (rawHeights is List) {
      for (final Object? item in rawHeights) {
        if (item is num && item.toInt() >= 144) heights.add(item.toInt());
      }
    }
    heights.sort((int a, int b) => b.compareTo(a));
    if (heights.length > 8) {
      heights.removeRange(8, heights.length);
    }

    final Map<String, int> sizes = <String, int>{};
    final Object? rawSizes = map['sizes'];
    if (rawSizes is Map) {
      rawSizes.forEach((Object? key, Object? value) {
        if (value is num) sizes[key.toString()] = value.toInt();
      });
    }

    // "Best" = sabse achhi quality jo har phone par reliably play ho
    // (h264 + aac -> mp4). "Max" = site ka sabse bada format (AV1/VP9 bhi,
    // container apne aap mkv/webm ban jata hai).
    final List<QualityOption> options = <QualityOption>[
      QualityOption(
        label: 'Best',
        format: hasFfmpeg
            ? 'bv*[vcodec^=avc1]+ba[ext=m4a]/bv*[ext=mp4]+ba[ext=m4a]/bv*+ba/b'
            : 'b[ext=mp4]/b',
      ),
    ];

    if (hasFfmpeg) {
      options.add(const QualityOption(label: 'Max', format: 'bv*+ba/b'));
    }

    for (final int height in heights) {
      // 1080p se upar h264 generally nahi milta - codec restriction hatana
      // zaroori hai warna "2160p" chunne par bhi 1080p hi download hota.
      final String fullFormat = height > 1080
          ? 'bv*[height<=$height]+ba/b[height<=$height]/b'
          : 'bv*[height<=$height][vcodec^=avc1]+ba[ext=m4a]/bv*[height<=$height][ext=mp4]+ba[ext=m4a]/bv*[height<=$height]+ba/b[height<=$height]/b';
      options.add(
        QualityOption(
          label: '${height}p',
          format: hasFfmpeg
              ? fullFormat
              : 'b[height<=$height][ext=mp4]/b[height<=$height]/b',
          height: height,
          bytes: sizes['$height'] ?? 0,
        ),
      );
    }

    if (map['audioOnly'] == true || heights.isEmpty) {
      options.add(
        const QualityOption(label: 'Audio', format: 'ba/b', audioOnly: true),
      );
    }

    return MediaInfo(
      url: (map['url'] ?? '') as String,
      title: (map['title'] ?? 'Untitled') as String,
      uploader: (map['uploader'] ?? '') as String,
      thumbnail: (map['thumbnail'] ?? '') as String,
      extractor: (map['extractor'] ?? '') as String,
      duration: map['duration'] is num ? (map['duration'] as num).toInt() : 0,
      options: options,
      lite: !hasFfmpeg,
    );
  }
}
