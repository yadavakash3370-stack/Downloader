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

  static void openInDownloadTab(PendingLink link) {
    pending.value = link;
  }

  static PendingLink? take() {
    final PendingLink? value = pending.value;
    pending.value = null;
    return value;
  }
}
