import 'package:flutter/foundation.dart';

/// A link handed over from another tab (PW browser -> Download tab).
class PendingLink {
  const PendingLink({
    required this.url,
    this.title = '',
    this.headers = const <String, String>{},
  });

  final String url;
  final String title;
  final Map<String, String> headers;
}

/// Tiny hand-off channel between screens.
class AppLinks {
  /// A link that should be analysed on the Download tab.
  static final ValueNotifier<PendingLink?> pending =
      ValueNotifier<PendingLink?>(null);

  /// A pw.live page that should be opened in the PW tab (official player or
  /// the website login).
  static final ValueNotifier<String?> study = ValueNotifier<String?>(null);

  static void openInDownloadTab(PendingLink link) {
    pending.value = link;
  }

  static PendingLink? take() {
    final PendingLink? value = pending.value;
    pending.value = null;
    return value;
  }

  static void openInStudyTab(String url) {
    study.value = url;
  }

  static String? takeStudy() {
    final String? value = study.value;
    study.value = null;
    return value;
  }
}
