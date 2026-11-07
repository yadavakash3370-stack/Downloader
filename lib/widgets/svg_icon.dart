import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';

/// Renders a bundled SVG asset and tints it with [color].
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.name, {
    super.key,
    this.size = 22,
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
    this.size = 40,
    this.iconSize = 20,
    this.background,
    this.color = AppColors.text,
    this.gradient = false,
    this.radius = 14,
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
        color: gradient ? const Color(0xFF08080F) : color,
      ),
    );
  }
}

/// Primary action button with a gradient fill.
class GradientButton extends StatelessWidget {
  const GradientButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.expanded = true,
    this.height = 52,
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
    final Widget content = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        gradient: disabled
            ? const LinearGradient(
                colors: <Color>[Color(0xFF2A2A3E), Color(0xFF2A2A3E)],
              )
            : AppColors.gradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: disabled
            ? const <BoxShadow>[]
            : <BoxShadow>[
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.32),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      alignment: Alignment.center,
      child: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF08080F)),
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  AppIcon(
                    icon!,
                    size: 18,
                    color: disabled ? AppColors.muted : const Color(0xFF08080F),
                  ),
                  const SizedBox(width: 10),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: disabled ? AppColors.muted : const Color(0xFF08080F),
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
    );

    final Widget button = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: disabled ? null : onPressed,
        child: content,
      ),
    );

    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Secondary outlined button used next to the gradient one.
class AppOutlineButton extends StatelessWidget {
  const AppOutlineButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.height = 52,
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
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: busy ? null : onPressed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.stroke),
            ),
            alignment: Alignment.center,
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (icon != null) ...<Widget>[
                        AppIcon(icon!, size: 17, color: AppColors.secondary),
                        const SizedBox(width: 9),
                      ],
                      Text(
                        label,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
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
