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

// Company identity colors — muted for dark backgrounds while remaining
// visually distinct. These are game identifiers; do not merge or remove.
const _companyColors = {
  'aauto': Color(0xFF6B9FD4), // steel blue
  'epic': Color(0xFF6BBF6B), // muted green
  'fed': Color(0xFFB5845A), // warm brown
  'lehm': Color(0xFFAB82C5), // muted purple
  'sip': Color(0xFFE8A857), // amber orange
  'tot': Color(0xFFE87D9A), // muted pink
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
  Map<String, int> get _stockPrices =>
      (_data['stockPrices'] as Map?)?.cast<String, int>() ?? {};
  List<Map<String, dynamic>> get _stockpiles =>
      ((_data['stockpiles'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  Map<String, dynamic> get _publicForecast =>
      (_data['publicForecast'] as Map?)?.cast<String, dynamic>() ?? {};
  Map<String, int> get _cash =>
      (_data['cash'] as Map?)?.cast<String, int>() ?? {};

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPhaseHeader(context),
            if (widget.serverStatusWidget != null) widget.serverStatusWidget!,
            const Divider(height: 1),
            Expanded(
              child: Stack(
                children: [
                  // Flame board — fills the play area
                  GameWidget(game: _boardGame),
                  // Public forecast banner — top overlay
                  if (_publicForecast.isNotEmpty)
                    Positioned(
                      top: 8,
                      left: 8,
                      right: 8,
                      child: _buildPublicForecast(context),
                    ),
                  // Player cash strip — bottom overlay
                  if (_cash.isNotEmpty)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      right: 8,
                      child: _buildCashRow(context),
                    ),
                ],
              ),
            ),
          ],
        ),
        // Action toast banner
        if (_toastVisible && _toastMessage != null)
          Positioned(
            top: 12,
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
      color: Theme.of(context).colorScheme.primaryContainer,
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
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(width: 12),
          // Phase chip
          Chip(
            label: Text(
              phaseLabel,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 12),
            ),
            backgroundColor:
                Theme.of(context).colorScheme.secondaryContainer,
            padding: EdgeInsets.zero,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
          Text(
            '덱 ${widget.boardView.deckRemaining}장',
            style: Theme.of(context).textTheme.bodySmall,
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
                      minimumSize: Size.zero,
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

    return Card(
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.visibility, size: 18),
            const SizedBox(width: 8),
            const Text('공개 예측: ',
                style: TextStyle(fontWeight: FontWeight.bold)),
            if (imgPath != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.asset(imgPath,
                    width: 28, height: 28, fit: BoxFit.cover),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              '$shortName ',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: 16),
            ),
            Text(
              changeStr,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: changeColor,
                  fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Player cash row
  // ---------------------------------------------------------------------------

  Widget _buildCashRow(BuildContext context) {
    if (_cash.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('보유 현금',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppTheme.onSurface)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: _cash.entries.map((e) {
            final name = widget.playerNames[e.key] ?? e.key;
            return Chip(
              avatar: const Icon(Icons.attach_money, size: 16),
              label: Text(
                '$name: \$${_formatCash(e.value)}',
                style: const TextStyle(fontSize: 12),
              ),
            );
          }).toList(),
        ),
      ],
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
                  fontSize: 13,
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

  /// Formats large integers as K / M shorthand (e.g. 18000 → "18K").
  String _formatCash(int amount) {
    if (amount >= 1000) return '${(amount / 1000).toStringAsFixed(0)}K';
    return '$amount';
  }

}
