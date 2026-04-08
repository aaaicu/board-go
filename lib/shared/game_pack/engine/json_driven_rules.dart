import 'dart:math';

import '../../game_session/game_log_entry.dart';
import '../../game_session/game_session_state.dart';
import '../../game_session/session_phase.dart';
import '../../game_session/turn_state.dart';
import '../../game_session/turn_step.dart';
import '../../messages/node_message.dart';
import '../game_pack_rules.dart';
import '../game_state.dart';
import '../player_action.dart';
import '../views/allowed_action.dart';
import '../views/board_view.dart';
import '../views/player_view.dart';
import 'dsl_effect.dart';
import 'dsl_expression.dart';
import 'pack_definition.dart';

/// A [GamePackRules] implementation driven entirely by a [PackDefinition].
///
/// Instead of compiled Dart code, the game logic is expressed as JSON DSL
/// (conditions, effects, view templates) and interpreted at runtime.
///
/// This enables:
///   - Game packs transmitted from server to client as JSON
///   - Hot-reloading of game rules without app updates
///   - BattleNet-style distribution: GameBoard hosts compiled engine,
///     GameNode renders whatever the server sends
class JsonDrivenRules implements GamePackRules {
  final PackDefinition definition;
  final Random? _rng;

  JsonDrivenRules({required this.definition, Random? rng}) : _rng = rng;

  @override
  String get packId => definition.packId;

  @override
  int get minPlayers => definition.minPlayers;

  @override
  int get maxPlayers => definition.maxPlayers;

  @override
  String get boardOrientation => definition.boardOrientation;

  @override
  String get nodeOrientation => definition.nodeOrientation;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  GameSessionState createInitialGameState(GameSessionState sessionState) {
    final playerOrder = List<String>.from(sessionState.playerOrder);
    final rng = _rng ?? Random();

    final ctx = DslContext(
      data: {
        'playerCount': playerOrder.length,
        'sessionId': sessionState.sessionId,
      },
      playerOrder: playerOrder,
      rng: rng,
    );

    // Evaluate the setup block to get initial game data
    final setupDef = definition.setup;
    final initialData = <String, dynamic>{};

    // Process setup instructions
    if (setupDef.containsKey('initialData')) {
      final template = setupDef['initialData'] as Map<String, dynamic>;
      for (final entry in template.entries) {
        initialData[entry.key] = _deepCopy(evalExpr(entry.value, ctx));
      }
    }

    // Run setup effects if any
    if (setupDef.containsKey('effects')) {
      final setupCtx = DslContext(
        data: initialData,
        playerOrder: playerOrder,
        rng: rng,
      );
      final result = executeEffects(
        setupDef['effects'] as List,
        setupCtx,
      );
      initialData.addAll(result.data);
    }

    // Determine the first active player
    final activePlayerId =
        initialData['activePlayerId'] as String? ?? playerOrder.first;

    final gameState = GameState(
      gameId: sessionState.sessionId,
      turn: initialData['turn'] as int? ?? 0,
      activePlayerId: activePlayerId,
      data: initialData,
    );

    final turnState = TurnState(
      round: initialData['round'] as int? ?? 1,
      turnIndex: playerOrder.indexOf(activePlayerId).clamp(0, playerOrder.length - 1),
      activePlayerId: activePlayerId,
      step: TurnStep.main,
      actionCountThisTurn: 0,
    );

    var newState = sessionState.copyWith(
      phase: SessionPhase.inGame,
      gameState: gameState,
      turnState: turnState,
      playerOrder: playerOrder,
      version: sessionState.version + 1,
    );

    // Run setup log entries
    if (setupDef.containsKey('log')) {
      final logEntries = setupDef['log'] as List;
      for (final entry in logEntries) {
        final logCtx = DslContext(
          data: initialData,
          playerOrder: playerOrder,
          rng: rng,
        );
        final eventType = evalExpr(entry['eventType'] ?? 'system', logCtx).toString();
        final description = evalExpr(entry['description'], logCtx).toString();
        newState = newState.addLog(GameLogEntry(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          eventType: eventType,
          description: description,
        ));
      }
    }

    return newState;
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
    if (state.gameState == null) return const [];

    final data = state.gameState!.data;
    final phase = data['phase'] as String?;
    if (phase == null) return const [];

    final phaseDef = definition.phases[phase];
    if (phaseDef == null) return const [];

    // Default active-player gate: unless the phase opts out.
    if (phaseDef.activePlayerOnly) {
      final turnState = state.turnState;
      if (turnState == null) return const [];
      if (turnState.activePlayerId != playerId) return const [];
    }

    final rng = _rng ?? Random();
    final actions = <AllowedAction>[];

    for (final entry in phaseDef.actions.entries) {
      final actionType = entry.key;
      final actionDef = entry.value;

      final ctx = DslContext(
        data: data,
        playerOrder: state.playerOrder,
        playerId: playerId,
        rng: rng,
      );

      // Check allowedWhen condition
      if (actionDef.allowedWhen != null) {
        final allowed = evalExpr(actionDef.allowedWhen, ctx);
        if (!_toBool(allowed)) continue;
      }

      // Generate action instances
      if (actionDef.generate != null) {
        final gen = actionDef.generate;
        if (gen is Map<String, dynamic> && gen.containsKey('forEach')) {
          // Declarative forEach-style generation:
          // { "forEach": <listExpr>, "as": "$var",
          //   "actionType": <expr>, "label": <expr>,
          //   "params": { "key": <expr>, ... } }
          final list = evalExpr(gen['forEach'], ctx);
          if (list is List) {
            final asVar = gen['as'] as String? ?? r'$item';
            for (final item in list) {
              final inner = ctx.withLocals({asVar: item});
              final genType = gen.containsKey('actionType')
                  ? evalExpr(gen['actionType'], inner).toString()
                  : actionType;
              final genLabel = gen.containsKey('label')
                  ? evalExpr(gen['label'], inner).toString()
                  : '$genType $item';
              final genParams = <String, dynamic>{};
              if (gen.containsKey('params')) {
                final paramsDef = gen['params'] as Map<String, dynamic>;
                for (final pe in paramsDef.entries) {
                  genParams[pe.key] = evalExpr(pe.value, inner);
                }
              }
              actions.add(AllowedAction(
                actionType: genType,
                label: genLabel,
                params: genParams,
              ));
            }
          }
        } else {
          // Direct expression that returns a list of action maps
          final generated = evalExpr(gen, ctx);
          if (generated is List) {
            for (final item in generated) {
              if (item is Map<String, dynamic>) {
                actions.add(AllowedAction(
                  actionType: item['actionType'] as String? ?? actionType,
                  label: item['label']?.toString() ?? actionType,
                  params: Map<String, dynamic>.from(
                      item['params'] as Map? ?? {}),
                ));
              }
            }
          }
        }
      } else {
        // Simple action: single instance
        final label = actionDef.label != null
            ? evalExpr(actionDef.label, ctx).toString()
            : actionType;
        actions.add(AllowedAction(
          actionType: actionType,
          label: label,
          params: const {},
        ));
      }
    }

    return actions;
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
    final data = state.gameState!.data;
    final phase = data['phase'] as String?;
    if (phase == null) return state;

    final phaseDef = definition.phases[phase];
    if (phaseDef == null) return state;

    final actionDef = phaseDef.actions[action.type];
    if (actionDef == null) return state;

    final rng = _rng ?? Random();
    final ctx = DslContext(
      data: Map<String, dynamic>.from(data),
      playerOrder: state.playerOrder,
      playerId: playerId,
      actionData: action.data,
      rng: rng,
    );

    final result = executeEffects(actionDef.effects, ctx);

    // Build updated game state
    final newGameState = state.gameState!.copyWith(
      data: result.data,
      activePlayerId: result.activePlayerOverride ?? state.gameState!.activePlayerId,
    );

    // Build updated turn state
    TurnState? newTurnState = state.turnState;
    if (result.turnUpdate != null) {
      final tu = result.turnUpdate!;
      newTurnState = newTurnState?.copyWith(
        round: tu.round,
        turnIndex: tu.turnIndex,
        activePlayerId: tu.activePlayerId,
        step: tu.step != null ? _parseTurnStep(tu.step!) : null,
        actionCountThisTurn: tu.actionCountThisTurn,
      );
    } else if (newTurnState != null) {
      // Increment action count by default
      newTurnState = newTurnState.copyWith(
        actionCountThisTurn: newTurnState.actionCountThisTurn + 1,
      );
    }

    // Apply active player override to turn state too
    if (result.activePlayerOverride != null && newTurnState != null) {
      newTurnState = newTurnState.copyWith(
        activePlayerId: result.activePlayerOverride,
      );
    }

    var newState = state.copyWith(
      gameState: newGameState,
      turnState: newTurnState,
      version: state.version + 1,
    );

    // Append log entries
    for (final log in result.logs) {
      newState = newState.addLog(GameLogEntry(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        eventType: log.eventType,
        description: log.description,
      ));
    }

    // Check for phase change and run onEnter effects
    final newPhase = result.data['phase'] as String?;
    if (newPhase != null && newPhase != phase) {
      final newPhaseDef = definition.phases[newPhase];
      if (newPhaseDef?.onEnter != null) {
        final onEnterCtx = DslContext(
          data: Map<String, dynamic>.from(result.data),
          playerOrder: state.playerOrder,
          playerId: playerId,
          rng: rng,
        );
        final onEnterResult = executeEffects(newPhaseDef!.onEnter!, onEnterCtx);

        final updatedGameState = newState.gameState!.copyWith(
          data: onEnterResult.data,
          activePlayerId: onEnterResult.activePlayerOverride ??
              newState.gameState!.activePlayerId,
        );

        newState = newState.copyWith(gameState: updatedGameState);

        for (final log in onEnterResult.logs) {
          newState = newState.addLog(GameLogEntry(
            timestamp: DateTime.now().millisecondsSinceEpoch,
            eventType: log.eventType,
            description: log.description,
          ));
        }

        if (onEnterResult.turnUpdate != null) {
          final tu = onEnterResult.turnUpdate!;
          newState = newState.copyWith(
            turnState: newState.turnState?.copyWith(
              round: tu.round,
              turnIndex: tu.turnIndex,
              activePlayerId: tu.activePlayerId,
              step: tu.step != null ? _parseTurnStep(tu.step!) : null,
              actionCountThisTurn: tu.actionCountThisTurn,
            ),
          );
        }
      }
    }

    return newState;
  }

  // ---------------------------------------------------------------------------
  // End condition
  // ---------------------------------------------------------------------------

  @override
  ({bool ended, List<String> winnerIds}) checkGameEnd(GameSessionState state) {
    if (state.gameState == null) return (ended: false, winnerIds: const []);

    final data = state.gameState!.data;
    final rng = _rng ?? Random();
    final ctx = DslContext(
      data: data,
      playerOrder: state.playerOrder,
      rng: rng,
    );

    final endDef = definition.gameEnd;

    // Check 'ended' condition
    final endedExpr = endDef['condition'];
    if (endedExpr == null) return (ended: false, winnerIds: const []);

    final ended = _toBool(evalExpr(endedExpr, ctx));
    if (!ended) return (ended: false, winnerIds: const []);

    // Determine winners
    final winnersExpr = endDef['winners'];
    if (winnersExpr == null) return (ended: true, winnerIds: const []);

    final winners = evalExpr(winnersExpr, ctx);
    if (winners is List) {
      return (
        ended: true,
        winnerIds: winners.map((e) => e.toString()).toList()
      );
    }

    return (ended: true, winnerIds: const []);
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

    final data = gameState.data;
    final rng = _rng ?? Random();
    final ctx = DslContext(
      data: data,
      playerOrder: state.playerOrder,
      rng: rng,
    );

    final viewDef = definition.boardView;

    // Build board view data
    final viewData = <String, dynamic>{};
    viewData['packId'] = packId;

    if (viewDef.containsKey('data')) {
      final dataDef = viewDef['data'] as Map<String, dynamic>;
      for (final entry in dataDef.entries) {
        viewData[entry.key] = evalExpr(entry.value, ctx);
      }
    }

    // Extract standard fields
    final scores = _extractScores(viewDef, ctx);
    final deckRemaining = viewDef.containsKey('deckRemaining')
        ? (evalExpr(viewDef['deckRemaining'], ctx) as num?)?.toInt() ?? 0
        : 0;
    final discardPile = viewDef.containsKey('discardPile')
        ? List<String>.from(evalExpr(viewDef['discardPile'], ctx) as List? ?? [])
        : <String>[];

    final maxLog = viewDef['maxRecentLog'] as int? ?? 10;
    final recentLog = state.log.length > maxLog
        ? state.log.sublist(state.log.length - maxLog)
        : List<GameLogEntry>.from(state.log);

    // Add player info with nicknames
    if (viewDef['includePlayerInfo'] == true) {
      final playerInfo = <String, Map<String, dynamic>>{};
      for (final pid in state.playerOrder) {
        playerInfo[pid] = {
          'nickname': state.players[pid]?.nickname ?? pid,
        };
      }
      viewData['playerInfo'] = playerInfo;
    }

    return BoardView(
      phase: state.phase,
      scores: scores,
      turnState: state.turnState,
      deckRemaining: deckRemaining,
      discardPile: discardPile,
      recentLog: recentLog,
      version: state.version,
      data: viewData,
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
        allowedActions: const [],
        version: state.version,
      );
    }

    final data = gameState.data;
    final rng = _rng ?? Random();
    final ctx = DslContext(
      data: data,
      playerOrder: state.playerOrder,
      playerId: playerId,
      rng: rng,
    );

    final viewDef = definition.playerView;

    // Build private view data
    final viewData = <String, dynamic>{};
    viewData['packId'] = packId;

    if (viewDef.containsKey('data')) {
      final dataDef = viewDef['data'] as Map<String, dynamic>;
      for (final entry in dataDef.entries) {
        viewData[entry.key] = evalExpr(entry.value, ctx);
      }
    }

    // Conditional data blocks
    if (viewDef.containsKey('conditionalData')) {
      final conditionals = viewDef['conditionalData'] as List;
      for (final block in conditionals) {
        if (block is Map<String, dynamic>) {
          final condition = block['when'];
          if (condition == null || _toBool(evalExpr(condition, ctx))) {
            final fields = block['data'] as Map<String, dynamic>? ?? {};
            for (final entry in fields.entries) {
              viewData[entry.key] = evalExpr(entry.value, ctx);
            }
          }
        }
      }
    }

    // Add player info with nicknames
    if (viewDef['includePlayerInfo'] == true) {
      final playerInfo = <String, Map<String, dynamic>>{};
      for (final pid in state.playerOrder) {
        playerInfo[pid] = {
          'nickname': state.players[pid]?.nickname ?? pid,
        };
      }
      viewData['playerInfo'] = playerInfo;
    }

    // Extract hand
    final hand = viewDef.containsKey('hand')
        ? List<String>.from(evalExpr(viewDef['hand'], ctx) as List? ?? [])
        : <String>[];

    // Extract scores
    final scores = _extractScores(viewDef, ctx);

    return PlayerView(
      phase: state.phase,
      playerId: playerId,
      hand: hand,
      scores: scores,
      turnState: state.turnState,
      allowedActions: getAllowedActions(state, playerId),
      version: state.version,
      data: viewData,
    );
  }

  // ---------------------------------------------------------------------------
  // Node message hook
  // ---------------------------------------------------------------------------

  @override
  NodeMessage? onNodeMessage(NodeMessage msg, GameSessionState state) {
    final msgDef = definition.nodeMessages;
    if (msgDef == null) return msg; // pass-through by default

    final rng = _rng ?? Random();
    final ctx = DslContext(
      data: state.gameState?.data ?? {},
      playerOrder: state.playerOrder,
      playerId: msg.fromPlayerId,
      actionData: {
        'type': msg.type,
        'payload': msg.payload,
        'toPlayerId': msg.toPlayerId,
      },
      rng: rng,
    );

    // Check allowed types
    if (msgDef.containsKey('allowedTypes')) {
      final allowed = evalExpr(msgDef['allowedTypes'], ctx);
      if (allowed is List && !allowed.contains(msg.type)) return null;
    }

    // Check per-type validation
    if (msgDef.containsKey('validate')) {
      final validators = msgDef['validate'] as Map<String, dynamic>;
      final validator = validators[msg.type];
      if (validator != null) {
        final valid = _toBool(evalExpr(validator, ctx));
        if (!valid) return null;
      }
    }

    return msg;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Map<String, int> _extractScores(
      Map<String, dynamic> viewDef, DslContext ctx) {
    if (!viewDef.containsKey('scores')) return const {};
    final scoresExpr = evalExpr(viewDef['scores'], ctx);
    if (scoresExpr is Map) {
      return scoresExpr
          .map((k, v) => MapEntry(k.toString(), v is num ? v.toInt() : 0));
    }
    return const {};
  }

  TurnStep _parseTurnStep(String step) => switch (step.toUpperCase()) {
        'START' => TurnStep.start,
        'MAIN' => TurnStep.main,
        'END' => TurnStep.end,
        _ => TurnStep.main,
      };

  bool _toBool(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v.isNotEmpty;
    if (v is List) return v.isNotEmpty;
    if (v is Map) return v.isNotEmpty;
    return true;
  }

  /// Deep-copy a value so const/unmodifiable collections become mutable.
  static dynamic _deepCopy(dynamic value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k, _deepCopy(v)));
    }
    if (value is List) {
      return value.map(_deepCopy).toList();
    }
    return value;
  }
}
