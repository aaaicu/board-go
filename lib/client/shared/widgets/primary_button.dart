import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Solid CTA button — the primary call-to-action component.
///
/// Spec:
///   - Background: AppTheme.primary solid (#FF7C38 orange)
///   - Text: on-primary (#ffffff), label-lg (16sp, weight 600)
///   - Corner radius: full (9999dp)
///   - Height: 56dp
///   - Press state: opacity 85%, scale 97%, 80ms ease-out
///   - Disabled state: surfaceContainerHigh bg, onSurfaceMuted text
class PrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;

  /// Optional icon to show before the label.
  final IconData? icon;

  final bool isLoading;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _pressed = false;

  bool get _isDisabled => widget.onPressed == null && !widget.isLoading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _isDisabled
          ? null
          : (_) => setState(() => _pressed = true),
      onTapUp: _isDisabled
          ? null
          : (_) {
              setState(() => _pressed = false);
              if (!widget.isLoading) widget.onPressed?.call();
            },
      onTapCancel: _isDisabled
          ? null
          : () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _pressed ? 0.85 : 1.0,
          duration: const Duration(milliseconds: 80),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9999),
              color: _isDisabled
                  ? AppTheme.surfaceContainerHigh
                  : AppTheme.primary,
            ),
            child: Center(
              child: widget.isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppTheme.onPrimary,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(
                            widget.icon,
                            size: 20,
                            color: _isDisabled
                                ? AppTheme.onSurfaceMuted
                                : AppTheme.onPrimary,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          widget.label,
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _isDisabled
                                ? AppTheme.onSurfaceMuted
                                : AppTheme.onPrimary,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
