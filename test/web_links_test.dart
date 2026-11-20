// Which links the PW tab's WebView may load, and which belong to other apps.

import 'package:flutter_test/flutter_test.dart';
import 'package:videograb/services/web_links.dart';

void main() {
  // Shape of the link PW's login page fires when the mobile number box is
  // tapped (nonce and key replaced by placeholders).
  const String truecaller = 'truecallersdk://truesdk/web_verify?type=btmsheet'
      '&requestNonce=0123456789abcdef&partnerKey=placeholder'
      '&partnerName=PW%20PROD&lang=en&ctaPrefix=continuewith'
      '&ctaColor=%235A4BDA&ctaTextColor=%23FFFFFF&btnShape=rect'
      '&skipOption=useanothernum';

  test('the Truecaller login link is not loaded as a page', () {
    expect(WebLinks.schemeOf(truecaller), 'truecallersdk');
    expect(WebLinks.opensInWebView(truecaller), isFalse);
    expect(WebLinks.isTruecaller(truecaller), isTrue);
  });

  test('scheme case and leading spaces do not matter', () {
    expect(WebLinks.opensInWebView('TruecallerSDK://truesdk/web_verify'),
        isFalse);
    expect(WebLinks.isTruecaller('  TRUECALLERSDK://truesdk/web_verify'),
        isTrue);
    expect(WebLinks.opensInWebView('HTTPS://WWW.PW.LIVE/'), isTrue);
    expect(WebLinks.opensInWebView('  https://www.pw.live/'), isTrue);
  });

  test('links of other apps are stopped', () {
    const List<String> appLinks = <String>[
      'intent://scan/#Intent;scheme=zxing;package=com.example.app;end',
      'upi://pay?pa=someone@bank&am=1',
      'tel:+911234567890',
      'mailto:someone@example.com',
      'sms:12345',
      'whatsapp://send?text=hello',
      'market://details?id=com.example.app',
      'pw://open/lecture',
    ];
    for (final String link in appLinks) {
      expect(WebLinks.opensInWebView(link), isFalse, reason: link);
      expect(WebLinks.isTruecaller(link), isFalse, reason: link);
    }
  });

  test('web pages load normally', () {
    const List<String> pages = <String>[
      'https://www.pw.live/study-v2/batches',
      'https://www.pw.live/watch/?scheduleId=abc&type=penpencilvdo',
      'http://example.com/a?next=truecallersdk://x',
      'about:blank',
      'data:text/html,hello',
      'blob:https://www.pw.live/0a1b2c3d',
    ];
    for (final String page in pages) {
      expect(WebLinks.opensInWebView(page), isTrue, reason: page);
      expect(WebLinks.isTruecaller(page), isFalse, reason: page);
    }
  });

  test('text without a scheme is left to the WebView', () {
    expect(WebLinks.schemeOf('/watch/?x=1'), isEmpty);
    expect(WebLinks.schemeOf(''), isEmpty);
    expect(WebLinks.opensInWebView('/watch/?x=1'), isTrue);
    expect(WebLinks.opensInWebView(''), isTrue);
  });
}
