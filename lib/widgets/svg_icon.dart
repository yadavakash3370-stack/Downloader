import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';

/// Renders a bundled SVG asset and tints it with [color].
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.name, {
    super.key,
    this.size = 20,
    this.color = AppColors.text,
  });

  final String name;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/icons/$name.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}

/// Icon inside a soft rounded square - used for headers and list tiles.
class IconBadge extends StatelessWidget {
  const IconBadge(
    this.name, {
    super.key,
    this.size = 38,
    this.iconSize = 18,
    this.background,
    this.color = AppColors.text,
    this.gradient = false,
    this.radius = 11,
  });

  final String name;
  final double size;
  final double iconSize;
  final Color? background;
  final Color color;
  final bool gradient;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: gradient ? AppColors.gradient : null,
        color: gradient ? null : (background ?? AppColors.surfaceAlt),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: gradient ? Colors.transparent : AppColors.stroke,
        ),
      ),
      alignment: Alignment.center,
      child: AppIcon(
        name,
        size: iconSize,
        color: gradient ? Colors.white : color,
      ),
    );
  }
}

/// Primary action button.
class GradientButton extends StatelessWidget {
  const GradientButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.expanded = true,
    this.height = 48,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? icon;
  final bool expanded;
  final double height;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final bool disabled = onPressed == null || busy;
    return SizedBox(
      height: height,
      width: expanded ? double.infinity : null,
      child: Material(
        color: disabled ? AppColors.surfaceAlt : AppColors.primary,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: disabled ? null : onPressed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: disabled ? AppColors.stroke : Colors.transparent,
              ),
            ),
            alignment: Alignment.center,
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (icon != null) ...<Widget>[
                        AppIcon(
                          icon!,
                          size: 16,
                          color: disabled ? AppColors.muted : Colors.white,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: disabled ? AppColors.muted : Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Secondary outlined button.
class AppOutlineButton extends StatelessWidget {
  const AppOutlineButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.height = 48,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? icon;
  final double height;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Material(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: busy ? null : onPressed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.stroke),
            ),
            alignment: Alignment.center,
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (icon != null) ...<Widget>[
                        AppIcon(icon!, size: 15, color: AppColors.secondary),
                        const SizedBox(width: 7),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
