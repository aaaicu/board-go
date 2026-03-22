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
/// stockpile contents + bids, public forecast, player cash, and the recent
/// action log.
class StockpileBoardWidget extends StatelessWidget {
  final BoardView boardView;

  /// Maps playerId → display nickname for human-readable labels.
  final Map<String, String> playerNames;

  /// Optional server status widget passed from the platform.
  /// Shown at the top of the board when non-null.
  final Widget? serverStatusWidget;

  const StockpileBoardWidget({
    super.key,
    required this.boardView,
    this.playerNames = const {},
    this.serverStatusWidget,
  });

  // Typed data helpers — safe casts from the dynamic data map.
  Map<String, dynamic> get _data => boardView.data;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (serverStatusWidget != null) serverStatusWidget!,
        _buildPhaseHeader(context),
        const Divider(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
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
              const VerticalDivider(width: 1),
              SizedBox(width: 220, child: _buildLogPanel()),
            ],
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Text(
            '라운드 $_round / $_totalRounds',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(width: 24),
          Chip(
            label: Text(
              phaseLabel,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor:
                Theme.of(context).colorScheme.secondaryContainer,
          ),
          const Spacer(),
          Text(
            '덱: ${boardView.deckRemaining}장',
            style: Theme.of(context).textTheme.bodyMedium,
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
                color: color.withValues(alpha: 0.12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: BorderSide(color: color.withValues(alpha: 0.5)),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
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
                      const SizedBox(height: 4),
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
        bidderId != null ? (playerNames[bidderId] ?? bidderId) : null;

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
              ...faceUpCards.map(
                (c) => Chip(
                  label: Text(_cardName(c),
                      style: const TextStyle(fontSize: 11)),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
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
            final name = playerNames[e.key] ?? e.key;
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
  // Recent log panel
  // ---------------------------------------------------------------------------

  Widget _buildLogPanel() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('최근 액션',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppTheme.onSurface)),
          ),
          Expanded(
            child: ListView(
              reverse: true,
              children: boardView.recentLog.reversed
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        e.description,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
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
