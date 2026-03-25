import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/game_pack/views/board_view.dart';
import '../shared/app_theme.dart';

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

const _kCompanyOrder = ['aauto', 'epic', 'fed', 'lehm', 'sip', 'tot'];
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
// Card display name helper
// ---------------------------------------------------------------------------

String _cardName(String cardId) {
  if (cardId.startsWith('stock_')) {
    final company = cardId.substring(6);
    return '${_companyShort[company] ?? company} 주식';
  }
  if (cardId == 'fee_1000') return '수수료 \$1K';
  if (cardId == 'fee_2000') return '수수료 \$2K';
  if (cardId == 'action_boom') return 'Boom!';
  if (cardId == 'action_bust') return 'Bust!';
  return cardId;
}

// ---------------------------------------------------------------------------
// Price colour helper
// ---------------------------------------------------------------------------

Color _priceColor(int price) {
  if (price <= 3) return AppTheme.error;
  if (price >= 9) return AppTheme.tertiary;
  return AppTheme.onSurface;
}

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
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildPublicForecast(context),
                    const SizedBox(height: 12),
                    _buildStockPriceGrid(context),
                    const SizedBox(height: 12),
                    _buildStockpiles(context),
                    const SizedBox(height: 12),
                    _buildCashRow(context),
                  ],
                ),
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
  // Stock price grid
  // ---------------------------------------------------------------------------

  Widget _buildStockPriceGrid(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('주가',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppTheme.onSurface)),
        const SizedBox(height: 6),
        Row(
          children: _kCompanyOrder.map((company) {
            final price = _stockPrices[company] ?? 0;
            final color = _companyColors[company] ?? Colors.grey;
            final short = _companyShort[company] ?? company.toUpperCase();
            return Expanded(
              child: Card(
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: color.withValues(alpha: 0.5)),
                ),
                child: Column(
                  children: [
                    // Company illustration
                    if (_companyImages[company] != null)
                      Image.asset(
                        _companyImages[company]!,
                        height: 60,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      )
                    else
                      Container(
                        height: 60,
                        color: color.withValues(alpha: 0.2),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 6),
                      child: Column(
                        children: [
                          Text(
                            short,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '\$$price',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: _priceColor(price),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Stockpile cards
  // ---------------------------------------------------------------------------

  Widget _buildStockpiles(BuildContext context) {
    if (_stockpiles.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('주식 더미',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppTheme.onSurface)),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _stockpiles.asMap().entries.map((entry) {
            final idx = entry.key;
            final sp = entry.value;
            return Expanded(child: _buildSingleStockpile(context, idx, sp));
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSingleStockpile(
    BuildContext context,
    int index,
    Map<String, dynamic> sp,
  ) {
    final faceUpCards = List<String>.from(sp['faceUpCards'] as List? ?? []);
    final faceDownCount = sp['faceDownCount'] as int? ?? 0;
    final currentBid = sp['currentBid'] as int? ?? 0;
    final bidderId = sp['currentBidderId'] as String?;
    final bidderName =
        bidderId != null ? (widget.playerNames[bidderId] ?? bidderId) : null;

    return Card(
      margin: const EdgeInsets.only(right: 6),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '더미 ${index + 1}',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 4),
            // Face-up cards
            if (faceUpCards.isNotEmpty)
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: faceUpCards.map((c) => _buildCardChip(c)).toList(),
              ),
            // Face-down placeholder
            if (faceDownCount > 0)
              Chip(
                label: Text(
                  '뒷면 $faceDownCount장',
                  style: const TextStyle(fontSize: 11),
                ),
                backgroundColor: AppTheme.surfaceContainerHigh,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            if (faceUpCards.isEmpty && faceDownCount == 0)
              const Text('(비어 있음)',
                  style: TextStyle(
                      fontSize: 11, color: AppTheme.onSurfaceMuted)),
            const Divider(height: 12),
            // Bid info
            if (currentBid > 0 && bidderName != null) ...[
              Text(
                '입찰: \$${_formatCash(currentBid)}',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold),
              ),
              Text(
                '입찰자: $bidderName',
                style: const TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ] else
              const Text(
                '입찰 없음',
                style: TextStyle(fontSize: 11, color: AppTheme.onSurfaceMuted),
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

  /// Renders a single face-up card in a stockpile.
  /// Stock cards show the company illustration; other cards use a text chip.
  Widget _buildCardChip(String cardId) {
    if (cardId.startsWith('stock_')) {
      final company = cardId.substring(6);
      final color = _companyColors[company] ?? Colors.grey;
      final short = _companyShort[company] ?? company.toUpperCase();
      final imgPath = _companyImages[company];
      return Container(
        width: 44,
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(6),
          color: color.withValues(alpha: 0.08),
        ),
        child: Column(
          children: [
            if (imgPath != null)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(5)),
                child: Image.asset(imgPath,
                    height: 32, width: 44, fit: BoxFit.cover),
              )
            else
              Container(
                  height: 32,
                  width: 44,
                  color: color.withValues(alpha: 0.2)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                short,
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: color),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }
    // Fee / action cards — plain chip
    Color chipColor = AppTheme.surfaceContainerHigh;
    Color textColor = AppTheme.onSurface;
    if (cardId == 'action_boom') {
      chipColor = AppTheme.tertiaryContainer;
      textColor = AppTheme.onTertiaryContainer;
    } else if (cardId == 'action_bust') {
      chipColor = AppTheme.errorContainer;
      textColor = AppTheme.error;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _cardName(cardId),
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w600, color: textColor),
      ),
    );
  }
}
