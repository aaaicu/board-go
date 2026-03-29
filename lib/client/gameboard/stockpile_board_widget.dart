import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../shared/game_pack/views/board_view.dart';
import '../shared/app_theme.dart';
import 'flame/board_world_game.dart';
import 'flame/stockpile/stockpile_board_renderer.dart';

// ---------------------------------------------------------------------------
// Company metadata
// ---------------------------------------------------------------------------

const _companyShort = {
  'aauto': 'AAUTO',
  'epic': 'EPIC',
  'fed': 'FED',
  'lehm': 'LEHM',
  'sip': 'SIP',
  'tot': 'TOT',
};

// Company identity colors — original board-game palette.
// Must match stockpile_player_widget.dart and kCompanyColors exactly.
const _companyColors = {
  'aauto': Color(0xFFD44B3A), // red   — American Automotive
  'epic': Color(0xFFE8A83C), // amber — Epic Electric
  'fed': Color(0xFF4A7BC8), // blue  — Cosmic Computers
  'lehm': Color(0xFF9B6BBF), // purple — Leading Laboratories
  'sip': Color(0xFF7A7A7A), // grey  — Stanford Steel
  'tot': Color(0xFF4A9B6B), // green — Bottomline Bank
};

const _companyImages = {
  'aauto': 'assets/gamepacks/stockpile/image/AAUTO.png',
  'epic': 'assets/gamepacks/stockpile/image/EPIC.png',
  'fed': 'assets/gamepacks/stockpile/image/FED.png',
  'lehm': 'assets/gamepacks/stockpile/image/LEHM.png',
  'sip': 'assets/gamepacks/stockpile/image/SIP.png',
  'tot': 'assets/gamepacks/stockpile/image/TOT.png',
};

const _kDividendSentinel = -99;

// ---------------------------------------------------------------------------
// Phase Korean labels
// ---------------------------------------------------------------------------

const _phaseLabels = {
  'supply': '공급 단계',
  'demand': '수요 단계',
  'action': '액션 단계',
  'selling': '매매 단계',
  'movement': '주가 이동 단계',
  'information': '정보 단계',
};

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// Stockpile-specific board view rendered on the iPad (GameBoard) during play.
///
/// Receives the [BoardView] produced by [StockpileRules.buildBoardView] and
/// presents all public information: current phase/round, stock price grid,
/// stockpile contents + bids, public forecast, and player cash.
///
/// New player actions appear as a temporary toast banner (3 s) instead of
/// a persistent log panel.
class StockpileBoardWidget extends StatefulWidget {
  final BoardView boardView;

  /// Maps playerId → display nickname for human-readable labels.
  final Map<String, String> playerNames;

  /// Optional server status widget passed from the platform.
  /// Shown as a toggled overlay within the board.
  final Widget? serverStatusWidget;

  /// True while a force-end vote is in progress.
  final bool voteInProgress;

  /// True when the server-status overlay is visible.
  final bool showServerStatus;

  /// Called when the host taps the server-status toggle.
  final VoidCallback? onToggleServerStatus;

  /// Called when the host taps the force-end button.
  final VoidCallback? onForceEndVote;

  const StockpileBoardWidget({
    super.key,
    required this.boardView,
    this.playerNames = const {},
    this.serverStatusWidget,
    this.voteInProgress = false,
    this.showServerStatus = false,
    this.onToggleServerStatus,
    this.onForceEndVote,
  });

  @override
  State<StockpileBoardWidget> createState() => _StockpileBoardWidgetState();
}

class _StockpileBoardWidgetState extends State<StockpileBoardWidget>
    with SingleTickerProviderStateMixin {
  // Flame
  late final BoardWorldGame _boardGame;

  // Header height measurement
  final _headerKey = GlobalKey();
  double _headerHeight = 56;

  // Toast state
  String? _toastMessage;
  bool _toastVisible = false;
  Timer? _toastTimer;
  late AnimationController _toastAnim;
  late Animation<double> _toastOpacity;

  // Track last seen log entry to detect new ones
  String? _lastLogDescription;

  @override
  void initState() {
    super.initState();
    // Flame board setup
    _boardGame = BoardWorldGame();
    _boardGame.updateRenderer(
      StockpileBoardRenderer(playerNames: widget.playerNames),
    );
    // Forward the initial board state so piles/prices are visible on first render.
    _boardGame.updateBoardView(widget.boardView);

    // Measure header height after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateHeaderHeight());

    // Toast animation
    _toastAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _toastOpacity = CurvedAnimation(parent: _toastAnim, curve: Curves.easeOut);

    // Seed with existing log so first update triggers correctly
    if (widget.boardView.recentLog.isNotEmpty) {
      _lastLogDescription = widget.boardView.recentLog.last.description;
    }
  }

  @override
  void didUpdateWidget(StockpileBoardWidget old) {
    super.didUpdateWidget(old);

    // Forward new board state to Flame
    if (widget.boardView != old.boardView) {
      _boardGame.updateBoardView(widget.boardView);
    }

    // Toast
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

  // Typed data helpers — safe casts from the dynamic data map.
  Map<String, dynamic> get _data => widget.boardView.data;
  String get _phase => _data['phase'] as String? ?? '';
  int get _round => _data['round'] as int? ?? 1;
  int get _totalRounds => _data['totalRounds'] as int? ?? 1;
  Map<String, dynamic> get _publicForecast =>
      (_data['publicForecast'] as Map?)?.cast<String, dynamic>() ?? {};

  @override
  Widget build(BuildContext context) {
    // Flame's GameWidget renders via its own graphics pipeline and can appear
    // above normal Flutter Column children. To guarantee the phase header is
    // always visible, we use a full-screen Stack where GameWidget fills the
    // background and the header is the last child (highest z-order).
    return Stack(
      children: [
        // Flame board — fills entire area
        GameWidget(game: _boardGame),

        // Public forecast panel — right side, below the phase header
        if (_publicForecast.isNotEmpty)
          Positioned(
            top: _headerHeight + 8,
            right: 8,
            child: _buildPublicForecast(context),
          ),

        // Phase header — always on top, pinned to the top edge
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
              if (widget.serverStatusWidget != null) widget.serverStatusWidget!,
              const Divider(height: 1),
            ],
          ),
        ),

        // Action toast banner — below the header
        if (_toastVisible && _toastMessage != null)
          Positioned(
            top: 60,
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

  // ---------------------------------------------------------------------------
  // Phase / round header
  // ---------------------------------------------------------------------------

  Widget _buildPhaseHeader(BuildContext context) {
    final phaseLabel = _phaseLabels[_phase] ?? _phase;
    return Container(
      color: const Color(0xFFE8DFC8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          // Logo — replaces the removed AppBar title
          Image.asset('assets/images/logo.png', height: 28),
          const SizedBox(width: 12),
          const VerticalDivider(width: 1, indent: 4, endIndent: 4),
          const SizedBox(width: 12),
          // Round info
          Text(
            '라운드 $_round / $_totalRounds',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(width: 12),
          // Phase chip
          Chip(
            label: Text(
              phaseLabel,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14),
            ),
            backgroundColor:
                Theme.of(context).colorScheme.secondaryContainer,
            padding: EdgeInsets.zero,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
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
                    : AppTheme.onSurfaceMuted,
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

  // ---------------------------------------------------------------------------
  // Public forecast
  // ---------------------------------------------------------------------------

  Widget _buildPublicForecast(BuildContext context) {
    if (_publicForecast.isEmpty) return const SizedBox.shrink();

    final company = _publicForecast['company'] as String? ?? '';
    final change = _publicForecast['change'] as int? ?? 0;
    final color = _companyColors[company] ?? Colors.grey;
    final shortName = _companyShort[company] ?? company.toUpperCase();
    final changeStr = change == _kDividendSentinel
        ? '\$\$ 배당'
        : change >= 0
            ? '+$change'
            : '$change';
    final changeColor = change == _kDividendSentinel
        ? AppTheme.secondary
        : change > 0
            ? AppTheme.tertiary
            : AppTheme.error;

    final imgPath = _companyImages[company];

    return Container(
      width: 130,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5EFE0).withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.visibility, size: 13, color: Color(0xFF5A4A2A)),
              SizedBox(width: 4),
              Text(
                '공개 예측',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  color: Color(0xFF5A4A2A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (imgPath != null)
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(imgPath, fit: BoxFit.cover),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            shortName,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: changeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: changeColor.withValues(alpha: 0.5), width: 1.5),
            ),
            child: Text(
              changeStr,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: changeColor,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Toast banner
  // ---------------------------------------------------------------------------

  Widget _buildToast(String message) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.onSurface.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
                color: Color(0x33000000),
                blurRadius: 12,
                offset: Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline,
                size: 16, color: AppTheme.onPrimary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 16,
                  color: AppTheme.onPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

}
