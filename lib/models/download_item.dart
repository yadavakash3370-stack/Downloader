class DownloadItem {
  const DownloadItem({
    required this.id,
    required this.title,
    required this.path,
    required this.ext,
    required this.sizeBytes,
    required this.createdAt,
    this.thumbnail = '',
    this.uploader = '',
    this.extractor = '',
    this.duration = 0,
    this.publicPath = '',
  });

  final String id;
  final String title;
  final String path;
  final String ext;
  final int sizeBytes;
  final DateTime createdAt;
  final String thumbnail;
  final String uploader;
  final String extractor;
  final int duration;

  /// Public copy inside the device "Download/VideoGrab" folder (when saved).
  final String publicPath;

  DownloadItem copyWith({String? publicPath, String? title}) {
    return DownloadItem(
      id: id,
      title: title ?? this.title,
      path: path,
      ext: ext,
      sizeBytes: sizeBytes,
      createdAt: createdAt,
      thumbnail: thumbnail,
      uploader: uploader,
      extractor: extractor,
      duration: duration,
      publicPath: publicPath ?? this.publicPath,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'path': path,
      'ext': ext,
      'sizeBytes': sizeBytes,
      'createdAt': createdAt.toIso8601String(),
      'thumbnail': thumbnail,
      'uploader': uploader,
      'extractor': extractor,
      'duration': duration,
      'publicPath': publicPath,
    };
  }

  factory DownloadItem.fromJson(Map<String, dynamic> json) {
    return DownloadItem(
      id: (json['id'] ?? '') as String,
      title: (json['title'] ?? 'Untitled') as String,
      path: (json['path'] ?? '') as String,
      ext: (json['ext'] ?? '') as String,
      sizeBytes: json['sizeBytes'] is num ? (json['sizeBytes'] as num).toInt() : 0,
      createdAt: DateTime.tryParse((json['createdAt'] ?? '') as String) ?? DateTime.now(),
      thumbnail: (json['thumbnail'] ?? '') as String,
      uploader: (json['uploader'] ?? '') as String,
      extractor: (json['extractor'] ?? '') as String,
      duration: json['duration'] is num ? (json['duration'] as num).toInt() : 0,
      publicPath: (json['publicPath'] ?? '') as String,
    );
  }
}
