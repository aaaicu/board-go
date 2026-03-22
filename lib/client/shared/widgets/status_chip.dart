import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Player / game-state status chip.
///
/// Spec:
///   - Corner radius: full (pill)
///   - Internal padding: 4dp vertical, 8dp horizontal
///   - Height: 28dp
///   - Text: label-md (14sp, weight 500)
enum ChipStatus {
  ready,
  waiting,
  voting,
  error,
}

class StatusChip extends StatelessWidget {
  final ChipStatus status;

  const StatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = _resolve(status);
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: fg,
          fontFamily: 'Manrope',
          height: 1.4,
        ),
      ),
    );
  }

  (String, Color, Color) _resolve(ChipStatus s) => switch (s) {
        ChipStatus.ready => (
            '준비완료',
            AppTheme.tertiaryContainer,
            AppTheme.onTertiaryContainer,
          ),
        ChipStatus.waiting => (
            '대기중',
            AppTheme.secondaryContainer,
            AppTheme.onSecondaryContainer,
          ),
        ChipStatus.voting => (
            '투표중',
            AppTheme.secondaryContainer,
            AppTheme.onSecondaryContainer,
          ),
        ChipStatus.error => (
            '위험',
            AppTheme.errorContainer,
            AppTheme.error,
          ),
      };
}

/// A single online/offline status dot — 8dp diameter.
class OnlineDot extends StatelessWidget {
  final bool isOnline;

  const OnlineDot({super.key, required this.isOnline});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isOnline ? AppTheme.onlineDot : AppTheme.offlineDot,
      ),
    );
  }
}
