/// Decides what the PW tab's WebView does with a link.
///
/// A WebView can only show web pages. Sites also fire links that belong to
/// other apps (`truecallersdk://`, `intent://`, `upi://`, `tel:` ...). Loaded
/// as a page those end in "Webpage not available - ERR_UNKNOWN_URL_SCHEME" and
/// the site is gone, so they have to be stopped before the WebView tries.
class WebLinks {
  static const Set<String> _webSchemes = <String>{
    'http',
    'https',
    'about',
    'data',
    'blob',
    'javascript',
  };

  static final RegExp _scheme = RegExp(r'^\s*([A-Za-z][A-Za-z0-9+.\-]*):');

  /// Scheme of [url] in lower case, `''` when it has none.
  static String schemeOf(String url) {
    final RegExpMatch? match = _scheme.firstMatch(url);
    return match == null ? '' : match.group(1)!.toLowerCase();
  }

  /// True when the WebView can show [url] itself.
  static bool opensInWebView(String url) {
    final String scheme = schemeOf(url);
    return scheme.isEmpty || _webSchemes.contains(scheme);
  }

  /// PW's website tries the Truecaller app for one-tap login when the mobile
  /// number box is tapped.
  static bool isTruecaller(String url) =>
      schemeOf(url).startsWith('truecaller');
}
