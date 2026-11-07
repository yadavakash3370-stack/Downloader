import 'dart:async';

import 'package:flutter/services.dart';

/// Event pushed from the native yt-dlp bridge.
class EngineEvent {
  const EngineEvent({
    required this.type,
    required this.jobId,
    this.progress = 0,
    this.eta = 0,
    this.message = '',
    this.path = '',
    this.name = '',
    this.size = 0,
    this.publicPath = '',
  });

  /// progress | stage | done | failed | cancelled
  final String type;
  final String jobId;
  final double progress;
  final int eta;
  final String message;
  final String path;
  final String name;
  final int size;
  final String publicPath;

  factory EngineEvent.fromMap(Map<String, dynamic> map) {
    final Object? message = map['message'] ?? map['line'];
    return EngineEvent(
      type: (map['type'] ?? '') as String,
      jobId: (map['jobId'] ?? '') as String,
      progress: map['progress'] is num ? (map['progress'] as num).toDouble() : 0,
      eta: map['eta'] is num ? (map['eta'] as num).toInt() : 0,
      message: message is String ? message : '',
      path: (map['path'] ?? '') as String,
      name: (map['name'] ?? '') as String,
      size: map['size'] is num ? (map['size'] as num).toInt() : 0,
      publicPath: (map['publicPath'] ?? '') as String,
    );
  }
}

/// Thin wrapper over the Android method channel that drives yt-dlp on device.
class Engine {
  static const MethodChannel _channel = MethodChannel('com.videograb/engine');
  static final StreamController<EngineEvent> _controller =
      StreamController<EngineEvent>.broadcast();
  static bool _bound = false;

  static Stream<EngineEvent> get events => _controller.stream;

  static void bind() {
    if (_bound) return;
    _bound = true;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'event' && call.arguments is Map) {
        _controller.add(
          EngineEvent.fromMap(
            Map<String, dynamic>.from(call.arguments as Map<dynamic, dynamic>),
          ),
        );
      }
      return null;
    });
  }

  static Future<Map<String, dynamic>> _invoke(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    try {
      final Map<dynamic, dynamic>? result =
          await _channel.invokeMethod<Map<dynamic, dynamic>>(method, args);
      if (result == null) {
        return <String, dynamic>{'ok': false, 'error': 'Engine did not respond'};
      }
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (error) {
      return <String, dynamic>{
        'ok': false,
        'error': error.message ?? error.code,
      };
    } on MissingPluginException {
      return <String, dynamic>{
        'ok': false,
        'error': 'Downloader engine sirf Android app me available hai',
      };
    }
  }

  static Future<Map<String, dynamic>> init() => _invoke('init');

  static Future<Map<String, dynamic>> info() => _invoke('engineInfo');

  static Future<Map<String, dynamic>> probe(String url) =>
      _invoke('probe', <String, dynamic>{'url': url});

  static Future<Map<String, dynamic>> streamUrl(String url) =>
      _invoke('streamUrl', <String, dynamic>{'url': url});

  static Future<Map<String, dynamic>> startDownload({
    required String jobId,
    required String url,
    required String format,
    required bool audioOnly,
    required bool alsoSave,
    required String title,
  }) {
    return _invoke('download', <String, dynamic>{
      'jobId': jobId,
      'url': url,
      'format': format,
      'audioOnly': audioOnly,
      'alsoSave': alsoSave,
      'title': title,
    });
  }

  static Future<Map<String, dynamic>> cancel(String jobId) =>
      _invoke('cancel', <String, dynamic>{'jobId': jobId});

  static Future<Map<String, dynamic>> updateEngine() => _invoke('updateEngine');

  static Future<Map<String, dynamic>> saveCopy(String path, String name) =>
      _invoke('saveCopy', <String, dynamic>{'path': path, 'name': name});

  static Future<Map<String, dynamic>> deleteFile(String path) =>
      _invoke('deleteFile', <String, dynamic>{'path': path});
}
