import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../shared/game_pack/views/player_view.dart';
import '../shared/app_theme.dart';
import 'flame/hand_card_component.dart'
    show kCardWidth, kCardHeight, kCardSelectedLift;
import 'flame/stockpile_node_game.dart';

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

// Company identity colors — original board-game palette.
// Must match stockpile_board_widget.dart and kCompanyColors exactly.
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
const _kDemandPass = 'DEMAND_PASS';
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
///   - supply → 2-step card selection then pile selection
///   - demand → bid buttons with custom amount dialog
///   - action → boom / bust action buttons
///   - selling → sell stock buttons
///   - (other) → waiting indicator
///
/// Always shows private forecast and pending fees at the bottom.
class StockpilePlayerWidget extends StatefulWidget {
  final PlayerView playerView;

  /// Called when the player performs an action.
  /// [type] is the action type string; [params] holds action parameters.
  final void Function(String type, Map<String, dynamic> params) onAction;

  const StockpilePlayerWidget({
    super.key,
    required this.playerView,
    required this.onAction,
  });

  @override
  State<StockpilePlayerWidget> createState() => _StockpilePlayerWidgetState();
}

class _StockpilePlayerWidgetState extends State<StockpilePlayerWidget> {
  /// Index into [playerView.hand] selected in step 1 of the supply phase.
  /// Null means step 1 (card selection); non-null means step 2 (pile selection).
  int? _selectedCardIndex;

  // ---------------------------------------------------------------------------
  // Flame game instances
  // ---------------------------------------------------------------------------

  /// Flame game used to render the supply-phase hand card fan.
  late final StockpileNodeGame _handGame;

  // ---------------------------------------------------------------------------
  // Per-pile bid state (demand phase)
  // ---------------------------------------------------------------------------

  /// All selectable bid amounts (×1000 each).
  static const List<int> _kBidValues = [
    0, 1000, 3000, 6000, 10000, 15000, 20000, 25000,
  ];

  /// Selected bid amount per pile index.
  final Map<int, int> _pileBidAmount = {};

  /// Which pile is selected in step 1 of the demand phase.
  /// null = step 1 (pile selection); non-null = step 2 (amount selection).
  int? _selectedBidPileIdx;

  /// Minimum required bid for [pileIdx], derived from allowed actions.
  /// Returns 0 if the pile is unclaimed (no prior bid).
  int _minBidFor(int pileIdx) {
    int? min;
    for (final a in widget.playerView.allowedActions) {
      if (a.actionType != _kBid) continue;
      if ((a.params['stockpileIndex'] as int?) != pileIdx) continue;
      final v = a.params['amount'] as int? ?? 0;
      if (min == null || v < min) min = v;
    }
    return min ?? 0;
  }

  /// Selected bid amount for [pileIdx], defaulting to the first valid value.
  /// If a saved value is no longer valid (below minBid), it is discarded.
  int _bidAmountFor(int pileIdx) {
    final minBid = _minBidFor(pileIdx);
    final saved = _pileBidAmount[pileIdx];
    if (saved != null && saved >= minBid) return saved;
    return _kBidValues.firstWhere((v) => v >= minBid, orElse: () => _kBidValues.last);
  }

  // ---------------------------------------------------------------------------
  // Typed data accessors
  // ---------------------------------------------------------------------------

  Map<String, dynamic> get _data => widget.playerView.data;
  String get _phase => _data['phase'] as String? ?? '';
  Set<String> get _allowedTypes =>
      widget.playerView.allowedActions.map((a) => a.actionType).toSet();

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

  int get _demandRound => _data['demandRound'] as int? ?? 1;
  bool get _isRebidRound => _demandRound > 1;
  List<String> get _outbidPlayers =>
      List<String>.from(_data['outbidPlayers'] as List? ?? []);
  bool get _isOutbid =>
      _outbidPlayers.contains(widget.playerView.playerId);

  // Cash for this player (from scores, which hold cash in Stockpile)
  int get _myCash => widget.playerView.scores[widget.playerView.playerId] ?? 0;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    _handGame = StockpileNodeGame()
      ..onCardTap = _onFlameCardTap;

    // After the first frame, GameWidget has been laid out and onGameResize has
    // already fired (size.x > 0), so it is safe to push the initial hand state.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncHandGame();
    });
  }

  @override
  void didUpdateWidget(StockpilePlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Reset card selection when the hand changes (e.g. after placing a card).
    if (oldWidget.playerView.hand.length != widget.playerView.hand.length) {
      _selectedCardIndex = null;
    }

    // Reset pile selection when phase changes.
    if (oldWidget.playerView.data['phase'] != widget.playerView.data['phase']) {
      _selectedBidPileIdx = null;
    } else if (_selectedBidPileIdx != null) {
      // Reset if the selected pile is no longer biddable.
      final stillBiddable = widget.playerView.allowedActions.any(
        (a) => a.actionType == _kBid &&
            (a.params['stockpileIndex'] as int?) == _selectedBidPileIdx,
      );
      if (!stillBiddable) _selectedBidPileIdx = null;
    }

    // Push hand state into the Flame game.
    _syncHandGame();
  }

  @override
  void dispose() {
    _handGame.onCardTap = null;
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Flame synchronisation helpers
  // ---------------------------------------------------------------------------

  void _syncHandGame() {
    final hand = widget.playerView.hand;
    final faceUpActions = widget.playerView.allowedActions
        .where((a) => a.actionType == _kPlaceFaceUp)
        .toList();
    final faceDownActions = widget.playerView.allowedActions
        .where((a) => a.actionType == _kPlaceFaceDown)
        .toList();

    final interactiveFlags = List.generate(hand.length, (idx) {
      return faceUpActions.any((a) => (a.params['cardIndex'] as int?) == idx) ||
          faceDownActions.any((a) => (a.params['cardIndex'] as int?) == idx);
    });

    _handGame
      ..updateMode(NodeGameMode.handOnly)
      ..updateHand(hand, interactiveFlags)
      ..setSelectedCard(_selectedCardIndex);
  }

  void _onFlameCardTap(int index) {
    if (!mounted) return;
    setState(() {
      _selectedCardIndex = index;
      _handGame.setSelectedCard(index);
    });
  }

  void _onAction(String type, Map<String, dynamic> params) {
    setState(() => _selectedCardIndex = null);
    widget.onAction(type, params);
  }

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
    if (_hasAction(_kPlaceFaceUp) || _hasAction(_kPlaceFaceDown)) {
      return _buildSupplyPhase(context);
    }
    if (_hasAction(_kBid) || _hasAction(_kDemandPass)) {
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

    // Waiting: show outbid banner if applicable so the player knows why.
    if (_phase == 'demand' && _isOutbid) {
      return _buildDemandWaitingOutbid(context);
    }

    // No allowed actions — waiting for other players.
    return _buildWaiting(context);
  }

  // ---------------------------------------------------------------------------
  // Supply phase — 2-step UX
  // ---------------------------------------------------------------------------

  Widget _buildSupplyPhase(BuildContext context) {
    final placed = _supplyPlaced;
    final hasPlacedFaceUp = placed['faceUp'] ?? false;
    final hasPlacedFaceDown = placed['faceDown'] ?? false;

    final faceUpActions = widget.playerView.allowedActions
        .where((a) => a.actionType == _kPlaceFaceUp)
        .toList();
    final faceDownActions = widget.playerView.allowedActions
        .where((a) => a.actionType == _kPlaceFaceDown)
        .toList();

    final hand = widget.playerView.hand;

    final subtitle = _selectedCardIndex == null
        ? '놓을 카드를 선택하세요'
        : '어느 더미에 놓을지 선택하세요';

    return _PhaseCard(
      title: '공급 단계',
      subtitle: subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Placement status badges
          Row(
            children: [
              _StatusBadge(label: '앞면 놓기', done: hasPlacedFaceUp),
              const SizedBox(width: 8),
              _StatusBadge(label: '뒷면 놓기', done: hasPlacedFaceDown),
            ],
          ),
          const SizedBox(height: 12),

          if (_selectedCardIndex == null)
            // ── Step 1: show hand cards as tappable tiles ──────────────────
            _buildCardSelection(hand, faceUpActions, faceDownActions)
          else
            // ── Step 2: show pile-selection buttons for selected card ───────
            _buildPileSelection(
              hand,
              _selectedCardIndex!,
              faceUpActions,
              faceDownActions,
              hasPlacedFaceUp,
              hasPlacedFaceDown,
            ),
        ],
      ),
    );
  }

  /// Step 1 — Flame-rendered hand card fan; tappable if actions exist for them.
  Widget _buildCardSelection(
    List<String> hand,
    List<dynamic> faceUpActions,
    List<dynamic> faceDownActions,
  ) {
    if (hand.isEmpty) {
      return const Text(
        '카드 없음',
        style: TextStyle(color: AppTheme.onSurfaceMuted),
      );
    }

    // Height = card + lift headroom.
    final gameHeight = kCardHeight + kCardSelectedLift + 16.0;
    // Width = total card fan width, capped at screen width.
    final fanWidth = hand.length * kCardWidth + (hand.length - 1) * 10.0;

    return SizedBox(
      height: gameHeight,
      width: fanWidth.clamp(kCardWidth, double.infinity),
      child: GameWidget(game: _handGame),
    );
  }

  /// Step 2 — selected card preview + pile buttons filtered by card index.
  Widget _buildPileSelection(
    List<String> hand,
    int cardIdx,
    List<dynamic> faceUpActions,
    List<dynamic> faceDownActions,
    bool hasPlacedFaceUp,
    bool hasPlacedFaceDown,
  ) {
    final selectedCard = hand[cardIdx];

    final cardFaceUpActions = faceUpActions
        .where((a) => (a.params['cardIndex'] as int?) == cardIdx)
        .toList();
    final cardFaceDownActions = faceDownActions
        .where((a) => (a.params['cardIndex'] as int?) == cardIdx)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Selected card + cancel
        Row(
          children: [
            _buildHandCard(selectedCard, selected: true),
            const SizedBox(width: 8),
            TextButton.icon(
              icon: const Icon(Icons.close, size: 16),
              label: const Text('취소'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.onSurfaceMuted,
                textStyle: const TextStyle(fontSize: 12),
              ),
              onPressed: () => setState(() => _selectedCardIndex = null),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Face-up pile buttons
        if (!hasPlacedFaceUp && cardFaceUpActions.isNotEmpty) ...[
          const Text(
            '앞면으로 놓기:',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 6),
          _buildPileButtons(cardFaceUpActions, AppTheme.primaryContainer),
          const SizedBox(height: 10),
        ],

        // Face-down pile buttons
        if (!hasPlacedFaceDown && cardFaceDownActions.isNotEmpty) ...[
          const Text(
            '뒷면으로 놓기:',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 6),
          _buildPileButtons(
              cardFaceDownActions, AppTheme.surfaceContainerHigh),
        ],
      ],
    );
  }

  Widget _buildPileButtons(List<dynamic> actions, Color color) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: actions.map((action) {
        final pileIdx =
            (action.params['stockpileIndex'] as int? ?? 0) + 1;
        return ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: AppTheme.onSurface,
            textStyle: const TextStyle(fontSize: 13),
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          onPressed: () => _onAction(action.actionType, action.params),
          child: Text('더미 $pileIdx'),
        );
      }).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // Demand phase — 2-step UX
  // ---------------------------------------------------------------------------

  Widget _buildDemandPhase(BuildContext context) {
    if (_selectedBidPileIdx == null) {
      return _buildDemandPileSelection(context);
    }
    return _buildDemandAmountSelection(context, _selectedBidPileIdx!);
  }

  /// Step 1 — choose which pile to bid on.
  Widget _buildDemandPileSelection(BuildContext context) {
    final myBid = _myBid;
    final canPass = _hasAction(_kDemandPass);

    final biddablePiles = <int>[];
    for (final a in widget.playerView.allowedActions
        .where((a) => a.actionType == _kBid)) {
      final idx = a.params['stockpileIndex'] as int? ?? 0;
      if (!biddablePiles.contains(idx)) biddablePiles.add(idx);
    }
    biddablePiles.sort();

    final subtitle = _isRebidRound
        ? '재입찰 라운드 (${_demandRound - 1}회차) — 더 높게 입찰하거나 통과하세요'
        : '입찰할 더미를 선택하세요';

    return _PhaseCard(
      title: '수요 단계',
      subtitle: subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 재입찰 알림 배너
          if (_isOutbid) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 18, color: AppTheme.error),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '다른 플레이어에게 밀렸습니다! 재입찰하세요',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.error),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // 보유 현금
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet, size: 16, color: AppTheme.tertiary),
                const SizedBox(width: 8),
                const Text('보유 현금', style: TextStyle(fontSize: 12, color: AppTheme.onSurfaceMuted)),
                const Spacer(),
                Text(
                  _formatCash(_myCash),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.tertiary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 더미 선택 카드
          ...biddablePiles.map((pileIdx) {
            final minBid = _minBidFor(pileIdx);
            final unclaimed = minBid == 0;
            final currentBid = unclaimed ? 0 : minBid - 1;
            return GestureDetector(
              onTap: () => setState(() => _selectedBidPileIdx = pileIdx),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '더미 ${pileIdx + 1}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primary),
                      ),
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          unclaimed ? '입찰 없음' : '현재 입찰',
                          style: const TextStyle(fontSize: 11, color: AppTheme.onSurfaceMuted),
                        ),
                        if (!unclaimed)
                          Text(
                            _formatCash(currentBid),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right, size: 20, color: AppTheme.onSurfaceMuted),
                  ],
                ),
              ),
            );
          }),

          // 내 현재 입찰 표시
          if (myBid != null) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.secondaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.gavel, size: 16, color: AppTheme.secondary),
                  const SizedBox(width: 8),
                  Text(
                    '현재 입찰 — 더미 ${(myBid['stockpileIndex'] as int) + 1}',
                    style: const TextStyle(fontSize: 13, color: AppTheme.onSecondaryContainer),
                  ),
                  const Spacer(),
                  Text(
                    _formatCash(myBid['amount'] as int? ?? 0),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.secondary),
                  ),
                ],
              ),
            ),
          ],

          // 재입찰 통과 버튼 (rebid round에서만)
          if (canPass) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.onSurfaceMuted,
                side: const BorderSide(color: AppTheme.outlineVariant),
                textStyle: const TextStyle(fontSize: 13),
              ),
              icon: const Icon(Icons.skip_next, size: 18),
              label: const Text('이번 라운드 통과'),
              onPressed: () => _onAction(_kDemandPass, {}),
            ),
          ],
        ],
      ),
    );
  }

  /// Step 2 — choose bid amount for the selected pile.
  Widget _buildDemandAmountSelection(BuildContext context, int pileIdx) {
    final minBid = _minBidFor(pileIdx);
    final unclaimed = minBid == 0;
    final currentBid = unclaimed ? 0 : minBid - 1;
    final selected = _bidAmountFor(pileIdx);

    final row1 = _kBidValues.sublist(0, 4); // 0 / 1K / 3K / 6K
    final row2 = _kBidValues.sublist(4);    // 10K / 15K / 20K / 25K

    return _PhaseCard(
      title: '수요 단계',
      subtitle: '입찰 금액을 선택하세요',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 헤더: 더미 정보 + 뒤로 버튼
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '더미 ${pileIdx + 1}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primary),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                unclaimed ? '입찰 없음' : '현재 입찰: ${_formatCash(currentBid)}',
                style: const TextStyle(fontSize: 12, color: AppTheme.onSurfaceMuted),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('뒤로'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.onSurfaceMuted,
                  textStyle: const TextStyle(fontSize: 12),
                ),
                onPressed: () => setState(() => _selectedBidPileIdx = null),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 선택 금액 표시
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('선택 금액: ', style: TextStyle(fontSize: 14, color: AppTheme.onSurfaceMuted)),
              Text(
                _formatCash(selected),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 행 1: 0 / 1K / 3K / 6K
          Row(
            children: row1.map((v) {
              final enabled = v >= minBid;
              return _buildBidCell(
                label: v == 0 ? '0' : '${v ~/ 1000}K',
                selected: v == selected,
                enabled: enabled,
                onTap: enabled ? () => setState(() => _pileBidAmount[pileIdx] = v) : null,
              );
            }).toList(),
          ),
          const SizedBox(height: 6),

          // 행 2: 10K / 15K / 20K / 25K
          Row(
            children: row2.map((v) {
              final enabled = v >= minBid;
              return _buildBidCell(
                label: '${v ~/ 1000}K',
                selected: v == selected,
                enabled: enabled,
                onTap: enabled ? () => setState(() => _pileBidAmount[pileIdx] = v) : null,
              );
            }).toList(),
          ),
          const SizedBox(height: 10),

          // 입찰 확인 버튼
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryContainer,
              foregroundColor: AppTheme.primary,
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            icon: const Icon(Icons.gavel, size: 18),
            label: Text('입찰 — ${_formatCash(selected)}'),
            onPressed: () {
              _onAction('BID', {
                'stockpileIndex': pileIdx,
                'amount': selected,
              });
              setState(() => _selectedBidPileIdx = null);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBidCell({
    required String label,
    required bool selected,
    required bool enabled,
    required VoidCallback? onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: !enabled
                ? const Color(0xFFD8D0B8)
                : selected
                    ? const Color(0xFFE8A040)
                    : const Color(0xFFF0E8D0),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: enabled ? const Color(0xFFBFAF88) : const Color(0xFFD0C8B0),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: !enabled
                  ? const Color(0xFFAA9A80)
                  : selected
                      ? Colors.white
                      : const Color(0xFF3A3020),
            ),
          ),
        ),
      ),
    );
  }

  /// Shown when the player is outbid but it is not yet their rebid turn.
  Widget _buildDemandWaitingOutbid(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 18, color: AppTheme.error),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '다른 플레이어에게 밀렸습니다! 재입찰 순서를 기다리세요',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text(
                  '재입찰 차례를 기다리는 중...',
                  style: TextStyle(color: AppTheme.onSurfaceMuted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Action phase
  // ---------------------------------------------------------------------------

  Widget _buildActionPhase(BuildContext context) {
    final hasBoom = _actionCards.contains('action_boom');
    final hasBust = _actionCards.contains('action_bust');
    final boomActions = widget.playerView.allowedActions
        .where((a) => a.actionType == _kUseBoom)
        .toList();
    final bustActions = widget.playerView.allowedActions
        .where((a) => a.actionType == _kUseBust)
        .toList();
    final canEndPhase = _hasAction(_kEndPhase);

    return _PhaseCard(
      title: '액션 단계',
      subtitle: '액션 카드를 사용하거나 완료하세요',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                        style:
                            TextStyle(color: AppTheme.onTertiaryContainer)),
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
                        onPressed: () => _onAction(a.actionType, a.params),
                        child: Text(
                            _companyShort[a.params['company']] ??
                                a.params['company'] as String? ??
                                ''),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
          ],

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
                        onPressed: () => _onAction(a.actionType, a.params),
                        child: Text(
                            _companyShort[a.params['company']] ??
                                a.params['company'] as String? ??
                                ''),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
          ],

          if (canEndPhase)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.secondaryContainer,
                foregroundColor: AppTheme.onSecondaryContainer,
              ),
              icon: const Icon(Icons.done, size: 18),
              label: const Text('액션 완료'),
              onPressed: () => _onAction(_kEndPhase, {}),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Selling phase
  // ---------------------------------------------------------------------------

  Widget _buildSellingPhase(BuildContext context) {
    final normalHoldings =
        _portfolio.entries.where((e) => e.value > 0).toList();
    final splitHoldings =
        _splitPortfolio.entries.where((e) => e.value > 0).toList();
    final canEndPhase = _hasAction(_kEndPhase);

    return _PhaseCard(
      title: '매매 단계',
      subtitle: '주식을 매도하세요',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (normalHoldings.isNotEmpty) ...[
            const Text('내 포트폴리오 (일반):',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            ...normalHoldings.map((e) {
              final company = e.key;
              final count = e.value;
              final color = _companyColors[company] ?? Colors.grey;
              final short = _companyShort[company] ?? company.toUpperCase();
              final canSell = widget.playerView.allowedActions.any((a) =>
                  a.actionType == _kSellStock &&
                  a.params['company'] == company &&
                  a.params['type'] == 'normal');
              return _HoldingRow(
                label: '$short (일반) × $count주',
                color: color,
                canSell: canSell,
                onSell: canSell
                    ? () => _onAction(
                        _kSellStock, {'company': company, 'type': 'normal'})
                    : null,
              );
            }),
            const SizedBox(height: 8),
          ],

          if (splitHoldings.isNotEmpty) ...[
            const Text('내 포트폴리오 (분할주):',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            ...splitHoldings.map((e) {
              final company = e.key;
              final count = e.value;
              final color = _companyColors[company] ?? Colors.grey;
              final short = _companyShort[company] ?? company.toUpperCase();
              final canSell = widget.playerView.allowedActions.any((a) =>
                  a.actionType == _kSellStock &&
                  a.params['company'] == company &&
                  a.params['type'] == 'split');
              return _HoldingRow(
                label: '$short (분할) × $count주',
                color: color,
                isSplit: true,
                canSell: canSell,
                onSell: canSell
                    ? () => _onAction(
                        _kSellStock, {'company': company, 'type': 'split'})
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

          if (canEndPhase)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.secondaryContainer,
                foregroundColor: AppTheme.onSecondaryContainer,
              ),
              icon: const Icon(Icons.done, size: 18),
              label: const Text('매매 완료'),
              onPressed: () => _onAction(_kEndPhase, {}),
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
    final imgPath = _companyImages[company];

    return Row(
      children: [
        if (imgPath != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.asset(imgPath,
                width: 24, height: 24, fit: BoxFit.cover),
          ),
          const SizedBox(width: 6),
        ] else ...[
          Icon(Icons.trending_up, size: 14, color: color),
          const SizedBox(width: 4),
        ],
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

/// Renders a hand card — stock cards show company illustration, others a chip.
/// [selected] draws a highlighted border; [dimmed] reduces opacity.
Widget _buildHandCard(
  String cardId, {
  bool selected = false,
  bool dimmed = false,
}) {
  Widget card;

  if (cardId.startsWith('stock_')) {
    final company = cardId.substring(6);
    final color = _companyColors[company] ?? Colors.grey;
    final short = _companyShort[company] ?? company.toUpperCase();
    final imgPath = _companyImages[company];

    final borderColor = selected
        ? color
        : color.withValues(alpha: dimmed ? 0.3 : 0.7);
    final bgColor = selected
        ? color.withValues(alpha: 0.18)
        : color.withValues(alpha: dimmed ? 0.02 : 0.06);

    card = Container(
      width: 64,
      margin: const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(
        border: Border.all(
          color: borderColor,
          width: selected ? 2.5 : 1.5,
        ),
        borderRadius: BorderRadius.circular(8),
        color: bgColor,
      ),
      child: Column(
        children: [
          if (imgPath != null)
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(7)),
              child: Image.asset(imgPath,
                  height: 52, width: 64, fit: BoxFit.cover),
            )
          else
            Container(
                height: 52,
                color: color.withValues(alpha: dimmed ? 0.1 : 0.2)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              short,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: dimmed
                    ? color.withValues(alpha: 0.4)
                    : color,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  } else {
    // Fee / action cards — compact chip
    Color bg = AppTheme.surfaceContainerHigh;
    Color fg = AppTheme.onSurface;
    if (cardId == 'action_boom') {
      bg = AppTheme.tertiaryContainer;
      fg = AppTheme.onTertiaryContainer;
    } else if (cardId == 'action_bust') {
      bg = AppTheme.errorContainer;
      fg = AppTheme.error;
    }

    card = Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? bg : bg.withValues(alpha: dimmed ? 0.4 : 1.0),
        borderRadius: BorderRadius.circular(8),
        border: selected
            ? Border.all(color: fg, width: 2)
            : null,
      ),
      child: Text(
        _cardName(cardId),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: dimmed ? fg.withValues(alpha: 0.4) : fg,
        ),
      ),
    );
  }

  return card;
}

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
    final companyKey = _companyShort.entries
        .firstWhere(
          (e) => label.startsWith(e.value),
          orElse: () => const MapEntry('', ''),
        )
        .key;
    final imgPath =
        companyKey.isNotEmpty ? _companyImages[companyKey] : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          if (imgPath != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.asset(imgPath,
                  width: 28, height: 28, fit: BoxFit.cover),
            )
          else
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
