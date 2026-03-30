import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../shared/game_pack/views/board_view.dart';
import '../shared/app_theme.dart';
import 'flame/board_world_game.dart';
import 'flame/secret_hitler/secret_hitler_board_renderer.dart';

// ---------------------------------------------------------------------------
// Phase Korean labels
// ---------------------------------------------------------------------------

const _phaseLabels = {
  'ROLE_REVEAL': '역할 확인',
  'CHANCELLOR_NOMINATION': '수상 지명',
  'VOTING': '투표 진행',
  'LEGISLATIVE_PRESIDENT': '대통령 입법',
  'LEGISLATIVE_CHANCELLOR': '수상 입법',
  'VETO_RESPONSE': '거부권 응답',
  'EXECUTIVE_ACTION': '행정 권한',
};

/// Secret Hitler board widget rendered on the iPad (GameBoard) during play.
///
/// Uses [BoardWorldGame] + [SecretHitlerBoardRenderer] pattern matching
/// the Stockpile board implementation.
class SecretHitlerBoardWidget extends StatefulWidget {
  final BoardView boardView;
  final Map<String, String> playerNames;

  /// Optional server status widget passed from the platform.
  final Widget? serverStatusWidget;

  /// True while a force-end vote is in progress.
  final bool voteInProgress;

  /// True when the server-status overlay is visible.
  final bool showServerStatus;

  /// Called when the host taps the server-status toggle.
  final VoidCallback? onToggleServerStatus;

  /// Called when the host taps the force-end button.
  final VoidCallback? onForceEndVote;

  const SecretHitlerBoardWidget({
    super.key,
    required this.boardView,
    required this.playerNames,
    this.serverStatusWidget,
    this.voteInProgress = false,
    this.showServerStatus = false,
    this.onToggleServerStatus,
    this.onForceEndVote,
  });

  @override
  State<SecretHitlerBoardWidget> createState() =>
      _SecretHitlerBoardWidgetState();
}

class _SecretHitlerBoardWidgetState extends State<SecretHitlerBoardWidget>
    with SingleTickerProviderStateMixin {
  // Flame
  late final BoardWorldGame _boardGame;

  // Header height measurement
  final _headerKey = GlobalKey();
  double _headerHeight = 48;

  // Toast state
  String? _toastMessage;
  bool _toastVisible = false;
  Timer? _toastTimer;
  late AnimationController _toastAnim;
  late Animation<double> _toastOpacity;

  // Track last seen log entry
  String? _lastLogDescription;

  @override
  void initState() {
    super.initState();
    _boardGame = BoardWorldGame();
    _boardGame.updateRenderer(
      SecretHitlerBoardRenderer(playerNames: widget.playerNames),
    );
    _boardGame.updateBoardView(widget.boardView);

    WidgetsBinding.instance
        .addPostFrameCallback((_) => _updateHeaderHeight());

    _toastAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _toastOpacity =
        CurvedAnimation(parent: _toastAnim, curve: Curves.easeOut);

    if (widget.boardView.recentLog.isNotEmpty) {
      _lastLogDescription = widget.boardView.recentLog.last.description;
    }
  }

  @override
  void didUpdateWidget(SecretHitlerBoardWidget old) {
    super.didUpdateWidget(old);

    if (widget.boardView != old.boardView) {
      _boardGame.updateBoardView(widget.boardView);
    }

    final log = widget.boardView.recentLog;
    if (log.isNotEmpty) {
      final latest = log.last.description;
      if (latest != _lastLogDescription) {
        _lastLogDescription = latest;
        _showToast(latest);
      }
    }
  }

  void _updateHeaderHeight() {
    final ctx = _headerKey.currentContext;
    if (ctx == null) return;
    final h = ctx.size?.height ?? _headerHeight;
    if (h != _headerHeight) setState(() => _headerHeight = h);
  }

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() {
      _toastMessage = message;
      _toastVisible = true;
    });
    _toastAnim.forward(from: 0);
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      _toastAnim.reverse().then((_) {
        if (mounted) setState(() => _toastVisible = false);
      });
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _toastAnim.dispose();
    _boardGame.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _data => widget.boardView.data;
  String get _phase => _data['phase'] as String? ?? '';

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Flame board — fills entire area
        Container(
          color: const Color(0xFF1A1A2E),
          child: GameWidget(game: _boardGame),
        ),

        // Phase header
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Column(
            key: _headerKey,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPhaseHeader(context),
              if (widget.serverStatusWidget != null)
                widget.serverStatusWidget!,
            ],
          ),
        ),

        // Action toast banner
        if (_toastVisible && _toastMessage != null)
          Positioned(
            top: _headerHeight + 8,
            left: 12,
            right: 12,
            child: FadeTransition(
              opacity: _toastOpacity,
              child: _buildToast(_toastMessage!),
            ),
          ),
      ],
    );
  }

  Widget _buildPhaseHeader(BuildContext context) {
    final phaseLabel = _phaseLabels[_phase] ?? _phase;
    return Container(
      color: const Color(0xFF1A1A2E).withValues(alpha: 0.92),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          // Logo
          Image.asset('assets/images/logo.png', height: 28),
          const SizedBox(width: 12),
          const VerticalDivider(width: 1, indent: 4, endIndent: 4),
          const SizedBox(width: 12),
          // Phase chip
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFD54F).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFFFD54F).withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              phaseLabel,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Color(0xFFFFD54F),
              ),
            ),
          ),
          const Spacer(),
          // Server status toggle
          if (widget.onToggleServerStatus != null)
            IconButton(
              icon: Icon(
                Icons.people_outline,
                size: 20,
                color: widget.showServerStatus
                    ? AppTheme.primary
                    : const Color(0xFFBDBDBD),
              ),
              tooltip: '서버 상태',
              onPressed: widget.onToggleServerStatus,
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          const SizedBox(width: 4),
          // Force-end button
          if (widget.onForceEndVote != null)
            widget.voteInProgress
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    child: const Text(
                      '투표 중...',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.onSecondaryContainer,
                      ),
                    ),
                  )
                : TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      minimumSize: const Size(72, 44),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.stop_circle_outlined,
                        color: AppTheme.error, size: 16),
                    label: const Text(
                      '강제종료',
                      style: TextStyle(
                          color: AppTheme.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                    ),
                    onPressed: widget.onForceEndVote,
                  ),
        ],
      ),
    );
  }

  Widget _buildToast(String message) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFFFD54F).withValues(alpha: 0.2),
          ),
          boxShadow: const [
            BoxShadow(
                color: Color(0x44000000),
                blurRadius: 12,
                offset: Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline,
                size: 16, color: Color(0xFFFFD54F)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFFF5F5F5),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
