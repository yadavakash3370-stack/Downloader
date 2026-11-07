class QualityOption {
  const QualityOption({
    required this.label,
    required this.format,
    this.audioOnly = false,
    this.height = 0,
    this.bytes = 0,
  });

  /// Text shown on the chip, e.g. "720p HD".
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
  });

  final String url;
  final String title;
  final String uploader;
  final String thumbnail;
  final String extractor;
  final int duration;
  final List<QualityOption> options;

  factory MediaInfo.fromMap(Map<String, dynamic> map) {
    final List<int> heights = <int>[];
    final Object? rawHeights = map['heights'];
    if (rawHeights is List) {
      for (final Object? item in rawHeights) {
        if (item is num) heights.add(item.toInt());
      }
    }

    final Map<String, int> sizes = <String, int>{};
    final Object? rawSizes = map['sizes'];
    if (rawSizes is Map) {
      rawSizes.forEach((Object? key, Object? value) {
        if (value is num) sizes[key.toString()] = value.toInt();
      });
    }

    final List<QualityOption> options = <QualityOption>[
      QualityOption(label: 'Best', format: 'bv*+ba/b'),
    ];

    for (final int height in heights) {
      if (height < 144) continue;
      options.add(
        QualityOption(
          label: '${height}p',
          format:
              'bv*[height<=$height][ext=mp4]+ba[ext=m4a]/bv*[height<=$height]+ba/b[height<=$height]/b',
          height: height,
          bytes: sizes['$height'] ?? 0,
        ),
      );
    }

    if (map['audioOnly'] == true || heights.isEmpty) {
      options.add(
        const QualityOption(
          label: 'Audio',
          format: 'ba/b',
          audioOnly: true,
        ),
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
    );
  }
}
