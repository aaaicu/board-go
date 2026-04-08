import 'dart:math';

import 'dsl_expression.dart';

/// Executes a list of DSL effect statements against a mutable data map.
///
/// Effects are JSON objects that describe state mutations. The effect executor
/// interprets these and applies them to [DslContext.data] (which points to
/// `gameState.data`).
///
/// Supported effects:
///   - `set`:       Set a value at a path
///   - `increment`: Add a number to a value at a path
///   - `append`:    Append a value to a list at a path
///   - `remove`:    Remove an item from a list at a path
///   - `insert`:    Insert an item into a list at a specific index
///   - `merge`:     Merge a map into a map at a path
///   - `delete`:    Delete a key from a map at a path
///   - `if`:        Conditional branching
///   - `forEach`:   Loop over a list, executing effects per item
///   - `let`:       Define local variables for a block of effects
///   - `log`:       Append a log entry (collected separately)
///   - `setPhase`:  Shorthand for setting the 'phase' key
///   - `advanceTurn`: Move to next player in turn order
///   - `shuffleDeck`: Shuffle a list at a path
///   - `drawCards`:  Move N items from one list to another
///   - `dealCards`:  Deal cards from deck to players' hands
///   - `returnCards`: Move all items from one list to another
///   - `setActivePlayer`: Change the active player
///   - `setTurn`:   Set turn state fields
///   - `noop`:      Do nothing (useful for conditional branches)

class EffectResult {
  final Map<String, dynamic> data;
  final List<LogEffect> logs;
  final TurnUpdate? turnUpdate;
  final String? activePlayerOverride;

  EffectResult({
    required this.data,
    this.logs = const [],
    this.turnUpdate,
    this.activePlayerOverride,
  });
}

class LogEffect {
  final String eventType;
  final String description;

  const LogEffect({required this.eventType, required this.description});
}

/// Turn state updates collected during effect execution.
class TurnUpdate {
  final int? round;
  final int? turnIndex;
  final String? activePlayerId;
  final String? step; // 'START', 'MAIN', 'END'
  final int? actionCountThisTurn;

  const TurnUpdate({
    this.round,
    this.turnIndex,
    this.activePlayerId,
    this.step,
    this.actionCountThisTurn,
  });

  TurnUpdate merge(TurnUpdate other) => TurnUpdate(
        round: other.round ?? round,
        turnIndex: other.turnIndex ?? turnIndex,
        activePlayerId: other.activePlayerId ?? activePlayerId,
        step: other.step ?? step,
        actionCountThisTurn: other.actionCountThisTurn ?? actionCountThisTurn,
      );
}

/// Mutable context for effect execution.
///
/// Wraps a [DslContext] and collects side-effects (logs, turn updates).
class _EffectCtx {
  final DslContext dsl;
  final Map<String, dynamic> data; // mutable reference to gameState.data
  final List<LogEffect> logs = [];
  TurnUpdate? turnUpdate;
  String? activePlayerOverride;

  _EffectCtx({required this.dsl, required this.data});

  _EffectCtx withLocals(Map<String, dynamic> extra) => _EffectCtx(
        dsl: dsl.withLocals(extra),
        data: data,
      )
        ..logs.addAll([]) // start fresh for sub-scope, merged back by caller
        ..turnUpdate = turnUpdate
        ..activePlayerOverride = activePlayerOverride;

  void addLog(LogEffect log) => logs.add(log);

  void updateTurn(TurnUpdate update) {
    turnUpdate = turnUpdate?.merge(update) ?? update;
  }
}

/// Execute a list of effects and return the result.
///
/// [effects] is a list of effect JSON objects.
/// [ctx] provides the evaluation context (data, playerOrder, playerId, etc).
///
/// Returns an [EffectResult] with the mutated data, collected logs, and
/// any turn state updates.
EffectResult executeEffects(
  List<dynamic> effects,
  DslContext ctx,
) {
  final data = _deepCopyMap(ctx.data);
  // Create a new DslContext pointing to mutable data
  final mutableCtx = DslContext(
    data: data,
    playerOrder: ctx.playerOrder,
    playerId: ctx.playerId,
    actionData: ctx.actionData,
    locals: ctx.locals,
    rng: ctx.rng,
  );
  final ectx = _EffectCtx(dsl: mutableCtx, data: data);

  for (final effect in effects) {
    _execEffect(effect, ectx);
  }

  return EffectResult(
    data: data,
    logs: ectx.logs,
    turnUpdate: ectx.turnUpdate,
    activePlayerOverride: ectx.activePlayerOverride,
  );
}

void _execEffect(dynamic effect, _EffectCtx ctx) {
  if (effect is! Map<String, dynamic>) return;

  // Check for "noop"
  if (effect.containsKey('noop')) return;

  // --- set ---
  if (effect.containsKey('set')) {
    final path = effect['path'] as String;
    final value = _deepCopyValue(evalExpr(effect['set'], ctx.dsl));
    _setAtPath(ctx.data, path, value, ctx.dsl);
    _syncDsl(ctx);
    return;
  }

  // --- increment ---
  if (effect.containsKey('increment')) {
    final path = effect['increment'] as String;
    final amount = evalExpr(effect['by'] ?? 1, ctx.dsl);
    final current = _getAtPath(ctx.data, path, ctx.dsl);
    final num currentNum = current is num ? current : 0;
    final num amountNum = amount is num ? amount : 0;
    _setAtPath(ctx.data, path, currentNum + amountNum, ctx.dsl);
    _syncDsl(ctx);
    return;
  }

  // --- append ---
  if (effect.containsKey('append')) {
    final path = effect['append'] as String;
    final value = _deepCopyValue(evalExpr(effect['value'], ctx.dsl));
    final list = _getAtPath(ctx.data, path, ctx.dsl);
    if (list is List) {
      list.add(value);
    } else {
      _setAtPath(ctx.data, path, [value], ctx.dsl);
    }
    _syncDsl(ctx);
    return;
  }

  // --- remove ---
  if (effect.containsKey('remove')) {
    final path = effect['remove'] as String;
    final value = evalExpr(effect['value'], ctx.dsl);
    final list = _getAtPath(ctx.data, path, ctx.dsl);
    if (list is List) {
      list.remove(value);
    }
    _syncDsl(ctx);
    return;
  }

  // --- insert ---
  if (effect.containsKey('insert')) {
    final path = effect['insert'] as String;
    final value = evalExpr(effect['value'], ctx.dsl);
    final index = evalExpr(effect['at'] ?? 0, ctx.dsl) as int;
    final list = _getAtPath(ctx.data, path, ctx.dsl);
    if (list is List) {
      list.insert(index.clamp(0, list.length), value);
    } else {
      _setAtPath(ctx.data, path, [value], ctx.dsl);
    }
    _syncDsl(ctx);
    return;
  }

  // --- merge ---
  if (effect.containsKey('merge')) {
    final path = effect['merge'] as String;
    final value = evalExpr(effect['value'], ctx.dsl);
    if (value is Map) {
      final existing = _getAtPath(ctx.data, path, ctx.dsl);
      if (existing is Map) {
        for (final e in value.entries) {
          existing[e.key.toString()] = e.value;
        }
      } else {
        _setAtPath(ctx.data, path, Map<String, dynamic>.from(value), ctx.dsl);
      }
    }
    _syncDsl(ctx);
    return;
  }

  // --- delete ---
  if (effect.containsKey('delete')) {
    final path = effect['delete'] as String;
    final parts = path.split('.');
    if (parts.length == 1) {
      ctx.data.remove(parts[0]);
    } else {
      final parentPath = parts.sublist(0, parts.length - 1).join('.');
      final parent = _getAtPath(ctx.data, parentPath, ctx.dsl);
      if (parent is Map) {
        parent.remove(parts.last);
      }
    }
    _syncDsl(ctx);
    return;
  }

  // --- if ---
  if (effect.containsKey('if')) {
    final condition = evalExpr(effect['if'], ctx.dsl);
    if (_toBool(condition)) {
      final thenEffects = effect['then'] as List? ?? [];
      for (final e in thenEffects) {
        _execEffect(e, ctx);
      }
    } else if (effect.containsKey('else')) {
      final elseEffects = effect['else'] as List? ?? [];
      for (final e in elseEffects) {
        _execEffect(e, ctx);
      }
    }
    return;
  }

  // --- forEach ---
  if (effect.containsKey('forEach')) {
    final listExpr = effect['forEach'];
    final list = evalExpr(listExpr, ctx.dsl);
    if (list is! List) return;

    final asVar = effect['as'] as String? ?? r'$item';
    final indexVar = effect['index'] as String?;
    final body = effect['do'] as List? ?? [];

    for (var i = 0; i < list.length; i++) {
      final locals = <String, dynamic>{asVar: list[i]};
      if (indexVar != null) locals[indexVar] = i;
      final innerCtx = _EffectCtx(
        dsl: ctx.dsl.withLocals(locals),
        data: ctx.data,
      );
      for (final e in body) {
        _execEffect(e, innerCtx);
      }
      ctx.logs.addAll(innerCtx.logs);
      if (innerCtx.turnUpdate != null) ctx.updateTurn(innerCtx.turnUpdate!);
      if (innerCtx.activePlayerOverride != null) {
        ctx.activePlayerOverride = innerCtx.activePlayerOverride;
      }
    }
    return;
  }

  // --- let ---
  if (effect.containsKey('let')) {
    final bindings = effect['let'] as Map<String, dynamic>;
    final body = effect['do'] as List? ?? effect['in'] as List? ?? [];
    final locals = <String, dynamic>{};
    for (final entry in bindings.entries) {
      locals[entry.key] = evalExpr(entry.value, ctx.dsl.withLocals(locals));
    }
    final innerCtx = _EffectCtx(
      dsl: ctx.dsl.withLocals(locals),
      data: ctx.data,
    );
    for (final e in body) {
      _execEffect(e, innerCtx);
    }
    ctx.logs.addAll(innerCtx.logs);
    if (innerCtx.turnUpdate != null) ctx.updateTurn(innerCtx.turnUpdate!);
    if (innerCtx.activePlayerOverride != null) {
      ctx.activePlayerOverride = innerCtx.activePlayerOverride;
    }
    return;
  }

  // --- log ---
  if (effect.containsKey('log')) {
    final eventType = evalExpr(effect['log'], ctx.dsl).toString();
    final description =
        evalExpr(effect['message'] ?? '', ctx.dsl).toString();
    ctx.addLog(LogEffect(eventType: eventType, description: description));
    return;
  }

  // --- setPhase ---
  if (effect.containsKey('setPhase')) {
    final phase = evalExpr(effect['setPhase'], ctx.dsl).toString();
    ctx.data['phase'] = phase;
    _syncDsl(ctx);
    return;
  }

  // --- setActivePlayer ---
  if (effect.containsKey('setActivePlayer')) {
    final playerId = evalExpr(effect['setActivePlayer'], ctx.dsl).toString();
    ctx.activePlayerOverride = playerId;
    ctx.data['activePlayerId'] = playerId;
    _syncDsl(ctx);
    return;
  }

  // --- advanceTurn ---
  if (effect.containsKey('advanceTurn')) {
    final cfg = effect['advanceTurn'];
    if (cfg is Map<String, dynamic>) {
      final playerOrder = ctx.dsl.playerOrder;
      final currentIndex =
          evalExpr(cfg['fromIndex'], ctx.dsl) as int? ??
          playerOrder.indexOf(ctx.dsl.playerId ?? '');
      final skipPlayers =
          List<String>.from(evalExpr(cfg['skip'] ?? [], ctx.dsl) as List? ?? []);

      var nextIndex = (currentIndex + 1) % playerOrder.length;
      var attempts = 0;
      while (skipPlayers.contains(playerOrder[nextIndex]) &&
          attempts < playerOrder.length) {
        nextIndex = (nextIndex + 1) % playerOrder.length;
        attempts++;
      }

      final isNewRound = cfg.containsKey('newRoundWhen')
          ? _toBool(evalExpr(cfg['newRoundWhen'], ctx.dsl.withLocals({
              r'$nextIndex': nextIndex,
              r'$currentIndex': currentIndex,
            })))
          : nextIndex <= currentIndex;

      ctx.updateTurn(TurnUpdate(
        turnIndex: nextIndex,
        activePlayerId: playerOrder[nextIndex],
        round: isNewRound ? null : null, // round increment handled by caller
        step: 'MAIN',
        actionCountThisTurn: 0,
      ));
      ctx.activePlayerOverride = playerOrder[nextIndex];
      ctx.data['activePlayerId'] = playerOrder[nextIndex];

      if (isNewRound) {
        final currentRound =
            (ctx.data['round'] as int?) ?? 1;
        ctx.data['round'] = currentRound + 1;
        ctx.updateTurn(TurnUpdate(round: currentRound + 1));
      }
    } else {
      // Simple advance: just move to next player
      final playerOrder = ctx.dsl.playerOrder;
      final currentId = ctx.dsl.playerId ?? ctx.activePlayerOverride ?? '';
      final currentIndex = playerOrder.indexOf(currentId);
      final nextIndex = (currentIndex + 1) % playerOrder.length;
      final isNewRound = nextIndex == 0;

      ctx.updateTurn(TurnUpdate(
        turnIndex: nextIndex,
        activePlayerId: playerOrder[nextIndex],
        step: 'MAIN',
        actionCountThisTurn: 0,
      ));
      ctx.activePlayerOverride = playerOrder[nextIndex];

      if (isNewRound) {
        final currentRound = (ctx.data['round'] as int?) ?? 1;
        ctx.data['round'] = currentRound + 1;
        ctx.updateTurn(TurnUpdate(round: currentRound + 1));
      }
    }
    _syncDsl(ctx);
    return;
  }

  // --- setTurn ---
  if (effect.containsKey('setTurn')) {
    final cfg = effect['setTurn'] as Map<String, dynamic>;
    ctx.updateTurn(TurnUpdate(
      round: cfg.containsKey('round')
          ? evalExpr(cfg['round'], ctx.dsl) as int?
          : null,
      turnIndex: cfg.containsKey('turnIndex')
          ? evalExpr(cfg['turnIndex'], ctx.dsl) as int?
          : null,
      activePlayerId: cfg.containsKey('activePlayerId')
          ? evalExpr(cfg['activePlayerId'], ctx.dsl)?.toString()
          : null,
      step: cfg.containsKey('step')
          ? evalExpr(cfg['step'], ctx.dsl)?.toString()
          : null,
      actionCountThisTurn: cfg.containsKey('actionCountThisTurn')
          ? evalExpr(cfg['actionCountThisTurn'], ctx.dsl) as int?
          : null,
    ));
    return;
  }

  // --- shuffleDeck ---
  if (effect.containsKey('shuffleDeck')) {
    final path = effect['shuffleDeck'] as String;
    final list = _getAtPath(ctx.data, path, ctx.dsl);
    if (list is List) {
      list.shuffle(ctx.dsl.rng);
    }
    return;
  }

  // --- drawCards ---
  if (effect.containsKey('drawCards')) {
    final cfg = effect['drawCards'] as Map<String, dynamic>;
    final fromPath = cfg['from'] as String;
    final toPath = cfg['to'] as String;
    final count = evalExpr(cfg['count'] ?? 1, ctx.dsl) as int;

    final fromList = _getAtPath(ctx.data, fromPath, ctx.dsl);
    final toList = _getAtPath(ctx.data, toPath, ctx.dsl);
    if (fromList is List && toList is List) {
      final n = count.clamp(0, fromList.length);
      final drawn = fromList.sublist(0, n);
      fromList.removeRange(0, n);
      toList.addAll(drawn);
    }
    _syncDsl(ctx);
    return;
  }

  // --- dealCards ---
  if (effect.containsKey('dealCards')) {
    final cfg = effect['dealCards'] as Map<String, dynamic>;
    final deckPath = cfg['from'] as String;
    final handsPath = cfg['to'] as String;
    final count = evalExpr(cfg['count'] ?? 1, ctx.dsl) as int;
    final players = List<String>.from(
        evalExpr(cfg['players'] ?? {'var': 'playerOrder'}, ctx.dsl) as List? ??
            ctx.dsl.playerOrder);

    final deck = _getAtPath(ctx.data, deckPath, ctx.dsl);
    if (deck is! List) return;

    var hands = _getAtPath(ctx.data, handsPath, ctx.dsl);
    if (hands is! Map) {
      hands = <String, dynamic>{};
      _setAtPath(ctx.data, handsPath, hands, ctx.dsl);
    }

    for (final playerId in players) {
      final hand = hands[playerId];
      final playerHand = hand is List ? hand : <dynamic>[];
      if (hand is! List) hands[playerId] = playerHand;

      final n = count.clamp(0, deck.length);
      playerHand.addAll(deck.sublist(0, n));
      deck.removeRange(0, n);
    }
    _syncDsl(ctx);
    return;
  }

  // --- returnCards ---
  if (effect.containsKey('returnCards')) {
    final cfg = effect['returnCards'] as Map<String, dynamic>;
    final fromPath = cfg['from'] as String;
    final toPath = cfg['to'] as String;

    final fromList = _getAtPath(ctx.data, fromPath, ctx.dsl);
    final toList = _getAtPath(ctx.data, toPath, ctx.dsl);
    if (fromList is List && toList is List) {
      toList.addAll(fromList);
      fromList.clear();
    }
    _syncDsl(ctx);
    return;
  }
}

// ---------------------------------------------------------------------------
// Path resolution helpers
// ---------------------------------------------------------------------------

/// Get a value at a dot-separated path, with `{var}` interpolation support.
dynamic _getAtPath(Map<String, dynamic> data, String path, DslContext dsl) {
  final parts = _interpolatePath(path, dsl);
  dynamic current = data;
  for (final part in parts) {
    if (current is Map) {
      current = current[part];
    } else if (current is List) {
      final idx = int.tryParse(part);
      if (idx != null && idx >= 0 && idx < current.length) {
        current = current[idx];
      } else {
        return null;
      }
    } else {
      return null;
    }
  }
  return current;
}

/// Set a value at a dot-separated path, creating intermediate maps as needed.
void _setAtPath(
    Map<String, dynamic> data, String path, dynamic value, DslContext dsl) {
  final parts = _interpolatePath(path, dsl);
  if (parts.isEmpty) return;

  dynamic current = data;
  for (var i = 0; i < parts.length - 1; i++) {
    final part = parts[i];
    if (current is Map) {
      if (current[part] == null) {
        current[part] = <String, dynamic>{};
      }
      current = current[part];
    } else if (current is List) {
      final idx = int.tryParse(part);
      if (idx != null && idx >= 0 && idx < current.length) {
        current = current[idx];
      } else {
        return;
      }
    } else {
      return;
    }
  }

  final lastPart = parts.last;
  if (current is Map) {
    current[lastPart] = value;
  } else if (current is List) {
    final idx = int.tryParse(lastPart);
    if (idx != null && idx >= 0 && idx < current.length) {
      current[idx] = value;
    }
  }
}

List<String> _interpolatePath(String path, DslContext dsl) {
  // Replace {varName} or {$varName} tokens in path segments
  final interpolated = path.replaceAllMapped(RegExp(r'\{(\$?\w+)\}'), (m) {
    final name = m.group(1)!;
    if (name == 'playerId') return dsl.playerId ?? '';
    if (dsl.locals.containsKey(name)) return dsl.locals[name].toString();
    if (dsl.actionData.containsKey(name)) {
      return dsl.actionData[name].toString();
    }
    if (dsl.data.containsKey(name)) return dsl.data[name].toString();
    return m.group(0)!;
  });
  return interpolated.split('.');
}

/// Re-sync the DslContext's data reference after mutation.
///
/// Since _EffectCtx.data and _EffectCtx.dsl.data are the same map,
/// this is a no-op, but exists for documentation clarity.
void _syncDsl(_EffectCtx ctx) {
  // data and dsl.data point to the same Map instance — no sync needed.
}

bool _toBool(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v.isNotEmpty;
  if (v is List) return v.isNotEmpty;
  if (v is Map) return v.isNotEmpty;
  return true;
}

/// Deep-copy a Map so all nested collections become mutable.
Map<String, dynamic> _deepCopyMap(Map<String, dynamic> source) {
  return source.map((k, v) => MapEntry(k, _deepCopyValue(v)));
}

dynamic _deepCopyValue(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.from(
        value.map((k, v) => MapEntry(k.toString(), _deepCopyValue(v))));
  }
  if (value is List) {
    return value.map(_deepCopyValue).toList();
  }
  return value;
}
