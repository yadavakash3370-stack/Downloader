import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The user's own Physics Wallah login. The token never leaves this phone
/// except in requests to PW's own servers.
class PwSession {
  const PwSession({
    required this.accessToken,
    this.refreshToken = '',
    this.name = '',
    this.phone = '',
    this.source = 'otp',
  });

  final String accessToken;
  final String refreshToken;
  final String name;
  final String phone;

  /// `otp` = logged in with the in-app OTP form, `web` = logged in on pw.live
  /// inside the PW tab.
  final String source;

  String get displayName {
    final String clean = name.trim();
    if (clean.isNotEmpty) return clean;
    if (phone.length >= 4) return 'XXXXXX${phone.substring(phone.length - 4)}';
    return 'PW account';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'name': name,
        'phone': phone,
        'source': source,
      };

  static PwSession? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Object? token = raw['accessToken'];
    if (token is! String || token.isEmpty) return null;
    String read(String key) {
      final Object? value = raw[key];
      return value is String ? value : '';
    }

    final String source = read('source');
    return PwSession(
      accessToken: token,
      refreshToken: read('refreshToken'),
      name: read('name'),
      phone: read('phone'),
      source: source.isEmpty ? 'otp' : source,
    );
  }
}

class PwException implements Exception {
  const PwException(
    this.message, {
    this.status = 0,
    this.needsLogin = false,
    this.detail = '',
  });

  final String message;
  final int status;

  /// True when the fix is "log in (again)".
  final bool needsLogin;

  /// Which PW requests were made and how they answered (no tokens, no
  /// signed URLs) - shown small under the error so a failure can be reported.
  final String detail;

  @override
  String toString() => message;
}

enum PwMediaKind {
  /// Hosted on a normal video site (YouTube / Vimeo) - the regular engine
  /// downloads it.
  external,

  /// Plain, unencrypted stream or file.
  stream,

  /// Widevine / CENC protected. Plays only in the official player.
  drm,
}

/// What a PW lecture link resolved to.
class PwLecture {
  const PwLecture({
    required this.kind,
    required this.pageUrl,
    this.title = '',
    this.thumbnail = '',
    this.duration = 0,
    this.mediaUrl = '',
    this.headers = const <String, String>{},
    this.note = '',
  });

  final PwMediaKind kind;

  /// The pw.live page the user pasted (opened in the PW tab for playback).
  final String pageUrl;
  final String title;
  final String thumbnail;
  final int duration;

  /// URL handed to the download engine (empty for DRM lectures).
  final String mediaUrl;
  final Map<String, String> headers;
  final String note;
}

/// The ids a pw.live lecture link carries.
///
/// `https://www.pw.live/watch/?batchSlug=...&batchSubjectId=...&scheduleId=...
/// &parentId=<batch id>&childId=<schedule id>`
class PwLink {
  const PwLink({
    this.scheduleId = '',
    this.batches = const <String>[],
    this.subjects = const <String>[],
    this.typeHint = '',
  });

  final String scheduleId;

  /// Batch id first (when the link has one), then the batch slug.
  final List<String> batches;

  /// Batch-subject id first, then the subject slug.
  final List<String> subjects;

  /// `type=` of the link (`penpencilvdo`, `youtube`, ...), lower case.
  final String typeHint;

  bool get isLecture => scheduleId.isNotEmpty;

  static PwLink parse(String raw) {
    final Uri? uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.host.isEmpty) return const PwLink();
    return fromUri(uri);
  }

  static PwLink fromUri(Uri uri) {
    // Query keys are matched without case: scheduleId / scheduleid.
    final Map<String, String> q = <String, String>{};
    try {
      uri.queryParameters.forEach((String key, String value) {
        q.putIfAbsent(key.toLowerCase(), () => value.trim());
      });
    } catch (_) {
      // badly encoded query - fall back to the path only
    }
    final List<String> segments = uri.pathSegments;
    String after(String name) {
      final int index = segments.indexOf(name);
      if (index < 0 || index + 1 >= segments.length) return '';
      return segments[index + 1].trim();
    }

    String pick(List<String> values) {
      for (final String value in values) {
        if (_usable(value)) return value;
      }
      return '';
    }

    List<String> all(List<String> values) {
      final List<String> out = <String>[];
      for (final String value in values) {
        if (_usable(value) && !out.contains(value)) out.add(value);
      }
      return out;
    }

    return PwLink(
      scheduleId: pick(<String>[
        q['scheduleid'] ?? '',
        q['childid'] ?? '',
        q['lectureid'] ?? '',
        q['contentid'] ?? '',
        after('schedule'),
      ]),
      batches: all(<String>[
        q['parentid'] ?? '',
        q['batchid'] ?? '',
        q['batchslug'] ?? '',
        after('batches'),
        after('batch'),
      ]),
      subjects: all(<String>[
        q['batchsubjectid'] ?? '',
        q['subjectslug'] ?? '',
        q['subjectid'] ?? '',
        after('subjects'),
        after('subject'),
      ]),
      typeHint: pick(<String>[
        q['type'] ?? '',
        q['urltype'] ?? '',
      ]).toLowerCase(),
    );
  }

  static bool _usable(String value) {
    if (value.isEmpty || value.length > 120) return false;
    final String lower = value.toLowerCase();
    return lower != 'undefined' && lower != 'null' && lower != 'all';
  }
}

class _PwResponse {
  const _PwResponse(this.status, this.json);

  final int status;
  final Object? json;

  bool get ok => status >= 200 && status < 300;

  Map<String, dynamic> get map {
    final Object? value = json;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  Object? get data => map['data'];
}

/// PW account + API client (login with OTP, resolve lecture links).
class PwAccount {
  static const String webHome = 'https://www.pw.live/study-v2/batches';
  static const String webLogin = 'https://www.pw.live/';

  static const String _productionApi = 'https://api.penpencil.co';

  /// PW API server. Only the tests point this somewhere else.
  @visibleForTesting
  static String apiBase = _productionApi;

  static const String _org = '5eb393ee95fab7468a79d189';
  static const String _clientId = 'system-admin';
  static const String _clientSecret = 'KjPXuAVfC5xbmgreETNMaL7z';
  static const String _clientVersion = '6.0.6';
  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  static const String _keySession = 'videograb_pw_session_v1';
  static const String _keyDevice = 'videograb_pw_device_v1';

  static const Map<String, String> _cdnHeaders = <String, String>{
    'Referer': 'https://www.pw.live/',
    'Origin': 'https://www.pw.live',
  };

  static final ValueNotifier<PwSession?> session =
      ValueNotifier<PwSession?>(null);

  static String _deviceId = '';
  static String _rejectedToken = '';
  static bool _adopting = false;

  // A token PW answered 401 for although the login itself is fine (the
  // lecture is not in the account): no need to re-check it for every request.
  static String _checkedToken = '';
  static DateTime _checkedAt = DateTime.fromMillisecondsSinceEpoch(0);

  static bool get loggedIn => session.value != null;

  /// Forgets everything held in memory (tests only).
  @visibleForTesting
  static void resetForTest() {
    session.value = null;
    _deviceId = '';
    _rejectedToken = '';
    _adopting = false;
    _checkedToken = '';
    apiBase = _productionApi;
  }

  // ------------------------------------------------------------ lifecycle

  static Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _deviceId = prefs.getString(_keyDevice) ?? '';
      final String raw = prefs.getString(_keySession) ?? '';
      if (raw.isNotEmpty) {
        session.value = PwSession.fromJson(jsonDecode(raw));
      }
    } catch (_) {
      session.value = null;
    }
  }

  static Future<void> _ensureDevice() async {
    if (_deviceId.isNotEmpty) return;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String saved = prefs.getString(_keyDevice) ?? '';
    if (saved.isNotEmpty) {
      _deviceId = saved;
      return;
    }
    _deviceId = _uuid();
    await prefs.setString(_keyDevice, _deviceId);
  }

  static Future<void> _store(PwSession next) async {
    session.value = next;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySession, jsonEncode(next.toJson()));
  }

  /// Forgets the account on this phone.
  static Future<void> logout() async {
    final PwSession? current = session.value;
    if (current != null) _rejectedToken = current.accessToken;
    session.value = null;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySession);
  }

  // ---------------------------------------------------------------- login

  /// Sends the login OTP to [phone] (SMS, or WhatsApp when [whatsapp]).
  static Future<void> requestOtp(String phone, {bool whatsapp = false}) async {
    final String number = cleanPhone(phone);
    if (number.length != 10) {
      throw const PwException('10 digit ka mobile number daalein');
    }
    await _ensureDevice();
    final _PwResponse response = await _send(
      'POST',
      '/v1/users/get-otp',
      query: <String, String>{'smsType': whatsapp ? '1' : '0'},
      body: <String, dynamic>{
        'username': number,
        'countryCode': '+91',
        'organizationId': _org,
      },
      token: '',
    );
    if (!response.ok) {
      throw PwException(
        _errorOf(response, 'OTP nahi bheja ja saka'),
        status: response.status,
      );
    }
  }

  /// Exchanges phone + OTP for the account token.
  static Future<PwSession> verifyOtp(String phone, String otp) async {
    final String number = cleanPhone(phone);
    final String code = otp.replaceAll(RegExp(r'[^0-9]'), '');
    if (number.length != 10) {
      throw const PwException('10 digit ka mobile number daalein');
    }
    if (code.length < 4) {
      throw const PwException('SMS me aaya OTP daalein');
    }
    await _ensureDevice();
    final _PwResponse response = await _send(
      'POST',
      '/v3/oauth/token',
      body: <String, dynamic>{
        'username': number,
        'otp': code,
        'client_id': _clientId,
        'client_secret': _clientSecret,
        'grant_type': 'password',
        'organizationId': _org,
        'latitude': 0,
        'longitude': 0,
      },
      token: '',
    );
    if (!response.ok) {
      throw PwException(
        _errorOf(response, 'OTP galat hai ya expire ho gaya'),
        status: response.status,
      );
    }

    String access = '';
    String refresh = '';
    String name = '';
    final Object? data = response.data;
    if (data is Map) {
      access = _str(data['access_token']);
      refresh = _str(data['refresh_token']);
      final Object? user = data['user'];
      if (user is Map) name = _nameOf(user);
    }
    if (access.isEmpty) {
      throw const PwException('Login response me token nahi mila');
    }
    if (name.isEmpty) name = _nameFromJwt(access);

    final PwSession next = PwSession(
      accessToken: access,
      refreshToken: refresh,
      name: name,
      phone: number,
      source: 'otp',
    );
    await _store(next);
    return next;
  }

  /// Uses the token of the user's own pw.live login (PW tab). The token is
  /// checked against PW before it is trusted.
  static Future<bool> adoptToken(String raw) async {
    String token = raw.trim();
    if (token.toLowerCase().startsWith('bearer ')) {
      token = token.substring(7).trim();
    }
    if (!_looksLikeJwt(token)) return false;

    final PwSession? current = session.value;
    if (current != null) {
      if (current.accessToken == token) return true;
      // An in-app OTP login can refresh itself - keep it.
      if (current.source == 'otp') return true;
    }
    if (token == _rejectedToken || _adopting) return false;

    _adopting = true;
    try {
      await _ensureDevice();
      final _PwResponse response =
          await _send('GET', '/v1/users/self', token: token);
      if (!response.ok) {
        if (response.status == 401 || response.status == 403) {
          _rejectedToken = token;
        }
        return false;
      }
      String name = '';
      String phone = '';
      final Object? data = response.data;
      if (data is Map) {
        name = _nameOf(data);
        phone = cleanPhone(
          _first(<String>[
            _str(data['primaryNumber']),
            _str(data['username']),
            _str(data['mobile']),
          ]),
        );
      }
      if (name.isEmpty) name = _nameFromJwt(token);
      if (phone.length != 10) phone = '';
      // Logged out while the check was running.
      if (token == _rejectedToken) return false;
      await _store(
        PwSession(
          accessToken: token,
          name: name,
          phone: phone,
          source: 'web',
        ),
      );
      return true;
    } on PwException {
      return false;
    } finally {
      _adopting = false;
    }
  }

  static Future<bool> _refresh() async {
    final PwSession? current = session.value;
    if (current == null || current.refreshToken.isEmpty) return false;
    try {
      final _PwResponse response = await _send(
        'POST',
        '/v3/oauth/refresh-token',
        body: <String, dynamic>{
          'refresh_token': current.refreshToken,
          'client_id': _clientId,
        },
      );
      if (!response.ok) return false;
      final Object? data = response.data;
      if (data is! Map) return false;
      final String access = _str(data['access_token']);
      if (access.isEmpty) return false;
      final String refresh = _str(data['refresh_token']);
      await _store(
        PwSession(
          accessToken: access,
          refreshToken: refresh.isEmpty ? current.refreshToken : refresh,
          name: current.name,
          phone: current.phone,
          source: current.source,
        ),
      );
      return true;
    } on PwException {
      return false;
    }
  }

  // ------------------------------------------------------------- resolver

  /// True when [url] is a pw.live link to one lecture (it has a schedule id).
  static bool isLectureLink(String url) {
    final Uri? uri = Uri.tryParse(url.trim());
    if (uri == null || !isPwHost(uri.host)) return false;
    if (_isMediaPath(uri.path)) return false;
    return PwLink.fromUri(uri).isLecture;
  }

  /// True when [url] points straight at a video file or a manifest.
  static bool isMediaLink(String url) {
    final Uri? uri = Uri.tryParse(url.trim());
    return uri != null && uri.host.isNotEmpty && _isMediaPath(uri.path);
  }

  /// Turns a pw.live lecture link into something the app can act on.
  ///
  /// DRM (Widevine) lectures are reported as [PwMediaKind.drm]; the app does
  /// not fetch decryption keys and cannot download them.
  static Future<PwLecture> resolve(String rawUrl) async {
    final String link = rawUrl.trim();
    final Uri? uri = Uri.tryParse(link);
    if (uri == null || uri.host.isEmpty) {
      throw const PwException('Link sahi nahi hai');
    }

    // A direct CDN manifest / file link.
    if (_isMediaPath(uri.path)) {
      return _inspect(pageUrl: link, mediaUrl: link);
    }

    final PwLink ids = PwLink.fromUri(uri);
    if (!ids.isLecture) {
      throw const PwException(
        'Ye kisi lecture ka link nahi lag raha. PW par lecture kholkar uska '
        'link dein (pw.live/watch/?…scheduleId=…), ya lecture PW tab me '
        'kholkar wahan "Download" dabayein.',
      );
    }
    if (session.value == null) {
      throw const PwException(
        'PW lecture ke liye pehle apne PW account me login karein',
        needsLogin: true,
      );
    }
    if (ids.batches.isEmpty) {
      throw const PwException(
        'Link me batch ki jaankari nahi hai. Lecture ka poora link copy karein.',
      );
    }

    final List<String> trace = <String>[];
    try {
      return await _resolveLecture(link, ids, trace);
    } on PwException catch (error) {
      if (error.detail.isNotEmpty || trace.isEmpty) rethrow;
      throw PwException(
        error.message,
        status: error.status,
        needsLogin: error.needsLogin,
        detail: trace.join(' · '),
      );
    }
  }

  static Future<PwLecture> _resolveLecture(
    String link,
    PwLink ids,
    List<String> trace,
  ) async {
    final String scheduleId = ids.scheduleId;
    final List<String> batches = ids.batches;

    // 1) Lecture details: title, hosting type, DRM flag.
    Map<String, dynamic> details = <String, dynamic>{};
    String usedBatch = batches.first;
    String lastError = '';
    search:
    for (final String batch in batches) {
      for (final String subject in ids.subjects) {
        final _PwResponse response = await _authedGet(
          '/v1/batches/${Uri.encodeComponent(batch)}'
          '/subject/${Uri.encodeComponent(subject)}'
          '/schedule/${Uri.encodeComponent(scheduleId)}/schedule-details',
        );
        trace.add('details ${response.status}');
        final Object? data = response.data;
        if (response.ok && data is Map) {
          details = Map<String, dynamic>.from(data);
          usedBatch = batch;
          break search;
        }
        lastError = _errorOf(response, 'Lecture details nahi mile');
      }
    }

    final Object? rawVideo = details['videoDetails'];
    final Map<String, dynamic> video = rawVideo is Map
        ? Map<String, dynamic>.from(rawVideo)
        : <String, dynamic>{};
    final String title = _first(<String>[
      _str(details['topic']),
      _str(video['name']),
      _str(details['name']),
    ]);
    final String thumbnail = _str(video['image']);
    final int duration = _seconds(video['duration']);
    final String urlType = _first(<String>[
      _str(details['urlType']).toLowerCase(),
      ids.typeHint,
    ]);
    final String rawMedia = _first(<String>[
      _str(details['url']),
      _str(video['videoUrl']),
    ]);
    final bool flaggedDrm =
        video['drmProtected'] == true || details['drmProtected'] == true;
    if (urlType.isNotEmpty) trace.add('type $urlType');

    // 2) Lectures hosted on a normal video site.
    final String hostedUrl = _externalUrl(rawMedia, urlType);
    if (hostedUrl.isNotEmpty) {
      final bool vimeo = hostedUrl.contains('vimeo.com');
      return PwLecture(
        kind: PwMediaKind.external,
        pageUrl: link,
        title: title,
        thumbnail: thumbnail,
        duration: duration,
        mediaUrl: hostedUrl,
        headers: vimeo
            ? const <String, String>{'Referer': 'https://www.pw.live/'}
            : const <String, String>{},
        note: vimeo ? 'Vimeo par hosted lecture' : 'YouTube par hosted lecture',
      );
    }

    if (flaggedDrm) {
      return PwLecture(
        kind: PwMediaKind.drm,
        pageUrl: link,
        title: title,
        thumbnail: thumbnail,
        duration: duration,
      );
    }

    // 3) PW's own player: ask for the playback URL the account is entitled to.
    String manifest = '';
    final List<String> order = <String>[usedBatch];
    for (final String batch in batches) {
      if (!order.contains(batch)) order.add(batch);
    }
    for (final String batch in order) {
      final _PwResponse response = await _authedGet(
        '/v1/videos/video-url-details',
        query: <String, String>{
          'type': 'BATCHES',
          'videoContainerType': 'DASH',
          'reqType': 'query',
          'childId': scheduleId,
          'parentId': batch,
        },
      );
      trace.add('video-url ${response.status}');
      final Object? data = response.data;
      if (response.ok && data is Map) {
        final String base = _str(data['url']);
        if (base.isNotEmpty) {
          manifest = _joinSigned(base, _str(data['signedUrl']));
          break;
        }
      }
      lastError = _errorOf(response, 'Video URL nahi mila');
    }
    if (manifest.isEmpty && rawMedia.startsWith('http')) manifest = rawMedia;
    if (manifest.isEmpty) {
      throw PwException(
        lastError.isEmpty
            ? 'Is lecture ka video nahi mila. Check karein ki ye batch aapke '
                'account me hai.'
            : lastError,
      );
    }
    trace.add('media ${Uri.tryParse(manifest)?.host ?? '?'}');

    try {
      return await _inspect(
        pageUrl: link,
        mediaUrl: manifest,
        title: title,
        thumbnail: thumbnail,
        duration: duration,
      );
    } on PwException catch (error) {
      trace.add('manifest ${error.status == 0 ? 'error' : error.status}');
      rethrow;
    }
  }

  /// Reads the manifest and reports whether the stream is encrypted.
  static Future<PwLecture> _inspect({
    required String pageUrl,
    required String mediaUrl,
    String title = '',
    String thumbnail = '',
    int duration = 0,
  }) async {
    PwLecture result(PwMediaKind kind) {
      return PwLecture(
        kind: kind,
        pageUrl: pageUrl,
        title: title,
        thumbnail: thumbnail,
        duration: duration,
        mediaUrl: kind == PwMediaKind.drm ? '' : mediaUrl,
        headers: kind == PwMediaKind.drm
            ? const <String, String>{}
            : _cdnHeaders,
      );
    }

    final Uri? uri = Uri.tryParse(mediaUrl);
    if (uri == null) return result(PwMediaKind.stream);
    final String path = uri.path.toLowerCase();
    final bool manifest = path.endsWith('.mpd') || path.endsWith('.m3u8');
    if (!manifest) return result(PwMediaKind.stream);

    final String text = await _fetchText(uri);
    if (_hasDrmMarkers(text)) return result(PwMediaKind.drm);

    // HLS master playlist: the key lines live in the variant playlists.
    if (text.contains('#EXT-X-STREAM-INF')) {
      final Uri? variant = _firstVariant(uri, text);
      if (variant != null) {
        try {
          final String child = await _fetchText(variant);
          if (_hasDrmMarkers(child)) return result(PwMediaKind.drm);
        } on PwException {
          // The engine reports protected streams on its own.
        }
      }
    }
    return result(PwMediaKind.stream);
  }

  static Future<String> _fetchText(Uri uri) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final HttpClientRequest request =
          await client.getUrl(uri).timeout(const Duration(seconds: 20));
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      _cdnHeaders.forEach(request.headers.set);
      final HttpClientResponse response =
          await request.close().timeout(const Duration(seconds: 25));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw PwException(
          'Video stream open nahi hua (HTTP ${response.statusCode}). Lecture '
          'PW tab me chalakar dekhein.',
          status: response.statusCode,
        );
      }
      final List<int> bytes = <int>[];
      await for (final List<int> chunk
          in response.timeout(const Duration(seconds: 20))) {
        bytes.addAll(chunk);
        if (bytes.length > 600000) break;
      }
      return const Utf8Decoder(allowMalformed: true).convert(bytes);
    } on SocketException {
      throw const PwException('Internet connection check karein');
    } on TimeoutException {
      throw const PwException('Video server ne time par jawab nahi diya');
    } on HandshakeException {
      throw const PwException('Secure connection nahi ban paya');
    } on HttpException {
      throw const PwException('Video server se connection toot gaya');
    } finally {
      client.close(force: true);
    }
  }

  static bool _hasDrmMarkers(String manifest) {
    final String lower = manifest.toLowerCase();
    return lower.contains('<contentprotection') ||
        lower.contains('cenc:default_kid') ||
        lower.contains('urn:mpeg:dash:mp4protection') ||
        lower.contains('edef8ba9-79d6-4ace-a3c8-27dcd51d21ed') ||
        lower.contains('9a04f079-9840-4286-ab92-e65be0885f95') ||
        lower.contains('method=sample-aes') ||
        lower.contains('#ext-x-session-key') ||
        lower.contains('keyformat=') ||
        lower.contains('skd://');
  }

  static Uri? _firstVariant(Uri master, String text) {
    final List<String> lines = const LineSplitter().convert(text);
    for (int i = 0; i < lines.length; i++) {
      if (!lines[i].startsWith('#EXT-X-STREAM-INF')) continue;
      for (int j = i + 1; j < lines.length; j++) {
        final String line = lines[j].trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        Uri resolved = master.resolve(line);
        if (!resolved.hasQuery && master.hasQuery) {
          resolved = resolved.replace(query: master.query);
        }
        return resolved;
      }
    }
    return null;
  }

  // ----------------------------------------------------------------- http

  /// Authenticated GET with one token refresh on 401.
  static Future<_PwResponse> _authedGet(
    String path, {
    Map<String, String> query = const <String, String>{},
  }) async {
    if (session.value == null) {
      throw const PwException(
        'PW lecture ke liye pehle apne PW account me login karein',
        needsLogin: true,
      );
    }
    await _ensureDevice();
    _PwResponse response = await _send('GET', path, query: query);
    if (response.status != 401) return response;

    final String failed = session.value?.accessToken ?? '';
    if (failed.isNotEmpty &&
        failed == _checkedToken &&
        DateTime.now().difference(_checkedAt) < const Duration(minutes: 1)) {
      return response;
    }

    if (await _refresh()) {
      response = await _send('GET', path, query: query);
      if (response.status != 401) return response;
    }

    // Is the login itself dead, or is only this lecture not allowed?
    final _PwResponse self = await _send('GET', '/v1/users/self');
    if (self.ok) {
      _checkedToken = session.value?.accessToken ?? '';
      _checkedAt = DateTime.now();
      return response;
    }

    await logout();
    throw const PwException(
      'PW session expire ho gaya — dobara login karein',
      status: 401,
      needsLogin: true,
    );
  }

  static Future<_PwResponse> _send(
    String method,
    String path, {
    Map<String, String> query = const <String, String>{},
    Map<String, dynamic>? body,
    String? token,
  }) async {
    Uri uri = Uri.parse('$apiBase$path');
    if (query.isNotEmpty) uri = uri.replace(queryParameters: query);

    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final HttpClientRequest request =
          await client.openUrl(method, uri).timeout(const Duration(seconds: 20));
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/json, text/plain, */*',
      );
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      request.headers.set(HttpHeaders.refererHeader, 'https://www.pw.live/');
      request.headers.set('origin', 'https://www.pw.live');
      request.headers.set('client-id', _org);
      request.headers.set('client-type', 'WEB');
      request.headers.set('client-version', _clientVersion);
      request.headers.set('randomid', _deviceId);

      final String bearer = token ?? (session.value?.accessToken ?? '');
      if (bearer.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
      }
      if (body != null) {
        final List<int> bytes = utf8.encode(jsonEncode(body));
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        request.contentLength = bytes.length;
        request.add(bytes);
      }

      final HttpClientResponse response =
          await request.close().timeout(const Duration(seconds: 25));
      final String text = await response
          .transform(const Utf8Decoder(allowMalformed: true))
          .join()
          .timeout(const Duration(seconds: 25));

      Object? decoded;
      try {
        decoded = text.isEmpty ? null : jsonDecode(text);
      } catch (_) {
        decoded = null;
      }
      return _PwResponse(response.statusCode, decoded);
    } on SocketException {
      throw const PwException('Internet connection check karein');
    } on TimeoutException {
      throw const PwException('PW server ne time par jawab nahi diya');
    } on HandshakeException {
      throw const PwException('PW server se secure connection nahi ban paya');
    } on HttpException {
      throw const PwException('PW server se connection toot gaya');
    } finally {
      client.close(force: true);
    }
  }

  static String _errorOf(_PwResponse response, String fallback) {
    final Map<String, dynamic> map = response.map;
    final Object? error = map['error'];
    if (error is Map) {
      final String message = _str(error['message']);
      if (message.isNotEmpty) return message;
    } else if (error is String && error.trim().isNotEmpty) {
      return error.trim();
    }
    final String message = _str(map['message']);
    if (message.isNotEmpty) return message;
    final Object? data = map['data'];
    if (data is Map) {
      final String nested = _str(data['message']);
      if (nested.isNotEmpty) return nested;
    }
    return '$fallback (HTTP ${response.status})';
  }

  // -------------------------------------------------------------- helpers

  /// Hosts that belong to PW - the only ones that may ever see the session.
  static bool isPwHost(String host) {
    final String value = host.toLowerCase();
    return _hostIs(value, 'pw.live') || _hostIs(value, 'penpencil.co');
  }

  static bool _hostIs(String host, String domain) =>
      host == domain || host.endsWith('.$domain');

  static String cleanPhone(String raw) {
    String digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 12 && digits.startsWith('91')) {
      digits = digits.substring(2);
    } else if (digits.length == 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return digits;
  }

  static String _str(Object? value) {
    if (value is String) return value.trim();
    if (value is num) return value.toString();
    return '';
  }

  static String _first(List<String> values) {
    for (final String value in values) {
      if (value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  static String _nameOf(Map<dynamic, dynamic> user) {
    final String full =
        '${_str(user['firstName'])} ${_str(user['lastName'])}'.trim();
    if (full.isNotEmpty) return full;
    return _str(user['name']);
  }

  static bool _looksLikeJwt(String token) {
    if (token.length < 60 || token.length > 4096) return false;
    return RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$')
        .hasMatch(token);
  }

  static String _nameFromJwt(String token) {
    try {
      final List<String> parts = token.split('.');
      if (parts.length != 3) return '';
      final Object? payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map) return '';
      final Object? data = payload['data'];
      if (data is Map) {
        final String name = _nameOf(data);
        if (name.isNotEmpty) return name;
      }
      return _nameOf(payload);
    } catch (_) {
      return '';
    }
  }

  static bool _isMediaPath(String path) {
    final String lower = path.toLowerCase();
    return lower.endsWith('.mpd') ||
        lower.endsWith('.m3u8') ||
        lower.endsWith('.mp4') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.m4a');
  }

  /// Returns a normal video-site URL when the lecture is hosted on one.
  static String _externalUrl(String rawMedia, String urlType) {
    final String media = rawMedia.trim();
    final Uri? uri = media.startsWith('http') ? Uri.tryParse(media) : null;
    final String host = uri?.host.toLowerCase() ?? '';

    final bool youtubeHost = host == 'youtu.be' ||
        _hostIs(host, 'youtube.com') ||
        _hostIs(host, 'youtube-nocookie.com');
    if (youtubeHost && uri != null) {
      final List<String> segments = uri.pathSegments;
      final int embed = segments.indexOf('embed');
      if (embed >= 0 && embed + 1 < segments.length) {
        return 'https://www.youtube.com/watch?v=${segments[embed + 1]}';
      }
      return media;
    }
    if (urlType.contains('youtube') &&
        RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(media)) {
      return 'https://www.youtube.com/watch?v=$media';
    }
    if (_hostIs(host, 'vimeo.com')) return media;
    return '';
  }

  static String _joinSigned(String base, String signed) {
    final String extra = signed.trim();
    if (extra.isEmpty) return base;
    if (extra.startsWith('http')) return extra;
    final String tail =
        (extra.startsWith('?') || extra.startsWith('&')) ? extra.substring(1) : extra;
    if (tail.isEmpty) return base;
    return base.contains('?') ? '$base&$tail' : '$base?$tail';
  }

  static int _seconds(Object? raw) {
    if (raw is num) return raw.toInt();
    if (raw is! String) return 0;
    final String text = raw.trim();
    if (text.isEmpty) return 0;
    final int? plain = int.tryParse(text);
    if (plain != null) return plain;
    int total = 0;
    for (final String part in text.split(':')) {
      final int? value = int.tryParse(part.trim());
      if (value == null) return 0;
      total = total * 60 + value;
    }
    return total;
  }

  static String _uuid() {
    final Random random = Random.secure();
    final List<int> bytes =
        List<int>.generate(16, (int index) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int start, int end) {
      final StringBuffer buffer = StringBuffer();
      for (int i = start; i < end; i++) {
        buffer.write(bytes[i].toRadixString(16).padLeft(2, '0'));
      }
      return buffer.toString();
    }

    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }
}
