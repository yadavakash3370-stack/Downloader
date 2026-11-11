import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/material.dart';

/// Host based platform detection - instant, no network request needed.
class PlatformInfo {
  const PlatformInfo({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    this.short,
  });

  final String id;
  final String label;
  final String icon;
  final Color color;
  final String? short;
}

class PlatformDetector {
  static const PlatformInfo youtube = PlatformInfo(
    id: 'youtube',
    label: 'YouTube',
    icon: 'brand-youtube',
    color: Color(0xFFFF3B30),
  );
  static const PlatformInfo instagram = PlatformInfo(
    id: 'instagram',
    label: 'Instagram',
    icon: 'brand-instagram',
    color: Color(0xFFE1306C),
  );
  static const PlatformInfo facebook = PlatformInfo(
    id: 'facebook',
    label: 'Facebook',
    icon: 'brand-facebook',
    color: Color(0xFF1877F2),
  );
  static const PlatformInfo tiktok = PlatformInfo(
    id: 'tiktok',
    label: 'TikTok',
    icon: 'brand-tiktok',
    color: Color(0xFFECEFF4),
  );
  static const PlatformInfo x = PlatformInfo(
    id: 'x',
    label: 'X (Twitter)',
    icon: 'brand-x',
    color: Color(0xFFECEFF4),
  );
  static const PlatformInfo vimeo = PlatformInfo(
    id: 'vimeo',
    label: 'Vimeo',
    icon: 'brand-vimeo',
    color: Color(0xFF1AB7EA),
  );
  static const PlatformInfo dailymotion = PlatformInfo(
    id: 'dailymotion',
    label: 'Dailymotion',
    icon: 'brand-dailymotion',
    color: Color(0xFF00AAFF),
  );
  static const PlatformInfo pw = PlatformInfo(
    id: 'pw',
    label: 'Physics Wallah',
    icon: 'graduation',
    color: Color(0xFF6366F1),
  );
  static const PlatformInfo other = PlatformInfo(
    id: 'other',
    label: 'Video link',
    short: '1000+ sites',
    icon: 'globe',
    color: Color(0xFF2DD4BF),
  );

  /// Returns null when the text is not an http(s) link.
  static PlatformInfo? detect(String raw) {
    final String text = raw.trim();
    if (text.isEmpty || !text.startsWith('http')) return null;

    Uri? uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    final String host = uri.host.toLowerCase();

    switch (host) {
      case 'youtu.be':
        return youtube;
    }
    if (_has(host, 'youtube.com') || _has(host, 'youtube-nocookie.com')) {
      return youtube;
    }
    if (_has(host, 'instagram.com') || _has(host, 'instagr.am')) return instagram;
    if (_has(host, 'facebook.com') || host == 'fb.watch' || _has(host, 'fb.com')) {
      return facebook;
    }
    if (_has(host, 'tiktok.com')) return tiktok;
    if (host == 'x.com' || _has(host, 'twitter.com')) return x;
    if (_has(host, 'vimeo.com')) return vimeo;
    if (_has(host, 'dailymotion.com') || host == 'dai.ly') return dailymotion;
    if (_has(host, 'pw.live') || _has(host, 'penpencil') || _has(host, 'pwskills.com')) {
      return pw;
    }
    if (_isDirectMedia(text)) return other;
    return other;
  }

  static bool _has(String host, String domain) =>
      host == domain || host.endsWith('.$domain');

  static bool _isDirectMedia(String url) {
    final String lower = url.toLowerCase();
    return lower.contains('.m3u8') ||
        lower.contains('.mp4') ||
        lower.contains('.mpd') ||
        lower.contains('.webm');
  }

  static bool isDirectMedia(String url) => _isDirectMedia(url);
}

/// Small brand badge used next to detected links.
class PlatformBadge extends StatelessWidget {
  const PlatformBadge({required this.platform, super.key, this.label});

  final PlatformInfo platform;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SvgPicture.asset(
          'assets/icons/${platform.icon}.svg',
          width: 14,
          height: 14,
          colorFilter: ColorFilter.mode(platform.color, BlendMode.srcIn),
        ),
        const SizedBox(width: 6),
        Text(
          label ?? platform.label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFFECEFF4),
          ),
        ),
      ],
    );
  }
}
