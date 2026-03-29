import 'dart:math';

import '../../game_session/game_log_entry.dart';
import '../../game_session/game_session_state.dart';
import '../../game_session/session_phase.dart';
import '../../game_session/turn_state.dart';
import '../../game_session/turn_step.dart';
import '../game_pack_rules.dart';
import '../game_state.dart';
import '../player_action.dart';
import '../views/allowed_action.dart';
import '../views/board_view.dart';
import '../views/player_view.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const String _kPackId = 'stockpile';
const int _kStartingCash = 20000;
const int _kSplitResetPrice = 6;
const int _kSplitThreshold = 10; // price > 10 triggers split (11 is the split space)
const int _kBankruptcyResetPrice = 5;
const int _kMaxRecentLog = 10;
const int _kDividendSentinel = -99;
const int _kDividendPayout = 2000;
const int _kMajorityBonus = 10000;
const int _kTiedMajorityBonus = 5000;
const int _kMaxBid = 25000;

/// Human-readable Korean display names for each company.
const Map<String, String> _kCompanyNames = {
  'aauto': 'AAUTO',
  'epic': 'EPIC',
  'fed': 'FED',
  'lehm': 'LEHM',
  'sip': 'SIP',
  'tot': 'TOT',
};

/// Returns the player's display nickname, falling back to playerId.
String _nick(GameSessionState state, String playerId) =>
    state.players[playerId]?.nickname ?? playerId;

/// Returns a user-friendly card name for log messages.
String _logCardName(String cardId) {
  if (cardId.startsWith('stock_')) {
    final c = cardId.substring(6);
    return '${_kCompanyNames[c] ?? c} 주식';
  }
  if (cardId == 'fee_1000') return '수수료 \$1K';
  if (cardId == 'fee_2000') return '수수료 \$2K';
  if (cardId == 'action_boom') return 'Boom!';
  if (cardId == 'action_bust') return 'Bust!';
  return cardId;
}

/// Company IDs in canonical order (used as indices into forecast arrays).
const List<String> _kCompanies = [
  'aauto',
  'epic',
  'fed',
  'lehm',
  'sip',
  'tot',
];

/// Starting prices for each company — all start at $5 per basic rules.
const Map<String, int> _kStartingPrices = {
  'aauto': 5,
  'epic': 5,
  'fed': 5,
  'lehm': 5,
  'sip': 5,
  'tot': 5,
};

/// Total rounds per player count.
const Map<int, int> _kTotalRounds = {
  3: 8,
  4: 6,
  5: 4,
};

// Market deck composition
const int _kStockCardsPerCompany = 10;  // 6 × 10 = 60
const int _kFee1000Count = 8;
const int _kFee2000Count = 4;
const int _kActionBoomCount = 4;
const int _kActionBustCount = 4;

// ---------------------------------------------------------------------------
// StockpileRules
// ---------------------------------------------------------------------------

/// Concrete [GamePackRules] for the Stockpile stock market board game.
///
/// All 6 game phases (information, supply, demand, action, selling, movement)
/// are encoded in [GameState.data] under the `'phase'` key.  The platform's
/// [SessionPhase] remains [SessionPhase.inGame] throughout.
///
/// All methods are pure — no mutable instance state beyond the optional [seed].
class StockpileRules extends GamePackRules {
  /// Optional RNG seed for deterministic testing.
  final int? seed;

  StockpileRules({this.seed});

  @override
  String get packId => _kPackId;

  @override
  int get minPlayers => 3;

  @override
  int get maxPlayers => 5;

  @override
  String get boardOrientation => 'landscape';

  @override
  String get nodeOrientation => 'landscape';

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  GameSessionState createInitialGameState(GameSessionState sessionState) {
    final playerOrder = List<String>.from(sessionState.playerOrder);
    assert(playerOrder.length >= 3 && playerOrder.length <= 5,
        'Stockpile requires 3–5 players');

    final rng = seed != null ? Random(seed) : Random();
    final playerCount = playerOrder.length;
    final totalRounds = _kTotalRounds[playerCount] ?? 8;

    // Build and shuffle market deck
    final deck = _buildMarketDeck(rng);

    // Build cash map
    final cash = <String, int>{
      for (final id in playerOrder) id: _kStartingCash,
    };

    // Empty portfolios
    final portfolios = <String, Map<String, int>>{
      for (final id in playerOrder) id: {},
    };
    final splitPortfolios = <String, Map<String, int>>{
      for (final id in playerOrder) id: {},
    };

    // Pre-generate all forecasts upfront so they are stable across phases
    final forecasts = _generateAllForecasts(totalRounds, rng);

    // Partial data — _setupRound will add phase/stockpile/supply/forecast data
    final partialData = <String, dynamic>{
      'round': 1,
      'totalRounds': totalRounds,
      'phase': 'supply',
      'stockPrices': Map<String, dynamic>.from(_kStartingPrices),
      'marketDeck': deck,
      'discardPile': <String>[],
      'cash': cash,
      'portfolios': portfolios,
      'splitPortfolios': splitPortfolios,
      'pendingFees': <String, int>{},
      'forecasts': forecasts,
      'publicForecast': <String, dynamic>{},
      'privateForecastByPlayer': <String, dynamic>{},
      'stockpiles': <dynamic>[],
      'supplyHands': <String, dynamic>{},
      'supplyPlaced': <String, dynamic>{},
      'demandBids': <String, dynamic>{},
      'demandRound': 1,
      'outbidPlayers': <String>[],
      'rebidActedPlayers': <String>[],
      'demandPassedPlayers': <String>[],
      'actionCards': <String, dynamic>{},
      'phaseActedPlayers': <String>[],
    };

    // Run _setupRound to deal stockpile cards, supply hands, and forecasts
    final data = _setupRound(partialData, playerOrder, 1, forecasts, rng);

    final gameState = GameState(
      gameId: sessionState.sessionId,
      turn: 0,
      activePlayerId: playerOrder.first,
      data: data,
    );

    final turnState = TurnState(
      round: 1,
      turnIndex: 0,
      activePlayerId: playerOrder.first,
      step: TurnStep.main,
      actionCountThisTurn: 0,
    );

    return sessionState.copyWith(
      phase: SessionPhase.inGame,
      gameState: gameState,
      turnState: turnState,
      version: sessionState.version + 1,
    );
  }

  // ---------------------------------------------------------------------------
  // Query
  // ---------------------------------------------------------------------------

  @override
  List<AllowedAction> getAllowedActions(
    GameSessionState state,
    String playerId,
  ) {
    if (state.phase != SessionPhase.inGame) return const [];
    final turnState = state.turnState;
    if (turnState == null) return const [];
    if (turnState.activePlayerId != playerId) return const [];
    final gameState = state.gameState;
    if (gameState == null) return const [];

    final phase = gameState.data['phase'] as String;
    final playerOrder = state.playerOrder;

    return switch (phase) {
      'supply' => _supplyActions(playerId, gameState, playerOrder.length),
      'demand' => _demandActions(playerId, gameState, playerOrder.length),
      'action' => _actionActions(playerId, gameState),
      'selling' => _sellingActions(playerId, gameState),
      _ => const [],
    };
  }

  // ---------------------------------------------------------------------------
  // Mutation
  // ---------------------------------------------------------------------------

  @override
  GameSessionState applyAction(
    GameSessionState state,
    String playerId,
    PlayerAction action,
  ) {
    return switch (action.type) {
      'PLACE_FACE_UP' => _applyPlaceFaceUp(state, playerId, action),
      'PLACE_FACE_DOWN' => _applyPlaceFaceDown(state, playerId, action),
      'BID' => _applyBid(state, playerId, action),
      'DEMAND_PASS' => _applyDemandPass(state, playerId),
      'END_PHASE' => _applyEndPhase(state, playerId),
      'USE_BOOM' => _applyUseBoom(state, playerId, action),
      'USE_BUST' => _applyUseBust(state, playerId, action),
      'SELL_STOCK' => _applySellStock(state, playerId, action),
      _ => state,
    };
  }

  // ---------------------------------------------------------------------------
  // End condition
  // ---------------------------------------------------------------------------

  @override
  ({bool ended, List<String> winnerIds}) checkGameEnd(GameSessionState state) {
    final gameState = state.gameState;
    final turnState = state.turnState;
    if (gameState == null || turnState == null) {
      return (ended: false, winnerIds: []);
    }

    final totalRounds = gameState.data['totalRounds'] as int;
    if (turnState.round <= totalRounds) {
      return (ended: false, winnerIds: []);
    }

    // Compute final wealth for each player
    final playerOrder = state.playerOrder;
    final cash = _getCash(gameState);
    final prices = _getPrices(gameState);
    final portfolios = _getPortfolios(gameState);
    final splitPortfolios = _getSplitPortfolios(gameState);

    // Majority bonus
    final majorityBonuses =
        _computeMajorityBonuses(playerOrder, portfolios, splitPortfolios);

    final wealth = <String, int>{};
    for (final pid in playerOrder) {
      int total = cash[pid] ?? 0;
      // Normal shares
      final normal = portfolios[pid] ?? {};
      for (final entry in normal.entries) {
        total += (prices[entry.key] ?? 0) * entry.value;
      }
      // Split shares (count double)
      final split = splitPortfolios[pid] ?? {};
      for (final entry in split.entries) {
        total += (prices[entry.key] ?? 0) * 2 * entry.value;
      }
      // Majority bonus
      total += majorityBonuses[pid] ?? 0;
      wealth[pid] = total;
    }

    final maxWealth = wealth.values.fold(0, (prev, w) => w > prev ? w : prev);
    final winners = wealth.entries
        .where((e) => e.value == maxWealth)
        .map((e) => e.key)
        .toList();

    return (ended: true, winnerIds: winners);
  }

  // ---------------------------------------------------------------------------
  // View builders
  // ---------------------------------------------------------------------------

  @override
  BoardView buildBoardView(GameSessionState state) {
    final gameState = state.gameState;
    if (gameState == null) {
      return BoardView(
        phase: state.phase,
        scores: const {},
        turnState: state.turnState,
        deckRemaining: 0,
        discardPile: const [],
        recentLog: const [],
        version: state.version,
      );
    }

    final gData = gameState.data;
    final cash = _getCash(gameState);
    final prices = _getPrices(gameState);
    final stockpiles = _getStockpiles(gameState);
    final phase = gData['phase'] as String;
    final round = gData['round'] as int;
    final totalRounds = gData['totalRounds'] as int;
    final deck = gData['marketDeck'] as List;
    final publicForecast =
        Map<String, dynamic>.from(gData['publicForecast'] as Map? ?? {});

    // Stockpile public state: face-up cards visible, face-down count only.
    final stockpilesPublic = <Map<String, dynamic>>[];
    for (final sp in stockpiles) {
      stockpilesPublic.add({
        'faceUpCards': List<String>.from(sp['faceUpCards'] as List? ?? []),
        'faceDownCount': (sp['faceDownCards'] as List? ?? []).length,
        'currentBid': sp['currentBid'] as int? ?? 0,
        'currentBidderId': sp['currentBidderId'] as String?,
      });
    }

    final recentLog = state.log.length > _kMaxRecentLog
        ? state.log.sublist(state.log.length - _kMaxRecentLog)
        : List<GameLogEntry>.from(state.log);

    return BoardView(
      phase: state.phase,
      scores: Map<String, int>.from(prices),
      turnState: state.turnState,
      deckRemaining: deck.length,
      discardPile: const [],
      recentLog: recentLog,
      version: state.version,
      data: {
        'packId': _kPackId,
        'phase': phase,
        'round': round,
        'totalRounds': totalRounds,
        'stockPrices': Map<String, int>.from(prices),
        'stockpiles': stockpilesPublic,
        'publicForecast': publicForecast,
        'cash': Map<String, int>.from(cash),
      },
    );
  }

  @override
  PlayerView buildPlayerView(GameSessionState state, String playerId) {
    final gameState = state.gameState;
    if (gameState == null) {
      return PlayerView(
        phase: state.phase,
        playerId: playerId,
        hand: const [],
        scores: const {},
        turnState: state.turnState,
        allowedActions: getAllowedActions(state, playerId),
        version: state.version,
      );
    }

    final gData = gameState.data;
    final cash = _getCash(gameState);
    final portfolios = _getPortfolios(gameState);
    final splitPortfolios = _getSplitPortfolios(gameState);
    final supplyHands = gData['supplyHands'] as Map? ?? {};
    final privateForecastByPlayer =
        gData['privateForecastByPlayer'] as Map? ?? {};
    final actionCards = gData['actionCards'] as Map? ?? {};
    final pendingFees = gData['pendingFees'] as Map? ?? {};
    final demandBids = gData['demandBids'] as Map? ?? {};
    final supplyPlaced = gData['supplyPlaced'] as Map? ?? {};

    // hand: only the actual supply cards dealt this round.
    final mySupplyCards =
        List<String>.from(supplyHands[playerId] as List? ?? []);

    // Private structured data goes into PlayerView.data.
    final myNormal = Map<String, int>.from(
        (portfolios[playerId] as Map?)?.cast<String, int>() ?? {});
    final mySplit = Map<String, int>.from(
        (splitPortfolios[playerId] as Map?)?.cast<String, int>() ?? {});
    final myForecast =
        privateForecastByPlayer[playerId] as Map<dynamic, dynamic>?;
    final myActionCards =
        List<String>.from(actionCards[playerId] as List? ?? []);
    final myFees = pendingFees[playerId] as int? ?? 0;
    final myBid = demandBids[playerId] as Map?;
    final myPlaced = supplyPlaced[playerId] as Map? ?? {};

    return PlayerView(
      phase: state.phase,
      playerId: playerId,
      hand: mySupplyCards,
      scores: Map<String, int>.from(cash),
      turnState: state.turnState,
      allowedActions: getAllowedActions(state, playerId),
      version: state.version,
      data: {
        'packId': _kPackId,
        'phase': gData['phase'] as String,
        'portfolio': myNormal,
        'splitPortfolio': mySplit,
        if (myForecast != null && myForecast.isNotEmpty)
          'privateForecast': {
            'company': myForecast['company'] as String,
            'change': myForecast['change'] as int,
          },
        'actionCards': myActionCards,
        'pendingFees': myFees,
        if (myBid != null)
          'myBid': {
            'stockpileIndex': myBid['stockpileIndex'] as int,
            'amount': myBid['amount'] as int,
          },
        'supplyPlaced': {
          'faceUp': myPlaced['faceUp'] as bool? ?? false,
          'faceDown': myPlaced['faceDown'] as bool? ?? false,
        },
        'demandRound': gData['demandRound'] as int? ?? 1,
        'outbidPlayers':
            List<String>.from(gData['outbidPlayers'] as List? ?? []),
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Supply phase actions
  // ---------------------------------------------------------------------------

  List<AllowedAction> _supplyActions(
    String playerId,
    GameState gameState,
    int stockpileCount,
  ) {
    final supplyHands = gameState.data['supplyHands'] as Map? ?? {};
    final supplyPlaced = gameState.data['supplyPlaced'] as Map? ?? {};
    final myHand = List<String>.from(supplyHands[playerId] as List? ?? []);
    final myPlaced = supplyPlaced[playerId] as Map? ?? {};
    final hasPlacedFaceUp = myPlaced['faceUp'] as bool? ?? false;
    final hasPlacedFaceDown = myPlaced['faceDown'] as bool? ?? false;

    final actions = <AllowedAction>[];

    for (var i = 0; i < myHand.length; i++) {
      final card = myHand[i];
      for (var spIdx = 0; spIdx < stockpileCount; spIdx++) {
        if (!hasPlacedFaceUp) {
          actions.add(AllowedAction(
            actionType: 'PLACE_FACE_UP',
            label: 'Place $card face-up on pile ${spIdx + 1}',
            params: {'cardIndex': i, 'stockpileIndex': spIdx},
          ));
        }
        if (!hasPlacedFaceDown) {
          actions.add(AllowedAction(
            actionType: 'PLACE_FACE_DOWN',
            label: 'Place $card face-down on pile ${spIdx + 1}',
            params: {'cardIndex': i, 'stockpileIndex': spIdx},
          ));
        }
      }
    }

    return actions;
  }

  // ---------------------------------------------------------------------------
  // Demand phase actions
  // ---------------------------------------------------------------------------

  List<AllowedAction> _demandActions(
    String playerId,
    GameState gameState,
    int stockpileCount,
  ) {
    final cash = _getCash(gameState);
    final myCash = cash[playerId] ?? 0;
    final demandRound = gameState.data['demandRound'] as int? ?? 1;
    final isRebidRound = demandRound > 1;
    final stockpiles = _getStockpiles(gameState);
    final actions = <AllowedAction>[];

    for (var i = 0; i < stockpileCount; i++) {
      final sp = (stockpiles[i] as Map).cast<String, dynamic>();
      final currentBidderId = sp['currentBidderId'] as String?;

      // In a rebid round, skip piles where this player is already the leader.
      if (isRebidRound && currentBidderId == playerId) continue;

      final currentBid = sp['currentBid'] as int? ?? 0;

      // Minimum bid is current pile bid + 1 (must be strictly higher).
      // In the first round, pile currentBid starts at 0, so amount 0 is valid
      // only if no one has bid yet.
      final minValidBid = currentBid > 0 ? currentBid + 1 : 0;

      // If the minimum valid bid already exceeds the cap, this pile is locked —
      // no further bids are possible. Skip it entirely so no button appears.
      if (minValidBid > _kMaxBid) continue;

      // Also skip if the player can't afford even the minimum bid.
      if (minValidBid > myCash) continue;

      actions.add(AllowedAction(
        actionType: 'BID',
        label: 'Bid on pile ${i + 1}',
        params: {'stockpileIndex': i, 'amount': minValidBid},
      ));

      // All-in option (capped to _kMaxBid)
      final allInAmount = myCash.clamp(0, _kMaxBid);
      if (allInAmount > currentBid) {
        actions.add(AllowedAction(
          actionType: 'BID',
          label: 'Bid all \$$allInAmount on pile ${i + 1}',
          params: {'stockpileIndex': i, 'amount': allInAmount},
        ));
      }
    }

    // DEMAND_PASS is only offered during rebid rounds.
    if (isRebidRound) {
      actions.add(const AllowedAction(
        actionType: 'DEMAND_PASS',
        label: '이번 재입찰 통과',
      ));
    }

    return actions;
  }

  // ---------------------------------------------------------------------------
  // Action phase actions
  // ---------------------------------------------------------------------------

  List<AllowedAction> _actionActions(
    String playerId,
    GameState gameState,
  ) {
    final actionCards = gameState.data['actionCards'] as Map? ?? {};
    final myCards = List<String>.from(actionCards[playerId] as List? ?? []);
    final actions = <AllowedAction>[];

    for (final card in myCards) {
      if (card == 'action_boom') {
        for (final company in _kCompanies) {
          actions.add(AllowedAction(
            actionType: 'USE_BOOM',
            label: 'Boom $company (+2)',
            params: {'company': company},
          ));
        }
      } else if (card == 'action_bust') {
        for (final company in _kCompanies) {
          actions.add(AllowedAction(
            actionType: 'USE_BUST',
            label: 'Bust $company (-2)',
            params: {'company': company},
          ));
        }
      }
    }

    // Always allow skipping (no cards or choose not to use them)
    actions.add(const AllowedAction(
      actionType: 'END_PHASE',
      label: 'Skip Actions',
    ));

    return actions;
  }

  // ---------------------------------------------------------------------------
  // Selling phase actions
  // ---------------------------------------------------------------------------

  List<AllowedAction> _sellingActions(
    String playerId,
    GameState gameState,
  ) {
    final portfolios = _getPortfolios(gameState);
    final splitPortfolios = _getSplitPortfolios(gameState);
    final myNormal = portfolios[playerId] ?? {};
    final mySplit = splitPortfolios[playerId] ?? {};
    final prices = _getPrices(gameState);
    final actions = <AllowedAction>[];

    for (final company in _kCompanies) {
      final normalShares = myNormal[company] ?? 0;
      final splitShares = mySplit[company] ?? 0;
      final price = prices[company] ?? 0;

      if (normalShares > 0) {
        actions.add(AllowedAction(
          actionType: 'SELL_STOCK',
          label: 'Sell $company normal @ \$$price',
          params: {'company': company, 'type': 'normal'},
        ));
      }
      if (splitShares > 0) {
        actions.add(AllowedAction(
          actionType: 'SELL_STOCK',
          label: 'Sell $company split @ \$${price * 2}',
          params: {'company': company, 'type': 'split'},
        ));
      }
    }

    actions.add(const AllowedAction(
      actionType: 'END_PHASE',
      label: 'Done Selling',
    ));

    return actions;
  }

  // ---------------------------------------------------------------------------
  // Private action implementations
  // ---------------------------------------------------------------------------

  GameSessionState _applyPlaceFaceUp(
    GameSessionState state,
    String playerId,
    PlayerAction action,
  ) {
    final gameState = state.gameState;
    if (gameState == null) return state;

    final cardIndex = action.data['cardIndex'] as int?;
    final stockpileIndex = action.data['stockpileIndex'] as int?;
    if (cardIndex == null || stockpileIndex == null) return state;

    final data = Map<String, dynamic>.from(gameState.data);
    final supplyHands = _deepCopyStringListMap(data['supplyHands'] as Map);
    final myHand = supplyHands[playerId] ?? [];
    if (cardIndex >= myHand.length) return state;

    final card = myHand.removeAt(cardIndex);

    final stockpiles = _copyStockpiles(data['stockpiles'] as List);
    if (stockpileIndex >= stockpiles.length) return state;

    final sp = Map<String, dynamic>.from(stockpiles[stockpileIndex]);
    final faceUp = List<String>.from(sp['faceUpCards'] as List);
    faceUp.add(card);
    sp['faceUpCards'] = faceUp;
    stockpiles[stockpileIndex] = sp;

    final supplyPlaced = _deepCopyBoolMap(data['supplyPlaced'] as Map? ?? {});
    final myPlaced = Map<String, dynamic>.from(
        (supplyPlaced[playerId] as Map?)?.cast<String, dynamic>() ?? {});
    myPlaced['faceUp'] = true;
    supplyPlaced[playerId] = myPlaced;

    data['supplyHands'] = supplyHands;
    data['stockpiles'] = stockpiles;
    data['supplyPlaced'] = supplyPlaced;

    final newGameState = gameState.copyWith(data: data);

    // Check if player has placed both — if so, advance
    final hasPlacedFaceDown = myPlaced['faceDown'] as bool? ?? false;
    if (hasPlacedFaceDown) {
      final logEntry = GameLogEntry(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        eventType: 'PLACE_FACE_UP',
        description:
            '${_nick(state, playerId)} → 더미 ${stockpileIndex + 1}에 ${_logCardName(card)} 앞면 배치',
      );
      return _advancePlayer(
        state.copyWith(gameState: newGameState).addLog(logEntry),
        playerId,
      );
    }

    final logEntry = GameLogEntry(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      eventType: 'PLACE_FACE_UP',
      description:
          '${_nick(state, playerId)} → 더미 ${stockpileIndex + 1}에 ${_logCardName(card)} 앞면 배치',
    );

    return state.copyWith(gameState: newGameState).addLog(logEntry);
  }

  GameSessionState _applyPlaceFaceDown(
    GameSessionState state,
    String playerId,
    PlayerAction action,
  ) {
    final gameState = state.gameState;
    if (gameState == null) return state;

    final cardIndex = action.data['cardIndex'] as int?;
    final stockpileIndex = action.data['stockpileIndex'] as int?;
    if (cardIndex == null || stockpileIndex == null) return state;

    final data = Map<String, dynamic>.from(gameState.data);
    final supplyHands = _deepCopyStringListMap(data['supplyHands'] as Map);
    final myHand = supplyHands[playerId] ?? [];
    if (cardIndex >= myHand.length) return state;

    final card = myHand.removeAt(cardIndex);

    final stockpiles = _copyStockpiles(data['stockpiles'] as List);
    if (stockpileIndex >= stockpiles.length) return state;

    final sp = Map<String, dynamic>.from(stockpiles[stockpileIndex]);
    final faceDown = List<String>.from(sp['faceDownCards'] as List);
    faceDown.add(card);
    sp['faceDownCards'] = faceDown;
    stockpiles[stockpileIndex] = sp;

    final supplyPlaced = _deepCopyBoolMap(data['supplyPlaced'] as Map? ?? {});
    final myPlaced = Map<String, dynamic>.from(
        (supplyPlaced[playerId] as Map?)?.cast<String, dynamic>() ?? {});
    myPlaced['faceDown'] = true;
    supplyPlaced[playerId] = myPlaced;

    data['supplyHands'] = supplyHands;
    data['stockpiles'] = stockpiles;
    data['supplyPlaced'] = supplyPlaced;

    final newGameState = gameState.copyWith(data: data);

    // Check if player has placed both — if so, advance
    final hasPlacedFaceUp = myPlaced['faceUp'] as bool? ?? false;
    if (hasPlacedFaceUp) {
      final logEntry = GameLogEntry(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        eventType: 'PLACE_FACE_DOWN',
        description:
            '${_nick(state, playerId)} → 더미 ${stockpileIndex + 1}에 카드 뒷면 배치',
      );
      return _advancePlayer(
        state.copyWith(gameState: newGameState).addLog(logEntry),
        playerId,
      );
    }

    final logEntry = GameLogEntry(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      eventType: 'PLACE_FACE_DOWN',
      description:
          '${_nick(state, playerId)} → 더미 ${stockpileIndex + 1}에 카드 뒷면 배치',
    );

    return state.copyWith(gameState: newGameState).addLog(logEntry);
  }

  GameSessionState _applyBid(
    GameSessionState state,
    String playerId,
    PlayerAction action,
  ) {
    final gameState = state.gameState;
    if (gameState == null) return state;

    final stockpileIndex = action.data['stockpileIndex'] as int?;
    final amount = action.data['amount'] as int?;
    if (stockpileIndex == null || amount == null) return state;

    // Enforce $25,000 upper cap.
    if (amount > _kMaxBid) return state;

    final data = Map<String, dynamic>.from(gameState.data);
    final stockpiles = _copyStockpiles(data['stockpiles'] as List);
    if (stockpileIndex >= stockpiles.length) return state;

    final sp = Map<String, dynamic>.from(stockpiles[stockpileIndex]);
    final currentBid = sp['currentBid'] as int? ?? 0;
    final previousBidderId = sp['currentBidderId'] as String?;

    // Reject bids that are not strictly higher than the current leading bid.
    // A $0 bid on an unclaimed pile (no current bidder) is valid.
    if (previousBidderId != null && amount <= currentBid) return state;

    // Track displaced bidder in outbidPlayers (only if there was a prior bidder
    // and that bidder is different from the current player).
    final outbidPlayers = List<String>.from(
        (data['outbidPlayers'] as List? ?? []));
    if (previousBidderId != null &&
        previousBidderId != playerId &&
        !outbidPlayers.contains(previousBidderId)) {
      outbidPlayers.add(previousBidderId);
    }
    // The player who is now bidding higher is no longer outbid.
    outbidPlayers.remove(playerId);

    sp['currentBid'] = amount;
    sp['currentBidderId'] = playerId;
    stockpiles[stockpileIndex] = sp;

    // Record player's bid.
    final demandBids = Map<String, dynamic>.from(
        (data['demandBids'] as Map?)?.cast<String, dynamic>() ?? {});
    demandBids[playerId] = {
      'stockpileIndex': stockpileIndex,
      'amount': amount,
    };

    data['stockpiles'] = stockpiles;
    data['demandBids'] = demandBids;
    data['outbidPlayers'] = outbidPlayers;

    final newGameState = gameState.copyWith(data: data);

    final logEntry = GameLogEntry(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      eventType: 'BID',
      description:
          '${_nick(state, playerId)} → 더미 ${stockpileIndex + 1}에 \$${amount ~/ 1000 > 0 ? '${amount ~/ 1000}K' : amount} 입찰',
    );

    return _advanceDemandPlayer(
      state.copyWith(gameState: newGameState).addLog(logEntry),
      playerId,
    );
  }

  /// Handles a DEMAND_PASS action during a rebid round.
  ///
  /// Adds [playerId] to [demandPassedPlayers] and advances to the next
  /// rebid-eligible player.  If all outbid players have now acted, resolves
  /// bids and transitions to the action phase.
  GameSessionState _applyDemandPass(
    GameSessionState state,
    String playerId,
  ) {
    final gameState = state.gameState;
    if (gameState == null) return state;

    final data = Map<String, dynamic>.from(gameState.data);
    final passed = List<String>.from(
        (data['demandPassedPlayers'] as List? ?? []));
    if (!passed.contains(playerId)) passed.add(playerId);
    data['demandPassedPlayers'] = passed;

    final newGameState = gameState.copyWith(data: data);

    final logEntry = GameLogEntry(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      eventType: 'DEMAND_PASS',
      description: '${_nick(state, playerId)} 재입찰 통과',
    );

    return _advanceDemandPlayer(
      state.copyWith(gameState: newGameState).addLog(logEntry),
      playerId,
    );
  }

  GameSessionState _applyEndPhase(
    GameSessionState state,
    String playerId,
  ) {
    final logEntry = GameLogEntry(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      eventType: 'END_PHASE',
      description: '${_nick(state, playerId)} 단계 완료',
    );

    return _advancePlayer(state.addLog(logEntry), playerId);
  }

  GameSessionState _applyUseBoom(
    GameSessionState state,
    String playerId,
    PlayerAction action,
  ) {
    final gameState = state.gameState;
    if (gameState == null) return state;

    final company = action.data['company'] as String?;
    if (company == null || !_kCompanies.contains(company)) return state;

    final data = Map<String, dynamic>.from(gameState.data);
    final actionCards = Map<String, dynamic>.from(
        (data['actionCards'] as Map?)?.cast<String, dynamic>() ?? {});
    final myCards = List<String>.from(actionCards[playerId] as List? ?? []);
    if (!myCards.contains('action_boom')) return state;

    myCards.remove('action_boom');
    actionCards[playerId] = myCards;

    final prices = Map<String, dynamic>.from(data['stockPrices'] as Map);
    final currentPrice = prices[company] as int;
    final newPrice = _applyPriceChange(
      company,
      currentPrice,
      2,
      _getPortfolios(gameState),
      _getSplitPortfolios(gameState),
      _getCash(gameState),
    );
    prices[company] = newPrice['price'];

    // Apply any split portfolio changes
    final portfolios = _deepCopyPortfolioMap(data['portfolios'] as Map);
    final splitPortfolios =
        _deepCopyPortfolioMap(data['splitPortfolios'] as Map);
    final cash = Map<String, int>.from(_getCash(gameState));

    _applySplitConsequences(
      newPrice,
      portfolios,
      splitPortfolios,
      cash,
    );

    data['stockPrices'] = prices;
    data['actionCards'] = actionCards;
    data['portfolios'] = portfolios;
    data['splitPortfolios'] = splitPortfolios;
    data['cash'] = cash;

    final newGameState = gameState.copyWith(data: data);

    final logEntry = GameLogEntry(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      eventType: 'USE_BOOM',
      description:
          '${_nick(state, playerId)} → ${_kCompanyNames[company] ?? company} Boom! (+2)',
    );

    return state.copyWith(gameState: newGameState).addLog(logEntry);
  }

  GameSessionState _applyUseBust(
    GameSessionState state,
    String playerId,
    PlayerAction action,
  ) {
    final gameState = state.gameState;
    if (gameState == null) return state;

    final company = action.data['company'] as String?;
    if (company == null || !_kCompanies.contains(company)) return state;

    final data = Map<String, dynamic>.from(gameState.data);
    final actionCards = Map<String, dynamic>.from(
        (data['actionCards'] as Map?)?.cast<String, dynamic>() ?? {});
    final myCards = List<String>.from(actionCards[playerId] as List? ?? []);
    if (!myCards.contains('action_bust')) return state;

    myCards.remove('action_bust');
    actionCards[playerId] = myCards;

    final prices = Map<String, dynamic>.from(data['stockPrices'] as Map);
    final currentPrice = prices[company] as int;
    final newPrice = _applyPriceChange(
      company,
      currentPrice,
      -2,
      _getPortfolios(gameState),
      _getSplitPortfolios(gameState),
      _getCash(gameState),
    );
    prices[company] = newPrice['price'];

    final portfolios = _deepCopyPortfolioMap(data['portfolios'] as Map);
    final splitPortfolios =
        _deepCopyPortfolioMap(data['splitPortfolios'] as Map);
    final cash = Map<String, int>.from(_getCash(gameState));

    _applyBankruptcyConsequences(newPrice, portfolios, splitPortfolios);

    data['stockPrices'] = prices;
    data['actionCards'] = actionCards;
    data['portfolios'] = portfolios;
    data['splitPortfolios'] = splitPortfolios;
    data['cash'] = cash;

    final newGameState = gameState.copyWith(data: data);

    final logEntry = GameLogEntry(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      eventType: 'USE_BUST',
      description:
          '${_nick(state, playerId)} → ${_kCompanyNames[company] ?? company} Bust! (-2)',
    );

    return state.copyWith(gameState: newGameState).addLog(logEntry);
  }

  GameSessionState _applySellStock(
    GameSessionState state,
    String playerId,
    PlayerAction action,
  ) {
    final gameState = state.gameState;
    if (gameState == null) return state;

    final company = action.data['company'] as String?;
    final type = action.data['type'] as String?;
    if (company == null || type == null) return state;
    if (!_kCompanies.contains(company)) return state;

    final data = Map<String, dynamic>.from(gameState.data);
    final prices = _getPrices(gameState);
    final price = prices[company] ?? 0;
    final portfolios = _deepCopyPortfolioMap(data['portfolios'] as Map);
    final splitPortfolios =
        _deepCopyPortfolioMap(data['splitPortfolios'] as Map);
    final cash = Map<String, int>.from(_getCash(gameState));

    int proceeds = 0;

    if (type == 'normal') {
      final shares = portfolios[playerId]?[company] ?? 0;
      if (shares <= 0) return state;
      final myPortfolio = Map<String, int>.from(portfolios[playerId]!);
      myPortfolio[company] = shares - 1;
      if (myPortfolio[company] == 0) myPortfolio.remove(company);
      portfolios[playerId] = myPortfolio;
      proceeds = price;
    } else if (type == 'split') {
      final shares = splitPortfolios[playerId]?[company] ?? 0;
      if (shares <= 0) return state;
      final mySplit = Map<String, int>.from(splitPortfolios[playerId]!);
      mySplit[company] = shares - 1;
      if (mySplit[company] == 0) mySplit.remove(company);
      splitPortfolios[playerId] = mySplit;
      proceeds = price * 2;
    } else {
      return state;
    }

    cash[playerId] = (cash[playerId] ?? 0) + proceeds;

    data['portfolios'] = portfolios;
    data['splitPortfolios'] = splitPortfolios;
    data['cash'] = cash;

    final newGameState = gameState.copyWith(data: data);

    final logEntry = GameLogEntry(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      eventType: 'SELL_STOCK',
      description:
          '${_nick(state, playerId)} → ${_kCompanyNames[company] ?? company} ${type == 'split' ? '분할' : '일반'} 주식 매도 \$${proceeds ~/ 1000 > 0 ? '${proceeds ~/ 1000}K' : proceeds}',
    );

    return state.copyWith(gameState: newGameState).addLog(logEntry);
  }

  // ---------------------------------------------------------------------------
  // Phase progression
  // ---------------------------------------------------------------------------

  /// Demand-specific player advancement that handles both the initial bid round
  /// and rebid rounds.
  ///
  /// After each bid or pass:
  /// - In round 1: advance through all players as usual; when the last player
  ///   acts, check whether any outbid players exist.  If yes, start rebid round.
  ///   If no, resolve bids and transition to action.
  /// - In rebid rounds (demandRound > 1): cycle only through outbidPlayers who
  ///   have not yet acted in this rebid round.  When all have acted, check for
  ///   new outbids to determine whether another rebid round is needed.
  GameSessionState _advanceDemandPlayer(
    GameSessionState state,
    String playerId,
  ) {
    final gameState = state.gameState!;
    final data = Map<String, dynamic>.from(gameState.data);
    final playerOrder = state.playerOrder;
    final demandRound = data['demandRound'] as int? ?? 1;
    final outbidPlayers = List<String>.from(
        (data['outbidPlayers'] as List? ?? []));

    if (demandRound == 1) {
      // ── First bid round: all players bid once in playerOrder ──────────────
      final acted = List<String>.from(
          data['phaseActedPlayers'] as List? ?? []);
      if (!acted.contains(playerId)) acted.add(playerId);
      data['phaseActedPlayers'] = acted;

      final nextPlayer = playerOrder.firstWhere(
        (pid) => !acted.contains(pid),
        orElse: () => '',
      );

      if (nextPlayer.isNotEmpty) {
        return _setActiveDemandPlayer(state, data, nextPlayer, gameState);
      }

      // All players have bid once.  Check for outbids.
      if (outbidPlayers.isEmpty) {
        // No one was outbid — resolve bids directly.
        final newGameState = gameState.copyWith(data: data);
        return _resolveBidsAndTransitionToAction(
            state.copyWith(gameState: newGameState), data, playerOrder);
      }

      // Start rebid round 2.
      return _startRebidRound(state, data, playerOrder, outbidPlayers);
    } else {
      // ── Rebid round: only outbidPlayers act ───────────────────────────────
      final rebidActed = List<String>.from(
          data['rebidActedPlayers'] as List? ?? []);
      if (!rebidActed.contains(playerId)) rebidActed.add(playerId);
      data['rebidActedPlayers'] = rebidActed;

      // Find next outbid player in playerOrder who has not yet acted this round.
      final nextRebidPlayer = playerOrder.firstWhere(
        (pid) => outbidPlayers.contains(pid) && !rebidActed.contains(pid),
        orElse: () => '',
      );

      if (nextRebidPlayer.isNotEmpty) {
        return _setActiveDemandPlayer(state, data, nextRebidPlayer, gameState);
      }

      // All outbid players scheduled for this round have acted.
      // Resolve if no one is still outbid, OR if every remaining outbid player
      // passed this round (they concede their piles).
      // Note: a player who bid and got re-outbid in the same round is still in
      // outbidPlayers — they must get a new rebid round, not be silently resolved.
      final passedPlayers = List<String>.from(
          data['demandPassedPlayers'] as List? ?? []);
      final allRemainingPassed =
          outbidPlayers.isNotEmpty &&
          outbidPlayers.every(passedPlayers.contains);

      if (outbidPlayers.isEmpty || allRemainingPassed) {
        // No one is outbid, or everyone who is outbid chose to pass — resolve.
        final newGameState = gameState.copyWith(data: data);
        return _resolveBidsAndTransitionToAction(
            state.copyWith(gameState: newGameState), data, playerOrder);
      }

      // At least one player is still outbid and hasn't conceded — start another
      // rebid round so they get a chance to respond.
      return _startRebidRound(state, data, playerOrder, outbidPlayers);
    }
  }

  /// Begins a new rebid round, incrementing [demandRound] and resetting the
  /// per-round acted tracking.  Activates the first outbid player in
  /// [playerOrder].
  GameSessionState _startRebidRound(
    GameSessionState state,
    Map<String, dynamic> data,
    List<String> playerOrder,
    List<String> outbidPlayers,
  ) {
    final currentRound = data['demandRound'] as int? ?? 1;
    data['demandRound'] = currentRound + 1;
    data['rebidActedPlayers'] = <String>[];
    // Clear passed list for the new round so players may act again.
    data['demandPassedPlayers'] = <String>[];

    // First outbid player in canonical order.
    final firstOutbid = playerOrder.firstWhere(
      (pid) => outbidPlayers.contains(pid),
      orElse: () => outbidPlayers.first,
    );

    return _setActiveDemandPlayer(
        state, data, firstOutbid, state.gameState!.copyWith(data: data));
  }

  /// Low-level helper: writes [data] and [nextPlayer] back to state.
  GameSessionState _setActiveDemandPlayer(
    GameSessionState state,
    Map<String, dynamic> data,
    String nextPlayer,
    GameState gameState,
  ) {
    final nextIndex = state.playerOrder.indexOf(nextPlayer);
    final newTurnState = TurnState(
      round: state.turnState!.round,
      turnIndex: nextIndex,
      activePlayerId: nextPlayer,
      step: TurnStep.main,
      actionCountThisTurn: 0,
    );
    final newGameState = gameState.copyWith(
      data: data,
      activePlayerId: nextPlayer,
      turn: gameState.turn + 1,
    );
    return state.copyWith(
      gameState: newGameState,
      turnState: newTurnState,
      version: state.version + 1,
    );
  }

  /// Marks [playerId] as having acted, then either advances to the next player
  /// or triggers [_advancePhase] when all players have acted.
  GameSessionState _advancePlayer(
    GameSessionState state,
    String playerId,
  ) {
    final gameState = state.gameState!;
    final data = Map<String, dynamic>.from(gameState.data);
    final acted = List<String>.from(
        data['phaseActedPlayers'] as List? ?? []);
    if (!acted.contains(playerId)) acted.add(playerId);
    data['phaseActedPlayers'] = acted;

    final playerOrder = state.playerOrder;
    // Find next player who has NOT acted
    final nextPlayer = playerOrder.firstWhere(
      (pid) => !acted.contains(pid),
      orElse: () => '',
    );

    if (nextPlayer.isNotEmpty) {
      // Advance turn to next player
      final nextIndex = playerOrder.indexOf(nextPlayer);
      final newTurnState = TurnState(
        round: state.turnState!.round,
        turnIndex: nextIndex,
        activePlayerId: nextPlayer,
        step: TurnStep.main,
        actionCountThisTurn: 0,
      );
      final newGameState = gameState.copyWith(
        data: data,
        activePlayerId: nextPlayer,
        turn: gameState.turn + 1,
      );
      return state.copyWith(
        gameState: newGameState,
        turnState: newTurnState,
        version: state.version + 1,
      );
    }

    // All players acted → advance to next phase
    final newGameState = gameState.copyWith(data: data);
    return _advancePhase(state.copyWith(gameState: newGameState));
  }

  /// Transitions from the current phase to the next, applying any resolution
  /// logic between phases.
  GameSessionState _advancePhase(GameSessionState state) {
    final gameState = state.gameState!;
    final data = Map<String, dynamic>.from(gameState.data);
    final currentPhase = data['phase'] as String;
    final playerOrder = state.playerOrder;

    return switch (currentPhase) {
      'supply' => _transitionToPhase(state, data, playerOrder, 'demand'),
      'demand' => _resolveBidsAndTransitionToAction(state, data, playerOrder),
      'action' => _transitionToPhase(state, data, playerOrder, 'selling'),
      'selling' => _resolveMovement(state, data, playerOrder),
      _ => state,
    };
  }

  /// Transitions to a named phase, resetting phaseActedPlayers and
  /// updating the first player in order.
  GameSessionState _transitionToPhase(
    GameSessionState state,
    Map<String, dynamic> data,
    List<String> playerOrder,
    String targetPhase,
  ) {
    data['phase'] = targetPhase;
    data['phaseActedPlayers'] = <String>[];

    final firstPlayer = playerOrder.first;
    final newTurnState = TurnState(
      round: state.turnState!.round,
      turnIndex: 0,
      activePlayerId: firstPlayer,
      step: TurnStep.main,
      actionCountThisTurn: 0,
    );
    final newGameState = state.gameState!.copyWith(
      data: data,
      activePlayerId: firstPlayer,
    );

    return state.copyWith(
      gameState: newGameState,
      turnState: newTurnState,
      version: state.version + 1,
    );
  }

  /// Resolves the demand auction: distributes stockpile cards to winners,
  /// then transitions to the action phase.
  GameSessionState _resolveBidsAndTransitionToAction(
    GameSessionState state,
    Map<String, dynamic> data,
    List<String> playerOrder,
  ) {
    final stockpiles = _copyStockpiles(data['stockpiles'] as List);
    final cash = Map<String, int>.from(_getCash(state.gameState!));
    final portfolios = _deepCopyPortfolioMap(data['portfolios'] as Map);
    final splitPortfolios =
        _deepCopyPortfolioMap(data['splitPortfolios'] as Map);
    final pendingFees = Map<String, int>.from(
        (data['pendingFees'] as Map? ?? {}).cast<String, int>());
    final actionCards = Map<String, dynamic>.from(
        (data['actionCards'] as Map? ?? {}).cast<String, dynamic>());

    // Track which players won a stockpile
    final winners = <String>{};

    for (var i = 0; i < stockpiles.length; i++) {
      final sp = stockpiles[i] as Map<String, dynamic>;
      final winnerId = sp['currentBidderId'] as String?;
      if (winnerId == null) continue;

      winners.add(winnerId);
      final bidAmount = sp['currentBid'] as int? ?? 0;

      // Deduct bid from winner's cash
      cash[winnerId] = (cash[winnerId] ?? 0) - bidAmount;

      // Collect all cards from the stockpile
      final allCards = [
        ...List<String>.from(sp['faceUpCards'] as List),
        ...List<String>.from(sp['faceDownCards'] as List),
      ];

      for (final card in allCards) {
        if (card.startsWith('stock_')) {
          final company = card.substring('stock_'.length);
          final myPortfolio = Map<String, int>.from(portfolios[winnerId] ?? {});
          myPortfolio[company] = (myPortfolio[company] ?? 0) + 1;
          portfolios[winnerId] = myPortfolio;
        } else if (card == 'fee_1000') {
          if ((cash[winnerId] ?? 0) >= 1000) {
            cash[winnerId] = (cash[winnerId] ?? 0) - 1000;
          } else {
            pendingFees[winnerId] = (pendingFees[winnerId] ?? 0) + 1000;
          }
        } else if (card == 'fee_2000') {
          if ((cash[winnerId] ?? 0) >= 2000) {
            cash[winnerId] = (cash[winnerId] ?? 0) - 2000;
          } else {
            pendingFees[winnerId] = (pendingFees[winnerId] ?? 0) + 2000;
          }
        } else if (card == 'action_boom' || card == 'action_bust') {
          final myCards =
              List<String>.from(actionCards[winnerId] as List? ?? []);
          myCards.add(card);
          actionCards[winnerId] = myCards;
        }
      }
    }

    // Players without a win get unclaimed stockpiles at $0
    final unclaimedStockpileIndices = <int>[];
    for (var i = 0; i < stockpiles.length; i++) {
      final sp = stockpiles[i] as Map<String, dynamic>;
      if (sp['currentBidderId'] == null) {
        unclaimedStockpileIndices.add(i);
      }
    }

    final playersWithoutWin =
        playerOrder.where((pid) => !winners.contains(pid)).toList();
    for (var i = 0;
        i < playersWithoutWin.length && i < unclaimedStockpileIndices.length;
        i++) {
      final pid = playersWithoutWin[i];
      final spIdx = unclaimedStockpileIndices[i];
      final sp = stockpiles[spIdx] as Map<String, dynamic>;
      final allCards = [
        ...List<String>.from(sp['faceUpCards'] as List),
        ...List<String>.from(sp['faceDownCards'] as List),
      ];
      for (final card in allCards) {
        if (card.startsWith('stock_')) {
          final company = card.substring('stock_'.length);
          final myPortfolio = Map<String, int>.from(portfolios[pid] ?? {});
          myPortfolio[company] = (myPortfolio[company] ?? 0) + 1;
          portfolios[pid] = myPortfolio;
        } else if (card == 'action_boom' || card == 'action_bust') {
          final myCards =
              List<String>.from(actionCards[pid] as List? ?? []);
          myCards.add(card);
          actionCards[pid] = myCards;
        }
        // Fee cards at $0 bid: no fee charged since they got it free
      }
    }

    data['cash'] = cash;
    data['portfolios'] = portfolios;
    data['splitPortfolios'] = splitPortfolios;
    data['pendingFees'] = pendingFees;
    data['actionCards'] = actionCards;

    return _transitionToPhase(state, data, playerOrder, 'action');
  }

  /// Applies all 6 forecasts for the current round, then either sets up the
  /// next round or ends the game.
  GameSessionState _resolveMovement(
    GameSessionState state,
    Map<String, dynamic> data,
    List<String> playerOrder,
  ) {
    final round = data['round'] as int;
    final totalRounds = data['totalRounds'] as int;
    final forecasts = data['forecasts'] as List;
    final roundForecasts = forecasts[round - 1] as List;

    var prices = Map<String, dynamic>.from(data['stockPrices'] as Map);
    var portfolios = _deepCopyPortfolioMap(data['portfolios'] as Map);
    var splitPortfolios =
        _deepCopyPortfolioMap(data['splitPortfolios'] as Map);
    var cash = Map<String, int>.from(_getCash(state.gameState!));

    final logEntries = <GameLogEntry>[];

    for (final forecastEntry in roundForecasts) {
      final fc = forecastEntry as Map;
      final company = fc['company'] as String;
      final change = fc['change'] as int;
      final currentPrice = prices[company] as int;

      if (change == _kDividendSentinel) {
        // Pay dividends
        for (final pid in playerOrder) {
          final normal = portfolios[pid]?[company] ?? 0;
          final split = splitPortfolios[pid]?[company] ?? 0;
          final dividend =
              (normal + split * 2) * _kDividendPayout;
          if (dividend > 0) {
            cash[pid] = (cash[pid] ?? 0) + dividend;
          }
        }
        logEntries.add(GameLogEntry(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          eventType: 'DIVIDEND',
          description: '${_kCompanyNames[company] ?? company} 배당 지급 💰',
        ));
      } else {
        final result = _applyPriceChange(
          company,
          currentPrice,
          change,
          portfolios,
          splitPortfolios,
          cash,
        );
        prices[company] = result['price'];
        // Apply split / bankruptcy consequences
        if (result['splitOccurred'] == true) {
          _applySplitConsequences(result, portfolios, splitPortfolios, cash);
        }
        if (result['bankruptcyOccurred'] == true) {
          _applyBankruptcyConsequences(result, portfolios, splitPortfolios);
        }
        logEntries.add(GameLogEntry(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          eventType: 'MOVEMENT',
          description:
              '${_kCompanyNames[company] ?? company} ${change >= 0 ? '+$change' : '$change'} → \$${prices[company]}',
        ));
      }
    }

    data['stockPrices'] = prices;
    data['portfolios'] = portfolios;
    data['splitPortfolios'] = splitPortfolios;
    data['cash'] = cash;

    var updatedState = state;
    for (final entry in logEntries) {
      updatedState = updatedState.addLog(entry);
    }

    if (round >= totalRounds) {
      // Game over: increment round past totalRounds to trigger checkGameEnd
      final newTurnState = state.turnState!.copyWith(
        round: round + 1,
      );
      final newGameState = state.gameState!.copyWith(data: data);
      return updatedState.copyWith(
        gameState: newGameState,
        turnState: newTurnState,
        version: updatedState.version + 1,
      );
    }

    // Set up next round
    final rng = seed != null ? Random(seed! + round) : Random();
    final newRound = round + 1;
    data['round'] = newRound;
    final allForecasts = data['forecasts'] as List;
    final newData =
        _setupRound(data, playerOrder, newRound, allForecasts, rng);

    final firstPlayer = playerOrder.first;
    final newTurnState = TurnState(
      round: newRound,
      turnIndex: 0,
      activePlayerId: firstPlayer,
      step: TurnStep.main,
      actionCountThisTurn: 0,
    );
    final newGameState = state.gameState!.copyWith(
      data: newData,
      activePlayerId: firstPlayer,
      turn: state.gameState!.turn + 1,
    );

    return updatedState.copyWith(
      gameState: newGameState,
      turnState: newTurnState,
      version: updatedState.version + 1,
    );
  }

  // ---------------------------------------------------------------------------
  // Stock price mechanics
  // ---------------------------------------------------------------------------

  /// Applies [change] to [currentPrice] for [company] and returns a result map:
  /// ```
  /// {
  ///   'price': int,                 // final price after mechanics
  ///   'splitOccurred': bool,
  ///   'bankruptcyOccurred': bool,
  ///   'company': String,
  /// }
  /// ```
  ///
  /// Split rule: if price would exceed 12, reset to 6, apply remaining change.
  /// Bankruptcy rule: if price would go below 1, reset to 5, wipe all shares.
  Map<String, dynamic> _applyPriceChange(
    String company,
    int currentPrice,
    int change,
    Map<String, Map<String, int>> portfolios,
    Map<String, Map<String, int>> splitPortfolios,
    Map<String, int> cash,
  ) {
    var price = currentPrice + change;
    var splitOccurred = false;
    var bankruptcyOccurred = false;

    if (price > _kSplitThreshold) {
      // Split: price crossed the split space (11+). Reset to 6, apply remaining.
      // e.g. price 9 + 4 = 13 → remaining = 13 - 11 = 2 → 6 + 2 = 8
      final remaining = price - (_kSplitThreshold + 1);
      price = _kSplitResetPrice + remaining;
      splitOccurred = true;
    } else if (price < 1) {
      price = _kBankruptcyResetPrice;
      bankruptcyOccurred = true;
    }

    return {
      'price': price,
      'splitOccurred': splitOccurred,
      'bankruptcyOccurred': bankruptcyOccurred,
      'company': company,
    };
  }

  /// Applies split consequences: normal shares → split portfolio; existing
  /// split shares → cash payout of \$10,000 per share.
  void _applySplitConsequences(
    Map<String, dynamic> result,
    Map<String, Map<String, int>> portfolios,
    Map<String, Map<String, int>> splitPortfolios,
    Map<String, int> cash,
  ) {
    final company = result['company'] as String;
    for (final pid in portfolios.keys.toList()) {
      final myPortfolio = Map<String, int>.from(portfolios[pid] ?? {});
      final mySplit = Map<String, int>.from(splitPortfolios[pid] ?? {});

      // Existing split shares → cash payout
      final existingSplit = mySplit[company] ?? 0;
      if (existingSplit > 0) {
        cash[pid] = (cash[pid] ?? 0) + existingSplit * 10000;
        mySplit.remove(company);
      }

      // Normal shares → move to split portfolio
      final normalShares = myPortfolio[company] ?? 0;
      if (normalShares > 0) {
        mySplit[company] = (mySplit[company] ?? 0) + normalShares;
        myPortfolio.remove(company);
      }

      portfolios[pid] = myPortfolio;
      splitPortfolios[pid] = mySplit;
    }
  }

  /// Wipes all shares of [company] from all portfolios on bankruptcy.
  void _applyBankruptcyConsequences(
    Map<String, dynamic> result,
    Map<String, Map<String, int>> portfolios,
    Map<String, Map<String, int>> splitPortfolios,
  ) {
    final company = result['company'] as String;
    for (final pid in portfolios.keys.toList()) {
      final myPortfolio = Map<String, int>.from(portfolios[pid] ?? {});
      myPortfolio.remove(company);
      portfolios[pid] = myPortfolio;
    }
    for (final pid in splitPortfolios.keys.toList()) {
      final mySplit = Map<String, int>.from(splitPortfolios[pid] ?? {});
      mySplit.remove(company);
      splitPortfolios[pid] = mySplit;
    }
  }

  // ---------------------------------------------------------------------------
  // Round setup
  // ---------------------------------------------------------------------------

  /// Initialises data for the start of [roundNumber].
  ///
  /// Deals 1 face-up market card to each stockpile, deals 2 supply cards to
  /// each player, sets up public and private forecasts, and resets phase tracking.
  Map<String, dynamic> _setupRound(
    Map<String, dynamic> data,
    List<String> playerOrder,
    int roundNumber,
    List<dynamic> allForecasts,
    Random rng,
  ) {
    final result = Map<String, dynamic>.from(data);
    final deck = List<String>.from(result['marketDeck'] as List);
    final playerCount = playerOrder.length;

    // Reset stockpiles
    final stockpiles = <Map<String, dynamic>>[];
    for (var i = 0; i < playerCount; i++) {
      final faceUpCard = deck.isNotEmpty ? deck.removeAt(0) : 'stock_aauto';
      stockpiles.add({
        'faceUpCards': [faceUpCard],
        'faceDownCards': <String>[],
        'currentBid': 0,
        'currentBidderId': null,
      });
    }

    // Deal 2 supply cards to each player
    final supplyHands = <String, List<String>>{};
    for (final pid in playerOrder) {
      final hand = <String>[];
      for (var i = 0; i < 2; i++) {
        if (deck.isNotEmpty) hand.add(deck.removeAt(0));
      }
      supplyHands[pid] = hand;
    }

    // Set up forecasts for this round
    final roundForecasts = allForecasts[roundNumber - 1] as List;
    // Assign public, private, and hidden
    // Shuffle to determine which index is public and which are private
    final indices = List.generate(6, (i) => i)..shuffle(rng);
    final publicIndex = indices[0];
    final privateIndices = indices.sublist(1, 1 + playerCount);

    final publicForecast =
        Map<String, dynamic>.from((roundForecasts[publicIndex] as Map).cast<String, dynamic>());
    final privateForecastByPlayer = <String, dynamic>{};
    for (var i = 0; i < playerCount; i++) {
      final fc = roundForecasts[privateIndices[i]] as Map;
      privateForecastByPlayer[playerOrder[i]] =
          Map<String, dynamic>.from(fc.cast<String, dynamic>());
    }

    result['marketDeck'] = deck;
    result['stockpiles'] = stockpiles;
    result['supplyHands'] = supplyHands;
    result['supplyPlaced'] = <String, dynamic>{
      for (final pid in playerOrder) pid: {'faceUp': false, 'faceDown': false},
    };
    result['demandBids'] = <String, dynamic>{};
    result['demandRound'] = 1;
    result['outbidPlayers'] = <String>[];
    result['rebidActedPlayers'] = <String>[];
    result['demandPassedPlayers'] = <String>[];
    result['actionCards'] = <String, dynamic>{
      for (final pid in playerOrder)
        pid: List<String>.from(
            (result['actionCards'] as Map?)?[pid] as List? ?? []),
    };
    result['phaseActedPlayers'] = <String>[];
    result['phase'] = 'supply';
    result['publicForecast'] = publicForecast;
    result['privateForecastByPlayer'] = privateForecastByPlayer;

    return result;
  }

  // ---------------------------------------------------------------------------
  // Forecast generation
  // ---------------------------------------------------------------------------

  /// Pre-generates all forecasts for [totalRounds] rounds.
  ///
  /// Each round has 6 pairs: (company, change).  Changes range from -3 to +4
  /// with one slot per company.  Each company appears exactly once per round.
  /// [_kDividendSentinel] (-99) represents a dividend event.
  List<List<Map<String, dynamic>>> _generateAllForecasts(
    int totalRounds,
    Random rng,
  ) {
    // Possible forecast values (integers from -3 to +4, plus dividend)
    const possibleChanges = [-3, -2, -1, 0, 1, 2, 3, 4, _kDividendSentinel];

    final allForecasts = <List<Map<String, dynamic>>>[];
    for (var r = 0; r < totalRounds; r++) {
      final companies = List<String>.from(_kCompanies)..shuffle(rng);
      final changes = List<int>.from(possibleChanges..toList())..shuffle(rng);
      // Ensure we have at least 6 changes
      while (changes.length < 6) {
        changes.add(possibleChanges[rng.nextInt(possibleChanges.length)]);
      }

      final roundForecasts = <Map<String, dynamic>>[];
      for (var i = 0; i < 6; i++) {
        roundForecasts.add({
          'company': companies[i],
          'change': changes[i],
        });
      }
      allForecasts.add(roundForecasts);
    }
    return allForecasts;
  }

  // ---------------------------------------------------------------------------
  // Victory condition helpers
  // ---------------------------------------------------------------------------

  Map<String, int> _computeMajorityBonuses(
    List<String> playerOrder,
    Map<String, Map<String, int>> portfolios,
    Map<String, Map<String, int>> splitPortfolios,
  ) {
    final bonuses = <String, int>{for (final pid in playerOrder) pid: 0};

    for (final company in _kCompanies) {
      // Count shares for each player (split counts double)
      final shareCounts = <String, int>{};
      for (final pid in playerOrder) {
        final normal = portfolios[pid]?[company] ?? 0;
        final split = splitPortfolios[pid]?[company] ?? 0;
        shareCounts[pid] = normal + split * 2;
      }

      final maxShares =
          shareCounts.values.fold(0, (prev, s) => s > prev ? s : prev);
      if (maxShares == 0) continue;

      final leaders =
          shareCounts.entries.where((e) => e.value == maxShares).toList();

      if (leaders.length == 1) {
        bonuses[leaders.first.key] =
            (bonuses[leaders.first.key] ?? 0) + _kMajorityBonus;
      } else {
        for (final leader in leaders) {
          bonuses[leader.key] =
              (bonuses[leader.key] ?? 0) + _kTiedMajorityBonus;
        }
      }
    }

    return bonuses;
  }

  // ---------------------------------------------------------------------------
  // Market deck builder
  // ---------------------------------------------------------------------------

  List<String> _buildMarketDeck(Random rng) {
    final deck = <String>[];

    // Stock cards
    for (final company in _kCompanies) {
      for (var i = 0; i < _kStockCardsPerCompany; i++) {
        deck.add('stock_$company');
      }
    }

    // Trading fee cards
    for (var i = 0; i < _kFee1000Count; i++) deck.add('fee_1000');
    for (var i = 0; i < _kFee2000Count; i++) deck.add('fee_2000');

    // Action cards
    for (var i = 0; i < _kActionBoomCount; i++) deck.add('action_boom');
    for (var i = 0; i < _kActionBustCount; i++) deck.add('action_bust');

    deck.shuffle(rng);
    return deck;
  }

  // ---------------------------------------------------------------------------
  // Data access helpers (all return copies)
  // ---------------------------------------------------------------------------

  Map<String, int> _getCash(GameState gameState) {
    final raw = gameState.data['cash'] as Map;
    return raw.map((k, v) => MapEntry(k as String, v as int));
  }

  Map<String, int> _getPrices(GameState gameState) {
    final raw = gameState.data['stockPrices'] as Map;
    return raw.map((k, v) => MapEntry(k as String, v as int));
  }

  Map<String, Map<String, int>> _getPortfolios(GameState gameState) {
    return _deepCopyPortfolioMap(gameState.data['portfolios'] as Map);
  }

  Map<String, Map<String, int>> _getSplitPortfolios(GameState gameState) {
    return _deepCopyPortfolioMap(gameState.data['splitPortfolios'] as Map);
  }

  List<Map<String, dynamic>> _getStockpiles(GameState gameState) {
    return _copyStockpiles(gameState.data['stockpiles'] as List);
  }

  // ---------------------------------------------------------------------------
  // Deep copy utilities
  // ---------------------------------------------------------------------------

  Map<String, Map<String, int>> _deepCopyPortfolioMap(Map raw) {
    return raw.map(
      (k, v) => MapEntry(k as String, Map<String, int>.from(v as Map)),
    );
  }

  Map<String, List<String>> _deepCopyStringListMap(Map raw) {
    return raw.map(
      (k, v) => MapEntry(k as String, List<String>.from(v as List)),
    );
  }

  Map<String, dynamic> _deepCopyBoolMap(Map raw) {
    return raw.map((k, v) => MapEntry(k as String, v));
  }

  List<Map<String, dynamic>> _copyStockpiles(List raw) {
    return raw.map((sp) => Map<String, dynamic>.from(sp as Map)).toList();
  }
}
