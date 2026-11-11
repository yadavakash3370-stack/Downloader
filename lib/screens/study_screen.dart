import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/app_links.dart';
import '../theme.dart';
import '../widgets/svg_icon.dart';
import 'player_screen.dart';

class DetectedMedia {
  DetectedMedia({required this.url, required this.title, required this.kind});

  final String url;
  final String title;
  final String kind;

  String get label {
    final String lower = url.toLowerCase();
    if (lower.contains('.m3u8')) return 'HLS';
    if (lower.contains('.mpd')) return 'DASH';
    if (lower.contains('.mp4')) return 'MP4';
    if (lower.contains('.webm')) return 'WebM';
    if (lower.contains('.m4a')) return 'M4A';
    return 'Media';
  }
}

/// Official PW (Physics Wallah) website inside the app.
///
/// Login is done on pw.live itself in the WebView - the app never reads or
/// stores the password/OTP. Lectures play in the site's own player, and any
/// plain (non-DRM) media URL the page loads can be played or sent to the
/// downloader with the session headers that the page used.
class StudyScreen extends StatefulWidget {
  const StudyScreen({
    required this.active,
    required this.onOpenInDownload,
    super.key,
  });

  final bool active;
  final void Function(PendingLink link) onOpenInDownload;

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  static const String _startUrl = 'https://www.pw.live/study-v2/batches';
  static const String _loginUrl = 'https://www.pw.live/';

  static const String _hookScript = r'''
(function () {
  if (window.__vgHooked) { return; }
  window.__vgHooked = true;
  var seen = {};
  var session = {};
  var lastSession = '';
  var watch = ['authorization', 'cookie', 'x-auth-token', 'x-access-token',
               'x-session-id', 'x-pw-token', 'x-user-token', 'referer'];

  function post(msg) {
    try { VideoGrab.postMessage(JSON.stringify(msg)); } catch (e) {}
  }
  function isMedia(u) {
    return /\.(m3u8|mp4|mpd|m4a|webm)(\?|#|$)/i.test(u);
  }
  function send(u, kind) {
    try {
      if (!u) { return; }
      u = String(u);
      if (u.indexOf('http') !== 0 || !isMedia(u) || seen[u]) { return; }
      seen[u] = 1;
      post({type: 'media', url: u, kind: kind,
            title: document.title || 'PW lecture'});
    } catch (e) {}
  }
  function capture(name, value) {
    try {
      var n = String(name).toLowerCase();
      if (watch.indexOf(n) < 0) { return; }
      var v = String(value);
      if (!v || session[String(name)] === v) { return; }
      session[String(name)] = v;
      var json = JSON.stringify(session);
      if (json !== lastSession) {
        lastSession = json;
        post({type: 'session', headers: session});
      }
    } catch (e) {}
  }
  function captureHeaders(headers) {
    try {
      if (!headers) { return; }
      if (typeof headers.forEach === 'function') {
        headers.forEach(function (v, k) { capture(k, v); });
      } else if (Array.isArray(headers)) {
        headers.forEach(function (pair) { capture(pair[0], pair[1]); });
      } else {
        Object.keys(headers).forEach(function (k) { capture(k, headers[k]); });
      }
    } catch (e) {}
  }
  try {
    var open = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function (method, url) {
      send(url, 'xhr');
      return open.apply(this, arguments);
    };
    var setHeader = XMLHttpRequest.prototype.setRequestHeader;
    XMLHttpRequest.prototype.setRequestHeader = function (name, value) {
      capture(name, value);
      return setHeader.apply(this, arguments);
    };
  } catch (e) {}
  try {
    var origFetch = window.fetch;
    if (origFetch) {
      window.fetch = function (input, init) {
        try {
          var u = (typeof input === 'string') ? input : (input && input.url);
          send(u, 'fetch');
          if (init && init.headers) { captureHeaders(init.headers); }
          if (input && input.headers) { captureHeaders(input.headers); }
        } catch (e) {}
        return origFetch.apply(this, arguments);
      };
    }
  } catch (e) {}
  try { capture('Cookie', document.cookie); } catch (e) {}
  setInterval(function () {
    try {
      var videos = document.querySelectorAll('video');
      for (var i = 0; i < videos.length; i++) {
        send(videos[i].currentSrc || videos[i].src, 'video');
        var sources = videos[i].querySelectorAll('source');
        for (var j = 0; j < sources.length; j++) {
          send(sources[j].src, 'source');
        }
      }
      if (window.performance && performance.getEntriesByType) {
        var entries = performance.getEntriesByType('resource');
        for (var k = 0; k < entries.length; k++) {
          send(entries[k].name, 'perf');
        }
      }
      capture('Cookie', document.cookie);
    } catch (e) {}
  }, 4000);
})();
''';

  late final WebViewController _controller;
  final List<DetectedMedia> _media = <DetectedMedia>[];
  Map<String, String> _headers = <String, String>{};

  Timer? _hookTimer;
  bool _loading = true;
  int _progress = 0;
  String _title = 'Physics Wallah';
  String _url = _startUrl;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.bg)
      ..addJavaScriptChannel('VideoGrab', onMessageReceived: _onJsMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _loading = true;
                _url = url;
              });
            }
          },
          onPageFinished: (String url) async {
            if (mounted) {
              setState(() {
                _loading = false;
                _url = url;
              });
            }
            await _injectHooks();
            final String? title = await _controller.getTitle();
            if (title != null && title.isNotEmpty && mounted) {
              setState(() => _title = title);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_startUrl));

    // PW is a single-page app: pageFinished may not fire on in-app navigation.
    _hookTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (widget.active) _injectHooks();
    });
  }

  @override
  void dispose() {
    _hookTimer?.cancel();
    super.dispose();
  }

  Future<void> _injectHooks() async {
    try {
      await _controller.runJavaScript(_hookScript);
    } catch (_) {
      // page not ready - next tick will retry
    }
  }

  void _onJsMessage(JavaScriptMessage message) {
    try {
      final Object? decoded = jsonDecode(message.message);
      if (decoded is! Map) return;
      final String type = (decoded['type'] as String?) ?? '';

      if (type == 'session') {
        final Object? raw = decoded['headers'];
        if (raw is Map) {
          final Map<String, String> next = <String, String>{};
          raw.forEach((Object? key, Object? value) {
            if (key != null && value != null) {
              next[key.toString()] = value.toString();
            }
          });
          if (!mounted) return;
          setState(() => _headers = next);
        }
        return;
      }

      final Object? rawUrl = decoded['url'];
      if (rawUrl is! String || rawUrl.length < 8) return;
      if (_media.any((DetectedMedia item) => item.url == rawUrl)) return;
      if (!mounted) return;
      setState(() {
        _media.insert(
          0,
          DetectedMedia(
            url: rawUrl,
            title: (decoded['title'] as String?) ?? _title,
            kind: (decoded['kind'] as String?) ?? 'media',
          ),
        );
        if (_media.length > 50) _media.removeLast();
      });
    } catch (_) {
      // ignore malformed messages
    }
  }

  Future<void> _openSheet() async {
    if (_media.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.60,
          maxChildSize: 0.92,
          minChildSize: 0.35,
          builder: (BuildContext context, ScrollController scrollController) {
            return Column(
              children: <Widget>[
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.stroke,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 13, 14, 8),
                  child: Row(
                    children: <Widget>[
                      const IconBadge('film', size: 32, iconSize: 15),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '${_media.length} media links mile',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _headers.isEmpty
                                  ? 'Page ke plain (non-DRM) streams'
                                  : 'Session headers bhi download ke saath bhejenge',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10, color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.all(14),
                    itemCount: _media.length,
                    separatorBuilder: (BuildContext context, int index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (BuildContext context, int index) =>
                        _mediaTile(_media[index]),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _mediaTile(DetectedMedia media) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppPill(label: media.label, color: AppColors.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  media.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            media.url,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 9.8, color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _sheetAction(
                  icon: 'play',
                  label: 'Play',
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PlayerScreen(
                          title: media.title,
                          networkUrl: media.url,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _sheetAction(
                  icon: 'download',
                  label: 'Download',
                  accent: true,
                  onTap: () {
                    Navigator.of(context).pop();
                    widget.onOpenInDownload(
                      PendingLink(
                        url: media.url,
                        title: media.title,
                        headers: Map<String, String>.from(_headers),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              _sheetAction(
                icon: 'copy',
                label: '',
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: media.url));
                  if (!mounted) return;
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Link copy ho gaya')),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sheetAction({
    required String icon,
    required String label,
    required VoidCallback onTap,
    bool accent = false,
  }) {
    return Material(
      color: accent ? AppColors.primary : AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Container(
          height: 34,
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: label.isEmpty ? 10 : 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: accent ? Colors.transparent : AppColors.stroke),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppIcon(icon, size: 13, color: accent ? Colors.white : AppColors.text),
              if (label.isNotEmpty) ...<Widget>[
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: accent ? Colors.white : AppColors.text,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolbar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 6, 8, 7),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.stroke)),
      ),
      child: Row(
        children: <Widget>[
          _toolButton('back', () async {
            if (await _controller.canGoBack()) await _controller.goBack();
          }),
          _toolButton('chevron', () async {
            if (await _controller.canGoForward()) await _controller.goForward();
          }),
          _toolButton('refresh', () => _controller.reload()),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _loading ? 'Loading…' : _title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 1),
                Text(
                  _url.replaceFirst('https://', ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9.2, color: AppColors.muted),
                ),
              ],
            ),
          ),
          _toolButton('home', () => _controller.loadRequest(Uri.parse(_startUrl))),
          _toolButton('lock', () => _controller.loadRequest(Uri.parse(_loginUrl))),
        ],
      ),
    );
  }

  Widget _toolButton(String icon, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: AppIcon(icon, size: 15, color: AppColors.muted),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int count = _media.length;
    return PopScope<Object?>(
      canPop: !widget.active,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          await _controller.goBack();
        } else {
          await SystemNavigator.pop();
        }
      },
      child: Column(
        children: <Widget>[
          _toolbar(),
          if (_progress > 0 && _progress < 100)
            LinearProgressIndicator(
              value: _progress / 100,
              minHeight: 2,
              backgroundColor: AppColors.surface,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          Expanded(child: WebViewWidget(controller: _controller)),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.stroke)),
            ),
            child: Row(
              children: <Widget>[
                IconBadge(
                  'graduation',
                  size: 32,
                  iconSize: 15,
                  color: count > 0 ? AppColors.secondary : AppColors.muted,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        count > 0 ? '$count media links detected' : 'pw.live — apne account me login karein',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 1),
                      const Text(
                        'Lectures site par dekhein · link milne par Download',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 9.2, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 96,
                  child: AppOutlineButton(
                    label: count > 0 ? 'Videos' : 'Refresh',
                    icon: count > 0 ? 'film' : 'refresh',
                    height: 34,
                    onPressed: count > 0 ? _openSheet : () => _controller.reload(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
