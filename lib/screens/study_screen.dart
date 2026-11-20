import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../services/app_links.dart';
import '../services/pw_account.dart';
import '../theme.dart';
import '../widgets/svg_icon.dart';
import 'player_screen.dart';
import 'pw_login_screen.dart';

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
/// Lectures play in the site's own player (including DRM lectures, through
/// the phone's built-in Widevine). When the user logs in on the site, the app
/// links that login to the PW account used by the Download tab. Plain
/// (non-DRM) media URLs the page loads can be played or sent to the
/// downloader.
class StudyScreen extends StatefulWidget {
  const StudyScreen({
    required this.active,
    required this.onOpenInDownload,
    required this.onRequestFocus,
    super.key,
  });

  final bool active;
  final void Function(PendingLink link) onOpenInDownload;

  /// Asks the shell to bring the PW tab to the front.
  final VoidCallback onRequestFocus;

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  static const String _hookScript = r'''
(function () {
  if (window.__vgHooked) { return; }
  window.__vgHooked = true;
  var seen = {};
  var session = {};
  var lastSession = '';
  var lastToken = '';
  var watch = ['authorization', 'cookie', 'referer'];

  function post(msg) {
    try { VideoGrab.postMessage(JSON.stringify(msg)); } catch (e) {}
  }
  function pwHost(h) {
    h = String(h || '').toLowerCase();
    return h === 'pw.live' || /\.pw\.live$/.test(h) ||
           h === 'penpencil.co' || /\.penpencil\.co$/.test(h);
  }
  function pwPage() {
    return pwHost(location.hostname);
  }
  function pwRequest(u) {
    try {
      return pwHost(new URL(String(u), location.href).hostname);
    } catch (e) { return false; }
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
  function token(value) {
    try {
      if (!pwPage()) { return; }
      var m = String(value || '').match(
          /eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/);
      if (!m || m[0] === lastToken) { return; }
      lastToken = m[0];
      post({type: 'token', token: m[0]});
    } catch (e) {}
  }
  function capture(name, value, url) {
    try {
      var n = String(name).toLowerCase();
      if (watch.indexOf(n) < 0) { return; }
      if (!pwPage() || !pwRequest(url)) { return; }
      var v = String(value);
      if (!v) { return; }
      if (n === 'authorization') { token(v); }
      if (session[n] === v) { return; }
      session[n] = v;
      var json = JSON.stringify(session);
      if (json !== lastSession) {
        lastSession = json;
        post({type: 'session', headers: session});
      }
    } catch (e) {}
  }
  function captureHeaders(headers, url) {
    try {
      if (!headers) { return; }
      if (typeof headers.forEach === 'function') {
        headers.forEach(function (v, k) { capture(k, v, url); });
      } else if (Array.isArray(headers)) {
        headers.forEach(function (pair) { capture(pair[0], pair[1], url); });
      } else {
        Object.keys(headers).forEach(function (k) {
          capture(k, headers[k], url);
        });
      }
    } catch (e) {}
  }
  function scanStorage() {
    try {
      if (!pwPage() || !window.localStorage) { return; }
      var best = null;
      var rank = 9;
      for (var i = 0; i < localStorage.length; i++) {
        var k = localStorage.key(i);
        if (!k || !/token/i.test(k) || /refresh/i.test(k)) { continue; }
        var v = localStorage.getItem(k);
        if (!v || v.indexOf('eyJ') < 0) { continue; }
        var r = /^token$/i.test(k) ? 0 : (/access/i.test(k) ? 1 : 2);
        if (r < rank) { rank = r; best = v; }
      }
      if (best) { token(best); }
    } catch (e) {}
  }
  try {
    var open = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function (method, url) {
      try { this.__vgUrl = String(url); } catch (e) {}
      send(url, 'xhr');
      return open.apply(this, arguments);
    };
    var setHeader = XMLHttpRequest.prototype.setRequestHeader;
    XMLHttpRequest.prototype.setRequestHeader = function (name, value) {
      capture(name, value, this.__vgUrl || '');
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
          if (init && init.headers) { captureHeaders(init.headers, u); }
          if (input && typeof input !== 'string' && input.headers) {
            captureHeaders(input.headers, u);
          }
        } catch (e) {}
        return origFetch.apply(this, arguments);
      };
    }
  } catch (e) {}
  function sweep() {
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
      if (pwPage()) { capture('cookie', document.cookie, location.href); }
      scanStorage();
    } catch (e) {}
  }
  sweep();
  setInterval(sweep, 4000);
})();
''';

  late final WebViewController _controller;
  final List<DetectedMedia> _media = <DetectedMedia>[];
  Map<String, String> _headers = <String, String>{};

  Timer? _hookTimer;
  PwSession? _lastSession;
  bool _loading = true;
  bool _fullscreen = false;
  int _progress = 0;
  String _title = 'Physics Wallah';
  String _url = PwAccount.webHome;

  @override
  void initState() {
    super.initState();
    _lastSession = PwAccount.session.value;
    PwAccount.session.addListener(_onSessionChanged);
    AppLinks.study.addListener(_onStudyLink);

    _controller = WebViewController(onPermissionRequest: _onPermissionRequest)
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
          onUrlChange: (UrlChange change) {
            final String? next = change.url;
            if (next != null && next.isNotEmpty && mounted) {
              setState(() => _url = next);
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
      );
    _configurePlatform();

    // A page may have been requested before this tab was ever built.
    final String? requested = AppLinks.takeStudy();
    final Uri? first = requested == null ? null : Uri.tryParse(requested);
    _controller.loadRequest(first ?? Uri.parse(PwAccount.webHome));

    // PW is a single-page app: pageFinished may not fire on in-app navigation.
    _hookTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (widget.active) _injectHooks();
    });
  }

  @override
  void dispose() {
    _hookTimer?.cancel();
    PwAccount.session.removeListener(_onSessionChanged);
    AppLinks.study.removeListener(_onStudyLink);
    super.dispose();
  }

  /// Android-only WebView settings needed by the official lecture player.
  void _configurePlatform() {
    final Object platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
      platform.setCustomWidgetCallbacks(
        onShowCustomWidget: _enterFullscreen,
        onHideCustomWidget: _leaveFullscreen,
      );
      AndroidWebViewCookieManager(
        const PlatformWebViewCookieManagerCreationParams(),
      ).setAcceptThirdPartyCookies(platform, true);
    }
  }

  bool get _onPwPage {
    final Uri? uri = Uri.tryParse(_url);
    return uri != null && PwAccount.isPwHost(uri.host);
  }

  /// DRM lectures need the phone's protected media id (Widevine). Only PW
  /// pages get it; camera / microphone requests are refused.
  void _onPermissionRequest(WebViewPermissionRequest request) {
    final bool onlyDrm = request.types.isNotEmpty &&
        request.types.every(
          (WebViewPermissionResourceType type) =>
              type.name == 'protectedMediaId',
        );
    if (onlyDrm && _onPwPage) {
      request.grant();
    } else {
      request.deny();
    }
  }

  // ---------------------------------------------------------- fullscreen

  void _enterFullscreen(Widget view, void Function() onHidden) {
    if (!mounted) {
      onHidden();
      return;
    }
    _fullscreen = true;
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    Navigator.of(context, rootNavigator: true)
        .push<void>(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (BuildContext context) {
              return ColoredBox(color: Colors.black, child: view);
            },
          ),
        )
        .whenComplete(() {
          // True when the user left with the back button (not the player).
          final bool closedByUser = _fullscreen;
          _fullscreen = false;
          SystemChrome.setPreferredOrientations(<DeviceOrientation>[
            DeviceOrientation.portraitUp,
          ]);
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          if (closedByUser) onHidden();
        });
  }

  void _leaveFullscreen() {
    if (!_fullscreen || !mounted) return;
    _fullscreen = false;
    Navigator.of(context, rootNavigator: true).pop();
  }

  // ------------------------------------------------------------- account

  void _onSessionChanged() {
    final PwSession? next = PwAccount.session.value;
    final bool loggedOut = _lastSession != null && next == null;
    _lastSession = next;
    if (loggedOut) _clearWebLogin();
    if (mounted) setState(() {});
  }

  /// Logout also signs the website out, otherwise the page would hand the
  /// same login straight back.
  Future<void> _clearWebLogin() async {
    try {
      await WebViewCookieManager().clearCookies();
      await _controller.clearLocalStorage();
    } catch (_) {
      // storage already empty
    }
    if (!mounted) return;
    setState(() {
      _headers = <String, String>{};
      _media.clear();
    });
    await _controller.loadRequest(Uri.parse(PwAccount.webHome));
  }

  /// The user logged in on pw.live: link that login to the app's PW account.
  Future<void> _adopt(String token) async {
    String? current;
    try {
      current = await _controller.currentUrl();
    } catch (_) {
      current = null;
    }
    final Uri? page = current == null ? null : Uri.tryParse(current);
    if (page == null || !PwAccount.isPwHost(page.host)) return;

    final bool wasLoggedIn = PwAccount.loggedIn;
    final bool linked = await PwAccount.adoptToken(token);
    if (linked && !wasLoggedIn && mounted) {
      final String name = PwAccount.session.value?.displayName ?? '';
      _snack('PW account connect ho gaya${name.isEmpty ? '' : ' — $name'}');
    }
  }

  Future<void> _login() async {
    final bool ok = await PwLoginScreen.open(context);
    if (ok && mounted) _snack('PW account login ho gaya');
  }

  Future<void> _openAccountSheet() async {
    final PwSession? current = PwAccount.session.value;
    if (current == null) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const IconBadge('user', size: 40, iconSize: 19, gradient: true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            current.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            current.source == 'web'
                                ? 'PW account · website login'
                                : 'PW account · OTP login',
                            style: const TextStyle(
                              fontSize: 10.8,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const AppPill(label: 'Connected', color: AppColors.success),
                  ],
                ),
                const SizedBox(height: 14),
                AppOutlineButton(
                  label: 'Logout',
                  icon: 'logout',
                  height: 44,
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    PwAccount.logout();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------- webview

  void _onStudyLink() {
    final String? url = AppLinks.takeStudy();
    if (url == null || !mounted) return;
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return;
    widget.onRequestFocus();
    _controller.loadRequest(uri);
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
      final Object? type = decoded['type'];

      if (type == 'token') {
        final Object? token = decoded['token'];
        if (token is String && token.isNotEmpty) _adopt(token);
        return;
      }

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
      final Object? title = decoded['title'];
      final Object? kind = decoded['kind'];
      setState(() {
        _media.insert(
          0,
          DetectedMedia(
            url: rawUrl,
            title: title is String && title.isNotEmpty ? title : _title,
            kind: kind is String ? kind : 'media',
          ),
        );
        if (_media.length > 50) _media.removeLast();
      });
    } catch (_) {
      // ignore malformed messages
    }
  }

  /// The PW login (token / cookies) is only ever forwarded to PW's own hosts.
  Map<String, String> _headersFor(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri != null && PwAccount.isPwHost(uri.host)) {
      final Map<String, String> headers = Map<String, String>.from(_headers);
      headers.putIfAbsent('referer', () => 'https://www.pw.live/');
      return headers;
    }
    return const <String, String>{'referer': 'https://www.pw.live/'};
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  // --------------------------------------------------------------- sheet

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
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Sirf plain (non-DRM) streams save ho sakte hain',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.muted,
                              ),
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
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
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
                        headers: _headersFor(media.url),
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
                  _snack('Link copy ho gaya');
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
            border: Border.all(
              color: accent ? Colors.transparent : AppColors.stroke,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppIcon(
                icon,
                size: 13,
                color: accent ? Colors.white : AppColors.text,
              ),
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

  // ------------------------------------------------------------------ ui

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
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
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
          _toolButton(
            'home',
            () => _controller.loadRequest(Uri.parse(PwAccount.webHome)),
          ),
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

  Widget _accountBar() {
    final PwSession? account = PwAccount.session.value;
    final int count = _media.length;
    final String headline = account == null
        ? 'PW account login nahi hai'
        : 'PW: ${account.displayName}';
    final String detail = count > 0
        ? '$count media links mile'
        : (account == null
            ? 'Login karke lectures yahin dekhein'
            : 'Lectures yahin player me chalayein');

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.stroke)),
      ),
      child: Row(
        children: <Widget>[
          IconBadge(
            account == null ? 'graduation' : 'user',
            size: 32,
            iconSize: 15,
            color: account == null ? AppColors.muted : AppColors.success,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  headline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9.2, color: AppColors.muted),
                ),
              ],
            ),
          ),
          // Compact buttons: label only, so the text never gets clipped.
          if (count > 0) ...<Widget>[
            const SizedBox(width: 8),
            SizedBox(
              width: 78,
              child: AppOutlineButton(
                label: 'Videos',
                height: 34,
                onPressed: _openSheet,
              ),
            ),
          ],
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: account == null
                ? GradientButton(
                    label: 'Login',
                    height: 34,
                    onPressed: _login,
                  )
                : AppOutlineButton(
                    label: 'Account',
                    height: 34,
                    onPressed: _openAccountSheet,
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          _accountBar(),
        ],
      ),
    );
  }
}
