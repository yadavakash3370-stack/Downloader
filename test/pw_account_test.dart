// PW account client, exercised against a local stand-in for PW's API and
// video CDN. Nothing here talks to the real servers.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videograb/services/pw_account.dart';

/// One request the fake server received.
class Seen {
  Seen(this.method, this.uri, this.headers, this.body);

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String body;

  String get path => uri.path;
  Map<String, String> get query => uri.queryParameters;
  Map<String, dynamic> get json =>
      Map<String, dynamic>.from(jsonDecode(body) as Map<dynamic, dynamic>);
  String header(String name) => headers[name.toLowerCase()] ?? '';
}

class Reply {
  const Reply(this.status, this.body);

  final int status;

  /// A Map is sent as JSON, a String as it is (manifests).
  final Object? body;
}

typedef Handler = Reply Function(Seen request);

/// Stands in for api.penpencil.co and the video CDN.
class FakePw {
  late HttpServer _server;
  final List<Seen> seen = <Seen>[];
  final Map<String, Handler> _routes = <String, Handler>{};

  String get base => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() async {
    await _server.close(force: true);
  }

  void on(String method, String path, Handler handler) {
    _routes['$method $path'] = handler;
  }

  List<Seen> calls(String path) =>
      seen.where((Seen request) => request.path == path).toList();

  Future<void> _handle(HttpRequest request) async {
    final String body = await utf8.decoder.bind(request).join();
    final Map<String, String> headers = <String, String>{};
    request.headers.forEach((String name, List<String> values) {
      headers[name.toLowerCase()] = values.join(', ');
    });
    final Seen record = Seen(request.method, request.uri, headers, body);
    seen.add(record);

    final Handler? handler = _routes['${request.method} ${request.uri.path}'];
    final Reply reply = handler == null
        ? const Reply(404, <String, dynamic>{
            'success': false,
            'error': <String, dynamic>{'message': 'Not found', 'status': 404},
          })
        : handler(record);

    request.response.statusCode = reply.status;
    final Object? payload = reply.body;
    if (payload is String) {
      request.response.headers.contentType = ContentType.text;
      request.response.write(payload);
    } else {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(payload));
    }
    await request.response.close();
  }
}

const String batchId = '676e4dee1ec923bc192f38c9';
const String batchSlug = 'arjuna-jee-2026-123456';
const String subjectId = '5f709c26796f410011b7b80b';
const String subjectSlug = 'physics-553415';
const String scheduleId = '684845e3ce9a26973819ddd9';

/// The link the PW website shows while a lecture is playing.
const String watchUrl = 'https://www.pw.live/watch/?batchSlug=$batchSlug'
    '&batchSubjectId=$subjectId&subjectSlug=$subjectSlug&topicSlug=all'
    '&scheduleId=$scheduleId&type=penpencilvdo&isPPJEnabled=true'
    '&entryPoint=BATCH_LECTURE_VIDEOS_$scheduleId&learn2Earn=true'
    '&parentId=$batchId&vType=BATCHES&childId=$scheduleId';

const String detailsPath = '/v1/batches/$batchId/subject/$subjectId'
    '/schedule/$scheduleId/schedule-details';
const String videoUrlPath = '/v1/videos/video-url-details';
const String selfPath = '/v1/users/self';
const String refreshPath = '/v3/oauth/refresh-token';

const String drmMpd = '<?xml version="1.0"?>\n'
    '<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" '
    'xmlns:cenc="urn:mpeg:cenc:2013">\n'
    ' <Period><AdaptationSet mimeType="video/mp4">\n'
    '  <ContentProtection schemeIdUri="urn:mpeg:dash:mp4protection:2011" '
    'value="cenc" cenc:default_KID="0123"/>\n'
    '  <ContentProtection '
    'schemeIdUri="urn:uuid:edef8ba9-79d6-4ace-a3c8-27dcd51d21ed"/>\n'
    '  <Representation id="1" bandwidth="800000" height="720"/>\n'
    ' </AdaptationSet></Period>\n'
    '</MPD>\n';

const String clearMpd = '<?xml version="1.0"?>\n'
    '<MPD xmlns="urn:mpeg:dash:schema:mpd:2011">\n'
    ' <Period><AdaptationSet mimeType="video/mp4">\n'
    '  <Representation id="1" bandwidth="800000" height="720"/>\n'
    ' </AdaptationSet></Period>\n'
    '</MPD>\n';

const String hlsMaster = '#EXTM3U\n'
    '#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=1280x720\n'
    '720/index.m3u8\n';
const String hlsClear = '#EXTM3U\n#EXT-X-TARGETDURATION:6\n'
    '#EXTINF:6.0,\nseg0.ts\n#EXT-X-ENDLIST\n';
const String hlsAes128 = '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="enc.key"\n'
    '#EXTINF:6.0,\nseg0.ts\n#EXT-X-ENDLIST\n';
const String hlsFairplay = '#EXTM3U\n'
    '#EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://abc",'
    'KEYFORMAT="com.apple.streamingkeydelivery"\n'
    '#EXTINF:6.0,\nseg0.ts\n#EXT-X-ENDLIST\n';

const Reply unauthorized = Reply(401, <String, dynamic>{
  'success': false,
  'error': <String, dynamic>{'message': 'Unauthorized', 'status': 401},
});

/// A token shaped like PW's (three base64url parts, name in the payload).
String jwt(String first, String last, {String salt = 'a'}) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final String header = part(<String, String>{'alg': 'HS256', 'typ': 'JWT'});
  final String payload = part(<String, dynamic>{
    'data': <String, String>{'firstName': first, 'lastName': last},
    'salt': salt,
  });
  return '$header.$payload.${salt * 43}';
}

Reply ok(Map<String, dynamic> data) =>
    Reply(200, <String, dynamic>{'success': true, 'data': data});

Reply apiError(int status, String message) => Reply(status, <String, dynamic>{
      'success': false,
      'error': <String, dynamic>{'message': message, 'status': status},
    });

/// Logs in through the fake OTP endpoint and returns the access token.
Future<String> login(FakePw pw, {String refresh = 'refresh-1'}) async {
  final String token = jwt('Akash', 'Yadav');
  pw.on('POST', '/v3/oauth/token', (Seen request) {
    return ok(<String, dynamic>{
      'access_token': token,
      'refresh_token': refresh,
      'user': <String, dynamic>{'firstName': 'Akash', 'lastName': 'Yadav'},
    });
  });
  await PwAccount.verifyOtp('9876543210', '123456');
  return token;
}

Future<PwException> failure(Future<Object?> Function() run) async {
  try {
    await run();
  } on PwException catch (error) {
    return error;
  }
  fail('expected a PwException');
}

void main() {
  late FakePw pw;

  setUp(() async {
    // Real sockets: the fake server listens on localhost.
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PwAccount.resetForTest();
    pw = FakePw();
    await pw.start();
    PwAccount.apiBase = pw.base;
  });

  tearDown(() async {
    await pw.stop();
    PwAccount.resetForTest();
  });

  group('lecture links', () {
    test('watch link gives schedule, batch and subject ids', () {
      final PwLink link = PwLink.parse(watchUrl);
      expect(link.isLecture, isTrue);
      expect(link.scheduleId, scheduleId);
      expect(link.batches, <String>[batchId, batchSlug]);
      expect(link.subjects, <String>[subjectId, subjectSlug]);
      expect(link.typeHint, 'penpencilvdo');
      expect(PwAccount.isLectureLink(watchUrl), isTrue);
    });

    test('query names are matched without case', () {
      final PwLink link = PwLink.parse(
        'https://www.pw.live/watch/?BatchSlug=$batchSlug'
        '&SCHEDULEID=$scheduleId&subjectslug=$subjectSlug',
      );
      expect(link.scheduleId, scheduleId);
      expect(link.batches, <String>[batchSlug]);
      expect(link.subjects, <String>[subjectSlug]);
    });

    test('batch slug is read from a study-v2 path', () {
      final PwLink link = PwLink.parse(
        'https://www.pw.live/study-v2/batches/$batchSlug/subjects'
        '/$subjectSlug/lecture?scheduleId=$scheduleId',
      );
      expect(link.scheduleId, scheduleId);
      expect(link.batches, <String>[batchSlug]);
      expect(link.subjects, <String>[subjectSlug]);
    });

    test('a batch page is not a lecture link', () {
      const String page = 'https://www.pw.live/study-v2/batches/$batchSlug'
          '/batch-overview?topicSlug=all&scheduleId=undefined';
      expect(PwLink.parse(page).isLecture, isFalse);
      expect(PwAccount.isLectureLink(page), isFalse);
      expect(PwAccount.isLectureLink(PwAccount.webHome), isFalse);
      expect(PwAccount.isLectureLink('not a link'), isFalse);
    });

    test('only PW hosts count as lecture links', () {
      expect(
        PwAccount.isLectureLink(
          'https://example.com/watch/?scheduleId=$scheduleId',
        ),
        isFalse,
      );
      expect(PwAccount.isPwHost('www.pw.live'), isTrue);
      expect(PwAccount.isPwHost('api.penpencil.co'), isTrue);
      expect(PwAccount.isPwHost('pw.live.example.com'), isFalse);
      expect(PwAccount.isPwHost('notpw.live'), isFalse);
    });

    test('stream links are recognised by their file type', () {
      expect(
        PwAccount.isMediaLink('https://cdn.example.net/a/master.mpd?x=1'),
        isTrue,
      );
      expect(
        PwAccount.isMediaLink('https://cdn.example.net/a/index.m3u8'),
        isTrue,
      );
      expect(PwAccount.isMediaLink(watchUrl), isFalse);
      expect(PwAccount.isLectureLink('https://www.pw.live/a/b.mp4'), isFalse);
    });

    test('phone numbers are reduced to ten digits', () {
      expect(PwAccount.cleanPhone('+91 98765 43210'), '9876543210');
      expect(PwAccount.cleanPhone('098765-43210'), '9876543210');
      expect(PwAccount.cleanPhone('9876543210'), '9876543210');
    });
  });

  group('login', () {
    test('OTP request carries the number and the web client headers',
        () async {
      pw.on(
        'POST',
        '/v1/users/get-otp',
        (Seen request) => const Reply(200, <String, dynamic>{'success': true}),
      );

      await PwAccount.requestOtp('+91 98765 43210');

      final Seen request = pw.calls('/v1/users/get-otp').single;
      expect(request.method, 'POST');
      expect(request.query['smsType'], '0');
      expect(request.json['username'], '9876543210');
      expect(request.json['countryCode'], '+91');
      expect(request.json['organizationId'], '5eb393ee95fab7468a79d189');
      expect(request.header('client-id'), '5eb393ee95fab7468a79d189');
      expect(request.header('client-type'), 'WEB');
      expect(request.header('content-type'), startsWith('application/json'));
      expect(
        request.header('randomid'),
        matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[0-9a-f]{4}-'
            r'[0-9a-f]{12}$')),
      );
      expect(request.header('authorization'), isEmpty);
    });

    test('WhatsApp OTP uses smsType 1', () async {
      pw.on(
        'POST',
        '/v1/users/get-otp',
        (Seen request) => const Reply(201, <String, dynamic>{'success': true}),
      );
      await PwAccount.requestOtp('9876543210', whatsapp: true);
      expect(pw.calls('/v1/users/get-otp').single.query['smsType'], '1');
    });

    test('PW error text reaches the user', () async {
      pw.on(
        'POST',
        '/v1/users/get-otp',
        (Seen request) => apiError(400, 'User not registered'),
      );
      final PwException error =
          await failure(() => PwAccount.requestOtp('9876543210'));
      expect(error.message, 'User not registered');
      expect(error.status, 400);
      expect(error.needsLogin, isFalse);
    });

    test('a short number is refused before any request', () async {
      final PwException error =
          await failure(() => PwAccount.requestOtp('12345'));
      expect(error.message, contains('10 digit'));
      expect(pw.seen, isEmpty);
    });

    test('OTP login stores the account and survives a restart', () async {
      final String token = await login(pw);

      final Seen request = pw.calls('/v3/oauth/token').single;
      expect(request.json['username'], '9876543210');
      expect(request.json['otp'], '123456');
      expect(request.json['grant_type'], 'password');
      expect(request.json['client_id'], 'system-admin');
      expect(request.json['organizationId'], '5eb393ee95fab7468a79d189');
      expect(request.header('authorization'), isEmpty);

      PwSession? session = PwAccount.session.value;
      expect(session, isNotNull);
      expect(session!.accessToken, token);
      expect(session.refreshToken, 'refresh-1');
      expect(session.displayName, 'Akash Yadav');
      expect(session.source, 'otp');

      // App restart: memory is gone, the saved login comes back.
      PwAccount.session.value = null;
      await PwAccount.load();
      session = PwAccount.session.value;
      expect(session, isNotNull);
      expect(session!.accessToken, token);
      expect(session.phone, '9876543210');
    });

    test('name falls back to the token when the reply has no user',
        () async {
      final String token = jwt('Ravi', 'Kumar');
      pw.on(
        'POST',
        '/v3/oauth/token',
        (Seen request) => ok(<String, dynamic>{'access_token': token}),
      );
      final PwSession session =
          await PwAccount.verifyOtp('9876543210', '123456');
      expect(session.displayName, 'Ravi Kumar');
      expect(session.refreshToken, isEmpty);
    });

    test('a wrong OTP reports PW\'s message and stores nothing', () async {
      pw.on(
        'POST',
        '/v3/oauth/token',
        (Seen request) => apiError(400, 'Invalid OTP'),
      );
      final PwException error =
          await failure(() => PwAccount.verifyOtp('9876543210', '000000'));
      expect(error.message, 'Invalid OTP');
      expect(PwAccount.loggedIn, isFalse);
    });

    test('logout forgets the saved login', () async {
      await login(pw);
      await PwAccount.logout();
      expect(PwAccount.loggedIn, isFalse);
      await PwAccount.load();
      expect(PwAccount.loggedIn, isFalse);
    });
  });

  group('website login', () {
    test('a valid site token becomes the account', () async {
      final String token = jwt('Site', 'User');
      pw.on(
        'GET',
        selfPath,
        (Seen request) => ok(<String, dynamic>{
          'firstName': 'Site',
          'lastName': 'User',
          'primaryNumber': '9876543210',
        }),
      );

      expect(await PwAccount.adoptToken('Bearer $token'), isTrue);

      final PwSession session = PwAccount.session.value!;
      expect(session.accessToken, token);
      expect(session.source, 'web');
      expect(session.phone, '9876543210');
      expect(session.displayName, 'Site User');
      expect(
        pw.calls(selfPath).single.header('authorization'),
        'Bearer $token',
      );
    });

    test('a token PW rejects is not stored and not retried', () async {
      final String token = jwt('Old', 'Login');
      pw.on('GET', selfPath, (Seen request) => unauthorized);

      expect(await PwAccount.adoptToken(token), isFalse);
      expect(await PwAccount.adoptToken(token), isFalse);
      expect(PwAccount.loggedIn, isFalse);
      expect(pw.calls(selfPath), hasLength(1));
    });

    test('text that is not a token is ignored without a request', () async {
      expect(await PwAccount.adoptToken('hello'), isFalse);
      expect(await PwAccount.adoptToken(''), isFalse);
      expect(pw.seen, isEmpty);
    });

    test('an OTP login is never replaced by a site token', () async {
      final String token = await login(pw);
      expect(await PwAccount.adoptToken(jwt('Someone', 'Else')), isTrue);
      expect(PwAccount.session.value!.accessToken, token);
      expect(pw.calls(selfPath), isEmpty);
    });

    test('the token of a logged-out account is not taken back', () async {
      final String token = jwt('Site', 'User');
      pw.on(
        'GET',
        selfPath,
        (Seen request) => ok(<String, dynamic>{'firstName': 'Site'}),
      );
      expect(await PwAccount.adoptToken(token), isTrue);
      await PwAccount.logout();
      expect(await PwAccount.adoptToken(token), isFalse);
      expect(PwAccount.loggedIn, isFalse);
    });
  });

  group('lecture resolver', () {
    test('asks for login first', () async {
      final PwException error =
          await failure(() => PwAccount.resolve(watchUrl));
      expect(error.needsLogin, isTrue);
      expect(pw.seen, isEmpty);
    });

    test('a page without a lecture id is explained, not sent to PW',
        () async {
      await login(pw);
      final int before = pw.seen.length;
      final PwException error = await failure(
        () => PwAccount.resolve(
          'https://www.pw.live/study-v2/batches/$batchSlug/batch-overview',
        ),
      );
      expect(error.needsLogin, isFalse);
      expect(error.message, contains('lecture ka link nahi'));
      expect(pw.seen, hasLength(before));
    });

    test('YouTube-hosted lecture goes to the normal engine', () async {
      final String token = await login(pw);
      pw.on(
        'GET',
        detailsPath,
        (Seen request) => ok(<String, dynamic>{
          'topic': 'Kinematics 01',
          'urlType': 'youtube',
          'url': 'https://www.youtube.com/embed/dQw4w9WgXcQ',
          'videoDetails': <String, dynamic>{
            'name': 'ignored',
            'image': 'https://static.pw.live/thumb.jpg',
            'duration': '01:02:03',
          },
        }),
      );

      final PwLecture lecture = await PwAccount.resolve(watchUrl);

      expect(lecture.kind, PwMediaKind.external);
      expect(lecture.mediaUrl, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(lecture.title, 'Kinematics 01');
      expect(lecture.thumbnail, 'https://static.pw.live/thumb.jpg');
      expect(lecture.duration, 3723);
      expect(lecture.headers, isEmpty);
      expect(lecture.pageUrl, watchUrl);

      final Seen request = pw.calls(detailsPath).single;
      expect(request.header('authorization'), 'Bearer $token');
      expect(request.header('client-type'), 'WEB');
      expect(pw.calls(videoUrlPath), isEmpty);
    });

    test('a bare YouTube id is turned into a watch link', () async {
      await login(pw);
      pw.on(
        'GET',
        detailsPath,
        (Seen request) => ok(<String, dynamic>{
          'urlType': 'youtube',
          'url': 'dQw4w9WgXcQ',
        }),
      );
      final PwLecture lecture = await PwAccount.resolve(watchUrl);
      expect(lecture.kind, PwMediaKind.external);
      expect(lecture.mediaUrl, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    });

    test('lecture flagged DRM is reported without asking for a stream',
        () async {
      await login(pw);
      pw.on(
        'GET',
        detailsPath,
        (Seen request) => ok(<String, dynamic>{
          'urlType': 'penpencilvdo',
          'url': 'https://cdn.example.net/abc/master.mpd',
          'videoDetails': <String, dynamic>{
            'name': 'Laws of Motion 03',
            'duration': 5400,
            'drmProtected': true,
          },
        }),
      );

      final PwLecture lecture = await PwAccount.resolve(watchUrl);

      expect(lecture.kind, PwMediaKind.drm);
      expect(lecture.mediaUrl, isEmpty);
      expect(lecture.headers, isEmpty);
      expect(lecture.title, 'Laws of Motion 03');
      expect(lecture.duration, 5400);
      expect(lecture.pageUrl, watchUrl);
      expect(pw.calls(videoUrlPath), isEmpty);
    });

    test('encrypted manifest is detected; the login never goes to the CDN',
        () async {
      await login(pw);
      pw.on(
        'GET',
        detailsPath,
        (Seen request) => ok(<String, dynamic>{
          'urlType': 'penpencilvdo',
          'url': '${pw.base}/cdn/abc/master.mpd',
          'videoDetails': <String, dynamic>{'name': 'Thermo 02'},
        }),
      );
      pw.on(
        'GET',
        videoUrlPath,
        (Seen request) => ok(<String, dynamic>{
          'url': '${pw.base}/cdn/abc/master.mpd',
          'signedUrl': '?Policy=p1&Signature=s1&Key-Pair-Id=k1',
        }),
      );
      pw.on('GET', '/cdn/abc/master.mpd', (Seen request) {
        return const Reply(200, drmMpd);
      });

      final PwLecture lecture = await PwAccount.resolve(watchUrl);

      expect(lecture.kind, PwMediaKind.drm);
      expect(lecture.mediaUrl, isEmpty);
      expect(lecture.title, 'Thermo 02');

      final Seen api = pw.calls(videoUrlPath).single;
      expect(api.query['type'], 'BATCHES');
      expect(api.query['childId'], scheduleId);
      expect(api.query['parentId'], batchId);
      expect(api.query['videoContainerType'], 'DASH');

      final Seen cdn = pw.calls('/cdn/abc/master.mpd').single;
      expect(cdn.query['Policy'], 'p1');
      expect(cdn.query['Signature'], 's1');
      expect(cdn.query['Key-Pair-Id'], 'k1');
      expect(cdn.header('referer'), 'https://www.pw.live/');
      expect(cdn.header('authorization'), isEmpty);
    });

    test('plain DASH lecture is handed over with its signed link', () async {
      await login(pw);
      pw.on(
        'GET',
        detailsPath,
        (Seen request) => ok(<String, dynamic>{
          'urlType': 'penpencilvdo',
          'videoDetails': <String, dynamic>{'name': 'Optics 01'},
        }),
      );
      pw.on(
        'GET',
        videoUrlPath,
        (Seen request) => ok(<String, dynamic>{
          'url': '${pw.base}/cdn/open/master.mpd',
          'signedUrl': '?Policy=p3',
        }),
      );
      pw.on('GET', '/cdn/open/master.mpd', (Seen request) {
        return const Reply(200, clearMpd);
      });

      final PwLecture lecture = await PwAccount.resolve(watchUrl);

      expect(lecture.kind, PwMediaKind.stream);
      expect(lecture.mediaUrl, '${pw.base}/cdn/open/master.mpd?Policy=p3');
      expect(lecture.headers['Referer'], 'https://www.pw.live/');
      expect(lecture.headers['Origin'], 'https://www.pw.live');
      expect(lecture.headers.keys.map((String key) => key.toLowerCase()),
          isNot(contains('authorization')));
      expect(lecture.title, 'Optics 01');
    });

    test('plain HLS lecture: the variant playlist is checked too', () async {
      await login(pw);
      pw.on(
        'GET',
        videoUrlPath,
        (Seen request) => ok(<String, dynamic>{
          'url': '${pw.base}/cdn/xyz/master.m3u8',
          'signedUrl': 'Policy=p2',
        }),
      );
      pw.on('GET', '/cdn/xyz/master.m3u8', (Seen request) {
        return const Reply(200, hlsMaster);
      });
      pw.on('GET', '/cdn/xyz/720/index.m3u8', (Seen request) {
        return const Reply(200, hlsClear);
      });
      // No schedule-details route: the lecture must still resolve.

      final PwLecture lecture = await PwAccount.resolve(watchUrl);

      expect(lecture.kind, PwMediaKind.stream);
      expect(lecture.mediaUrl, '${pw.base}/cdn/xyz/master.m3u8?Policy=p2');
      final Seen variant = pw.calls('/cdn/xyz/720/index.m3u8').single;
      expect(variant.query['Policy'], 'p2');
      expect(variant.header('authorization'), isEmpty);
    });

    test('AES-128 HLS is a normal stream', () async {
      await login(pw);
      pw.on(
        'GET',
        videoUrlPath,
        (Seen request) => ok(<String, dynamic>{
          'url': '${pw.base}/cdn/aes/master.m3u8',
        }),
      );
      pw.on('GET', '/cdn/aes/master.m3u8', (Seen request) {
        return const Reply(200, hlsMaster);
      });
      pw.on('GET', '/cdn/aes/720/index.m3u8', (Seen request) {
        return const Reply(200, hlsAes128);
      });

      final PwLecture lecture = await PwAccount.resolve(watchUrl);
      expect(lecture.kind, PwMediaKind.stream);
      expect(lecture.mediaUrl, '${pw.base}/cdn/aes/master.m3u8');
    });

    test('FairPlay HLS is reported as DRM', () async {
      await login(pw);
      pw.on(
        'GET',
        videoUrlPath,
        (Seen request) => ok(<String, dynamic>{
          'url': '${pw.base}/cdn/fp/master.m3u8',
        }),
      );
      pw.on('GET', '/cdn/fp/master.m3u8', (Seen request) {
        return const Reply(200, hlsMaster);
      });
      pw.on('GET', '/cdn/fp/720/index.m3u8', (Seen request) {
        return const Reply(200, hlsFairplay);
      });

      final PwLecture lecture = await PwAccount.resolve(watchUrl);
      expect(lecture.kind, PwMediaKind.drm);
      expect(lecture.mediaUrl, isEmpty);
    });

    test('subject slug is tried when the subject id is not accepted',
        () async {
      await login(pw);
      pw.on(
        'GET',
        '/v1/batches/$batchId/subject/$subjectSlug'
            '/schedule/$scheduleId/schedule-details',
        (Seen request) => ok(<String, dynamic>{
          'urlType': 'youtube',
          'url': 'https://youtu.be/dQw4w9WgXcQ',
        }),
      );

      final PwLecture lecture = await PwAccount.resolve(watchUrl);

      expect(lecture.kind, PwMediaKind.external);
      expect(lecture.mediaUrl, 'https://youtu.be/dQw4w9WgXcQ');
      expect(pw.calls(detailsPath), hasLength(1));
    });

    test('batch slug is used when the link has no batch id', () async {
      await login(pw);
      pw.on(
        'GET',
        videoUrlPath,
        (Seen request) => ok(<String, dynamic>{
          'url': '${pw.base}/cdn/slug/video.mp4',
          'signedUrl': '?Policy=p9',
        }),
      );

      final PwLecture lecture = await PwAccount.resolve(
        'https://www.pw.live/watch/?batchSlug=$batchSlug'
        '&scheduleId=$scheduleId',
      );

      expect(lecture.kind, PwMediaKind.stream);
      expect(lecture.mediaUrl, '${pw.base}/cdn/slug/video.mp4?Policy=p9');
      expect(pw.calls(videoUrlPath).single.query['parentId'], batchSlug);
    });

    test('a lecture outside the account shows PW\'s reason and what was tried',
        () async {
      await login(pw);
      pw.on(
        'GET',
        videoUrlPath,
        (Seen request) => apiError(403, 'Batch not purchased'),
      );

      final PwException error =
          await failure(() => PwAccount.resolve(watchUrl));

      expect(error.message, 'Batch not purchased');
      expect(error.needsLogin, isFalse);
      expect(error.detail, contains('details 404'));
      expect(error.detail, contains('type penpencilvdo'));
      expect(error.detail, contains('video-url 403'));
      expect(error.detail, isNot(contains('eyJ')));
      expect(PwAccount.loggedIn, isTrue);
    });

    test('a manifest the CDN refuses is reported with its status', () async {
      await login(pw);
      pw.on(
        'GET',
        videoUrlPath,
        (Seen request) => ok(<String, dynamic>{
          'url': '${pw.base}/cdn/denied/master.mpd',
        }),
      );
      pw.on('GET', '/cdn/denied/master.mpd', (Seen request) {
        return const Reply(403, 'AccessDenied');
      });

      final PwException error =
          await failure(() => PwAccount.resolve(watchUrl));

      expect(error.status, 403);
      expect(error.message, contains('HTTP 403'));
      expect(error.detail, contains('manifest 403'));
      expect(error.detail, contains('media 127.0.0.1'));
      expect(error.detail, isNot(contains('Policy')));
    });

    test('expired token is refreshed once and the lecture still opens',
        () async {
      await login(pw);
      final String fresh = jwt('Akash', 'Yadav', salt: 'b');
      pw.on('GET', detailsPath, (Seen request) {
        if (request.header('authorization') != 'Bearer $fresh') {
          return unauthorized;
        }
        return ok(<String, dynamic>{
          'urlType': 'youtube',
          'url': 'https://youtu.be/dQw4w9WgXcQ',
        });
      });
      pw.on(
        'POST',
        refreshPath,
        (Seen request) => ok(<String, dynamic>{
          'access_token': fresh,
          'refresh_token': 'refresh-2',
        }),
      );

      final PwLecture lecture = await PwAccount.resolve(watchUrl);

      expect(lecture.kind, PwMediaKind.external);
      final PwSession session = PwAccount.session.value!;
      expect(session.accessToken, fresh);
      expect(session.refreshToken, 'refresh-2');
      expect(session.displayName, 'Akash Yadav');
      final Seen refresh = pw.calls(refreshPath).single;
      expect(refresh.json['refresh_token'], 'refresh-1');
      expect(refresh.json['client_id'], 'system-admin');
      expect(pw.calls(detailsPath), hasLength(2));

      // The refreshed login is what gets saved.
      PwAccount.session.value = null;
      await PwAccount.load();
      expect(PwAccount.session.value!.accessToken, fresh);
    });

    test('a dead login is cleared and the user is asked to log in again',
        () async {
      await login(pw);
      pw.on('GET', detailsPath, (Seen request) => unauthorized);
      pw.on('POST', refreshPath, (Seen request) => unauthorized);
      pw.on('GET', selfPath, (Seen request) => unauthorized);

      final PwException error =
          await failure(() => PwAccount.resolve(watchUrl));

      expect(error.needsLogin, isTrue);
      expect(error.status, 401);
      expect(PwAccount.loggedIn, isFalse);
      await PwAccount.load();
      expect(PwAccount.loggedIn, isFalse);
    });

    test('401 for one lecture does not log a working account out', () async {
      await login(pw);
      pw.on('GET', detailsPath, (Seen request) => unauthorized);
      pw.on('GET', videoUrlPath, (Seen request) => unauthorized);
      pw.on('POST', refreshPath, (Seen request) => unauthorized);
      pw.on(
        'GET',
        selfPath,
        (Seen request) => ok(<String, dynamic>{'firstName': 'Akash'}),
      );

      final PwException error =
          await failure(() => PwAccount.resolve(watchUrl));

      expect(error.needsLogin, isFalse);
      expect(error.message, 'Unauthorized');
      expect(PwAccount.loggedIn, isTrue);
    });
  });

  group('stream links', () {
    test('a pasted encrypted manifest is reported as DRM', () async {
      pw.on('GET', '/cdn/abc/master.mpd', (Seen request) {
        return const Reply(200, drmMpd);
      });
      final String link = '${pw.base}/cdn/abc/master.mpd?Policy=p1';

      final PwLecture lecture = await PwAccount.resolve(link);

      expect(lecture.kind, PwMediaKind.drm);
      expect(lecture.mediaUrl, isEmpty);
      expect(lecture.pageUrl, link);
    });

    test('a video file link needs no account and no request', () async {
      final String link = '${pw.base}/cdn/files/lecture.mp4';
      final PwLecture lecture = await PwAccount.resolve(link);
      expect(lecture.kind, PwMediaKind.stream);
      expect(lecture.mediaUrl, link);
      expect(pw.seen, isEmpty);
    });
  });
}
