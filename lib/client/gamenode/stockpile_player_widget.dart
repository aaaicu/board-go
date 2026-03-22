import 'package:flutter/material.dart';

import '../../shared/game_pack/views/player_view.dart';
import '../shared/app_theme.dart';

// ---------------------------------------------------------------------------
// Company metadata (kept local — no shared constants package yet)
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
// visually distinct. Must match stockpile_board_widget.dart exactly.
const _companyColors = {
  'aauto': Color(0xFF6B9FD4), // steel blue
  'epic': Color(0xFF6BBF6B), // muted green
  'fed': Color(0xFFB5845A), // warm brown
  'lehm': Color(0xFFAB82C5), // muted purple
  'sip': Color(0xFFE8A857), // amber orange
  'tot': Color(0xFFE87D9A), // muted pink
};

const _kDividendSentinel = -99;

// ---------------------------------------------------------------------------
// Card / company display helpers
// ---------------------------------------------------------------------------

String _cardName(String cardId) {
  if (cardId.startsWith('stock_')) {
    final c = cardId.substring(6);
    return '${_companyShort[c] ?? c.toUpperCase()} 주식';
  }
  if (cardId == 'fee_1000') return '수수료 \$1K';
  if (cardId == 'fee_2000') return '수수료 \$2K';
  if (cardId == 'action_boom') return 'Boom!';
  if (cardId == 'action_bust') return 'Bust!';
  return cardId;
}

String _forecastChangeStr(int change) {
  if (change == _kDividendSentinel) return '\$\$ 배당';
  return change >= 0 ? '+$change' : '$change';
}

Color _forecastChangeColor(int change) {
  if (change == _kDividendSentinel) return AppTheme.secondary;
  if (change > 0) return AppTheme.tertiary;
  if (change < 0) return AppTheme.error;
  return AppTheme.onSurfaceMuted;
}

/// Formats large cash values as e.g. "\$18K" or "\$2K".
String _formatCash(int amount) {
  if (amount >= 1000) return '\$${(amount / 1000).toStringAsFixed(0)}K';
  return '\$$amount';
}

// ---------------------------------------------------------------------------
// Allowed-action type constants
// ---------------------------------------------------------------------------

const _kPlaceFaceUp = 'PLACE_FACE_UP';
const _kPlaceFaceDown = 'PLACE_FACE_DOWN';
const _kBid = 'BID';
const _kEndPhase = 'END_PHASE';
const _kUseBoom = 'USE_BOOM';
const _kUseBust = 'USE_BUST';
const _kSellStock = 'SELL_STOCK';

// ---------------------------------------------------------------------------
// StockpilePlayerWidget
// ---------------------------------------------------------------------------

/// Stockpile-specific phone UI for a player during the game.
///
/// Detects the current game phase from [PlayerView.data]['phase'] and renders
/// the appropriate context-aware controls:
///   - supply → card placement buttons
///   - demand → bid buttons with custom amount dialog
///   - action → boom / bust action buttons
///   - selling → sell stock buttons
///   - (other) → waiting indicator
///
/// Always shows private forecast and pending fees at the bottom.
class StockpilePlayerWidget extends StatelessWidget {
  final PlayerView playerView;

  /// Called when the player performs an action.
  /// [type] is the action type string; [params] holds action parameters.
  final void Function(String type, Map<String, dynamic> params) onAction;

  const StockpilePlayerWidget({
    super.key,
    required this.playerView,
    required this.onAction,
  });

  // ---------------------------------------------------------------------------
  // Typed data accessors
  // ---------------------------------------------------------------------------

  Map<String, dynamic> get _data => playerView.data;
  String get _phase => _data['phase'] as String? ?? '';
  Set<String> get _allowedTypes =>
      playerView.allowedActions.map((a) => a.actionType).toSet();

  bool _hasAction(String type) => _allowedTypes.contains(type);

  Map<String, int> get _portfolio =>
      (_data['portfolio'] as Map?)?.cast<String, int>() ?? {};
  Map<String, int> get _splitPortfolio =>
      (_data['splitPortfolio'] as Map?)?.cast<String, int>() ?? {};
  List<String> get _actionCards =>
      List<String>.from(_data['actionCards'] as List? ?? []);
  int get _pendingFees => _data['pendingFees'] as int? ?? 0;
  Map<String, dynamic>? get _privateForecast =>
      (_data['privateForecast'] as Map?)?.cast<String, dynamic>();
  Map<String, dynamic>? get _myBid =>
      (_data['myBid'] as Map?)?.cast<String, dynamic>();
  Map<String, bool> get _supplyPlaced => {
        'faceUp': (_data['supplyPlaced'] as Map?)?['faceUp'] as bool? ?? false,
        'faceDown':
            (_data['supplyPlaced'] as Map?)?['faceDown'] as bool? ?? false,
      };

  // Cash for this player (from scores, which hold cash in Stockpile)
  int get _myCash => playerView.scores[playerView.playerId] ?? 0;

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildPhaseSection(context),
                const SizedBox(height: 12),
                _buildPrivateInfoSection(context),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Phase-specific section
  // ---------------------------------------------------------------------------

  Widget _buildPhaseSection(BuildContext context) {
    // Prefer allowedActions to determine which phase controls to show, since
    // the player might be waiting (empty actions) even if phase is 'supply'.
    if (_hasAction(_kPlaceFaceUp) || _hasAction(_kPlaceFaceDown)) {
      return _buildSupplyPhase(context);
    }
    if (_hasAction(_kBid)) {
      return _buildDemandPhase(context);
    }
    if (_hasAction(_kUseBoom) || _hasAction(_kUseBust)) {
      return _buildActionPhase(context);
    }
    if (_hasAction(_kSellStock)) {
      return _buildSellingPhase(context);
    }
    if (_hasAction(_kEndPhase) && _phase == 'action') {
      return _buildActionPhase(context);
    }
    if (_hasAction(_kEndPhase) && _phase == 'selling') {
      return _buildSellingPhase(context);
    }

    // No allowed actions — waiting for other players.
    return _buildWaiting(context);
  }

  // ---------------------------------------------------------------------------
  // Supply phase
  // ---------------------------------------------------------------------------

  Widget _buildSupplyPhase(BuildContext context) {
    final placed = _supplyPlaced;
    final hasPlacedFaceUp = placed['faceUp'] ?? false;
    final hasPlacedFaceDown = placed['faceDown'] ?? false;

    // Gather per-pile, per-placement-type actions from allowedActions.
    final faceUpActions = playerView.allowedActions
        .where((a) => a.actionType == _kPlaceFaceUp)
        .toList();
    final faceDownActions = playerView.allowedActions
        .where((a) => a.actionType == _kPlaceFaceDown)
        .toList();

    // Derive available cards from the hand.
    final hand = playerView.hand;

    return _PhaseCard(
      title: '공급 단계',
      subtitle: '카드를 더미에 놓으세요',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hand preview
          if (hand.isNotEmpty) ...[
            const Text('내 카드:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: hand
                  .map((c) => Chip(
                        label: Text(_cardName(c),
                            style: const TextStyle(fontSize: 12)),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 10),
          ],

          // Placement status indicators
          Row(
            children: [
              _StatusBadge(
                label: '앞면 놓기',
                done: hasPlacedFaceUp,
              ),
              const SizedBox(width: 8),
              _StatusBadge(
                label: '뒷면 놓기',
                done: hasPlacedFaceDown,
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Face-up placement buttons
          if (!hasPlacedFaceUp && faceUpActions.isNotEmpty) ...[
            const Text('앞면으로 놓기:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 4),
            _buildSupplyButtons(
                context, faceUpActions, AppTheme.primaryContainer),
            const SizedBox(height: 8),
          ],

          // Face-down placement buttons
          if (!hasPlacedFaceDown && faceDownActions.isNotEmpty) ...[
            const Text('뒷면으로 놓기:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 4),
            _buildSupplyButtons(
                context, faceDownActions, AppTheme.surfaceContainerHigh),
          ],
        ],
      ),
    );
  }

  Widget _buildSupplyButtons(
    BuildContext context,
    List<dynamic> actions,
    Color color,
  ) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: actions.map((action) {
        return ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: AppTheme.onSurface,
            textStyle: const TextStyle(fontSize: 12),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onPressed: () => onAction(action.actionType, action.params),
          child: Text(action.label),
        );
      }).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // Demand phase
  // ---------------------------------------------------------------------------

  Widget _buildDemandPhase(BuildContext context) {
    final myBid = _myBid;

    // Distinct stockpile indices from BID actions.
    final bidsByPile = <int, List<dynamic>>{};
    for (final a in playerView.allowedActions
        .where((a) => a.actionType == _kBid)) {
      final idx = a.params['stockpileIndex'] as int? ?? 0;
      bidsByPile.putIfAbsent(idx, () => []).add(a);
    }

    return _PhaseCard(
      title: '수요 단계',
      subtitle: '입찰하세요',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Current cash
          Row(
            children: [
              const Icon(Icons.account_balance_wallet, size: 18),
              const SizedBox(width: 6),
              Text(
                '보유 현금: ${_formatCash(_myCash)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Per-pile bid buttons
          ...bidsByPile.entries.map((entry) {
            final pileIdx = entry.key;
            final pileActions = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('더미 ${pileIdx + 1}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      // Pre-built bid buttons from allowedActions
                      ...pileActions.map((a) => ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              textStyle: const TextStyle(fontSize: 12),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                            ),
                            onPressed: () =>
                                onAction(a.actionType, a.params),
                            child: Text(a.label),
                          )),
                      // Custom amount button
                      OutlinedButton.icon(
                        icon: const Icon(Icons.edit, size: 14),
                        label: const Text('직접 입력',
                            style: TextStyle(fontSize: 12)),
                        onPressed: () => _showBidDialog(
                            context, pileIdx),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),

          // Current bid summary
          if (myBid != null) ...[
            const Divider(),
            Row(
              children: [
                const Icon(Icons.gavel, size: 16, color: AppTheme.secondary),
                const SizedBox(width: 6),
                Text(
                  '내 입찰: 더미 ${(myBid['stockpileIndex'] as int) + 1} — '
                  '${_formatCash(myBid['amount'] as int? ?? 0)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: AppTheme.secondary),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showBidDialog(BuildContext context, int pileIndex) async {
    final controller = TextEditingController();
    final amount = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('더미 ${pileIndex + 1} 입찰'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: '입찰 금액 (최대 ${_formatCash(_myCash)})',
            prefixText: '\$',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              final val = int.tryParse(controller.text.trim());
              Navigator.of(ctx).pop(val);
            },
            child: const Text('입찰'),
          ),
        ],
      ),
    );
    if (amount != null && amount >= 0 && amount <= _myCash) {
      onAction(_kBid, {'stockpileIndex': pileIndex, 'amount': amount});
    }
  }

  // ---------------------------------------------------------------------------
  // Action phase
  // ---------------------------------------------------------------------------

  Widget _buildActionPhase(BuildContext context) {
    final hasBoom = _actionCards.contains('action_boom');
    final hasBust = _actionCards.contains('action_bust');
    final boomActions = playerView.allowedActions
        .where((a) => a.actionType == _kUseBoom)
        .toList();
    final bustActions = playerView.allowedActions
        .where((a) => a.actionType == _kUseBust)
        .toList();
    final canEndPhase = _hasAction(_kEndPhase);

    return _PhaseCard(
      title: '액션 단계',
      subtitle: '액션 카드를 사용하거나 완료하세요',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Held action cards summary
          if (hasBoom || hasBust) ...[
            const Text('내 액션 카드:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                if (hasBoom)
                  const Chip(
                    label: Text('Boom!',
                        style: TextStyle(color: AppTheme.onTertiaryContainer)),
                    backgroundColor: AppTheme.tertiaryContainer,
                  ),
                if (hasBust)
                  const Chip(
                    label: Text('Bust!',
                        style: TextStyle(color: AppTheme.error)),
                    backgroundColor: AppTheme.errorContainer,
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],

          // Boom actions
          if (boomActions.isNotEmpty) ...[
            const Text('Boom! 사용 (주가 상승):',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppTheme.tertiary)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: boomActions
                  .map((a) => ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.tertiaryContainer,
                          foregroundColor: AppTheme.onTertiaryContainer,
                          textStyle: const TextStyle(fontSize: 12),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                        ),
                        onPressed: () =>
                            onAction(a.actionType, a.params),
                        child: Text(
                            _companyShort[a.params['company']] ??
                                a.params['company'] as String? ??
                                ''),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
          ],

          // Bust actions
          if (bustActions.isNotEmpty) ...[
            const Text('Bust! 사용 (주가 하락):',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppTheme.error)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: bustActions
                  .map((a) => ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.errorContainer,
                          foregroundColor: AppTheme.error,
                          textStyle: const TextStyle(fontSize: 12),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                        ),
                        onPressed: () =>
                            onAction(a.actionType, a.params),
                        child: Text(
                            _companyShort[a.params['company']] ??
                                a.params['company'] as String? ??
                                ''),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
          ],

          // End phase
          if (canEndPhase)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.secondaryContainer,
                foregroundColor: AppTheme.onSecondaryContainer,
              ),
              icon: const Icon(Icons.done, size: 18),
              label: const Text('액션 완료'),
              onPressed: () => onAction(_kEndPhase, {}),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Selling phase
  // ---------------------------------------------------------------------------

  Widget _buildSellingPhase(BuildContext context) {
    // Prices are not directly in PlayerView — the server owns price computation.
    // Display share counts; the server will calculate proceeds when SELL_STOCK arrives.
    final normalHoldings = _portfolio.entries
        .where((e) => e.value > 0)
        .toList();
    final splitHoldings = _splitPortfolio.entries
        .where((e) => e.value > 0)
        .toList();
    final canEndPhase = _hasAction(_kEndPhase);

    return _PhaseCard(
      title: '매매 단계',
      subtitle: '주식을 매도하세요',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Normal holdings
          if (normalHoldings.isNotEmpty) ...[
            const Text('내 포트폴리오 (일반):',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            ...normalHoldings.map((e) {
              final company = e.key;
              final count = e.value;
              final color = _companyColors[company] ?? Colors.grey;
              final short =
                  _companyShort[company] ?? company.toUpperCase();
              final canSell = playerView.allowedActions.any((a) =>
                  a.actionType == _kSellStock &&
                  a.params['company'] == company &&
                  a.params['type'] == 'normal');
              return _HoldingRow(
                label: '$short (일반) × $count주',
                color: color,
                canSell: canSell,
                onSell: canSell
                    ? () => onAction(_kSellStock,
                        {'company': company, 'type': 'normal'})
                    : null,
              );
            }),
            const SizedBox(height: 8),
          ],

          // Split holdings
          if (splitHoldings.isNotEmpty) ...[
            const Text('내 포트폴리오 (분할주):',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            ...splitHoldings.map((e) {
              final company = e.key;
              final count = e.value;
              final color = _companyColors[company] ?? Colors.grey;
              final short =
                  _companyShort[company] ?? company.toUpperCase();
              final canSell = playerView.allowedActions.any((a) =>
                  a.actionType == _kSellStock &&
                  a.params['company'] == company &&
                  a.params['type'] == 'split');
              return _HoldingRow(
                label: '$short (분할) × $count주',
                color: color,
                isSplit: true,
                canSell: canSell,
                onSell: canSell
                    ? () => onAction(_kSellStock,
                        {'company': company, 'type': 'split'})
                    : null,
              );
            }),
            const SizedBox(height: 8),
          ],

          if (normalHoldings.isEmpty && splitHoldings.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '보유 주식 없음',
                style: TextStyle(color: AppTheme.onSurfaceMuted),
              ),
            ),

          // End phase
          if (canEndPhase)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.secondaryContainer,
                foregroundColor: AppTheme.onSecondaryContainer,
              ),
              icon: const Icon(Icons.done, size: 18),
              label: const Text('매매 완료'),
              onPressed: () => onAction(_kEndPhase, {}),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Waiting indicator
  // ---------------------------------------------------------------------------

  Widget _buildWaiting(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            const Text(
              '다른 플레이어를 기다리는 중...',
              style: TextStyle(color: AppTheme.onSurfaceMuted),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Private info section (always visible)
  // ---------------------------------------------------------------------------

  Widget _buildPrivateInfoSection(BuildContext context) {
    final forecast = _privateForecast;
    final hasForecast = forecast != null && forecast.isNotEmpty;
    final hasFees = _pendingFees > 0;

    if (!hasForecast && !hasFees) return const SizedBox.shrink();

    return Card(
      color: AppTheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
            color: AppTheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.lock, size: 14, color: AppTheme.onSurfaceMuted),
                SizedBox(width: 4),
                Text(
                  '비공개 정보',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.onSurfaceMuted,
                  ),
                ),
              ],
            ),
            if (hasForecast) ...[
              const SizedBox(height: 6),
              _buildForecastRow(_privateForecast!),
            ],
            if (hasFees) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.warning_amber,
                      size: 14, color: AppTheme.secondary),
                  const SizedBox(width: 4),
                  Text(
                    '미납 수수료: ${_formatCash(_pendingFees)}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildForecastRow(Map<String, dynamic> forecast) {
    final company = forecast['company'] as String? ?? '';
    final change = forecast['change'] as int? ?? 0;
    final color = _companyColors[company] ?? Colors.grey;
    final short = _companyShort[company] ?? company.toUpperCase();
    final changeStr = _forecastChangeStr(change);
    final changeColor = _forecastChangeColor(change);

    return Row(
      children: [
        Icon(Icons.trending_up, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          '$short ',
          style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 13, color: color),
        ),
        Text(
          '$changeStr (이번 라운드 예측)',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: changeColor),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Private helper widgets
// ---------------------------------------------------------------------------

/// Titled card wrapper used for each phase section.
class _PhaseCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _PhaseCard({
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.onSurfaceMuted)),
            ],
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

/// Status badge showing whether a placement type has been completed.
class _StatusBadge extends StatelessWidget {
  final String label;
  final bool done;

  const _StatusBadge({required this.label, required this.done});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          done ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 16,
          color: done ? AppTheme.tertiary : AppTheme.onSurfaceMuted,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: done ? AppTheme.tertiary : AppTheme.onSurfaceMuted,
          ),
        ),
      ],
    );
  }
}

/// A single portfolio row with company name and optional sell button.
class _HoldingRow extends StatelessWidget {
  final String label;
  final Color color;
  final bool isSplit;
  final bool canSell;
  final VoidCallback? onSell;

  const _HoldingRow({
    required this.label,
    required this.color,
    this.isSplit = false,
    required this.canSell,
    this.onSell,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    isSplit ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          if (canSell)
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.error,
                textStyle: const TextStyle(fontSize: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              ),
              onPressed: onSell,
              child: const Text('매도'),
            )
          else
            const SizedBox(width: 60),
        ],
      ),
    );
  }
}
