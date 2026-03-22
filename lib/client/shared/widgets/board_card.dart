import 'package:flutter/material.dart';

import '../app_theme.dart';

/// The Hero card component from the board-go design system.
///
/// Spec:
///   - Background: [AppTheme.surfaceContainerHigh]
///   - No borders
///   - Corner radius: 24dp
///   - Internal padding: 16dp (spacing-md)
///   - Press state: scale to 98% over 80ms ease-out
///   - Selected state: 2px primary outline + primary glow
///   - Elevation shadow: 0 4px 16px rgba(0,0,0,0.3)
class BoardCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool isSelected;

  /// Override the default [AppTheme.surfaceContainerHigh] background.
  final Color? backgroundColor;

  /// Override the default 16dp internal padding.
  final EdgeInsetsGeometry? padding;

  /// Override the default 24dp corner radius.
  final double borderRadius;

  const BoardCard({
    super.key,
    required this.child,
    this.onTap,
    this.isSelected = false,
    this.backgroundColor,
    this.padding,
    this.borderRadius = 24,
  });

  @override
  State<BoardCard> createState() => _BoardCardState();
}

class _BoardCardState extends State<BoardCard>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.backgroundColor ?? AppTheme.surfaceContainerHigh;
    final padding = widget.padding ?? const EdgeInsets.all(16);
    final radius = widget.borderRadius;

    return GestureDetector(
      onTapDown: widget.onTap != null
          ? (_) => setState(() => _pressed = true)
          : null,
      onTapUp: widget.onTap != null
          ? (_) {
              setState(() => _pressed = false);
              widget.onTap?.call();
            }
          : null,
      onTapCancel: widget.onTap != null
          ? () => setState(() => _pressed = false)
          : null,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              const BoxShadow(
                color: Color(0x4D000000), // rgba(0,0,0,0.3)
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
              if (widget.isSelected) ...[
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 0,
                ),
                const BoxShadow(
                  color: AppTheme.primary,
                  blurRadius: 0,
                  spreadRadius: 2,
                ),
              ],
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Padding(padding: padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}
