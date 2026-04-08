import 'dart:math';

/// Evaluation context for DSL expressions.
///
/// Holds all variable bindings available during expression evaluation:
/// game state data, player ID, action params, and local variables.
class DslContext {
  final Map<String, dynamic> data; // gameState.data
  final List<String> playerOrder;
  final String? playerId;
  final Map<String, dynamic> actionData;
  final Map<String, dynamic> locals; // $varName bindings from let/forEach
  final Random rng;

  DslContext({
    required this.data,
    this.playerOrder = const [],
    this.playerId,
    this.actionData = const {},
    Map<String, dynamic>? locals,
    Random? rng,
  })  : locals = locals ?? {},
        rng = rng ?? Random();

  DslContext withLocals(Map<String, dynamic> extra) => DslContext(
        data: data,
        playerOrder: playerOrder,
        playerId: playerId,
        actionData: actionData,
        locals: {...locals, ...extra},
        rng: rng,
      );

  DslContext withPlayer(String pid) => DslContext(
        data: data,
        playerOrder: playerOrder,
        playerId: pid,
        actionData: actionData,
        locals: locals,
        rng: rng,
      );
}

/// Evaluates a JSON DSL expression against a [DslContext].
///
/// Expressions can be:
/// - Literals: `42`, `"hello"`, `true`, `null`, `[1,2,3]`
/// - Variable ref: `{"var": "path.to.field"}`
/// - Operators: `{"+": [a, b]}`, `{"==": [a, b]}`, etc.
/// - Collection ops: `{"length": expr}`, `{"contains": [list, item]}`, etc.
/// - Conditionals: `{"if": [cond, then, else]}`
dynamic evalExpr(dynamic expr, DslContext ctx) {
  if (expr == null || expr is num || expr is bool) return expr;
  if (expr is String) return _interpolate(expr, ctx);
  if (expr is List) return expr.map((e) => evalExpr(e, ctx)).toList();
  if (expr is! Map<String, dynamic>) return expr;

  final map = expr;

  // Single-key operator dispatch
  if (map.length == 1) {
    final key = map.keys.first;
    final val = map.values.first;
    switch (key) {
      case 'var':
        return _resolveVar(val as String, ctx);
      case 'literal':
        return val; // Return without evaluation
      case '!':
        return !_toBool(evalExpr(val, ctx));
      case 'length':
        final v = evalExpr(val, ctx);
        if (v is List) return v.length;
        if (v is Map) return v.length;
        if (v is String) return v.length;
        return 0;
      case 'keys':
        final v = evalExpr(val, ctx);
        return v is Map ? v.keys.toList() : [];
      case 'values':
        final v = evalExpr(val, ctx);
        return v is Map ? v.values.toList() : [];
      case 'isEmpty':
        final v = evalExpr(val, ctx);
        if (v is List) return v.isEmpty;
        if (v is Map) return v.isEmpty;
        if (v is String) return v.isEmpty;
        return v == null;
      case 'isNotEmpty':
        final v = evalExpr(val, ctx);
        if (v is List) return v.isNotEmpty;
        if (v is Map) return v.isNotEmpty;
        if (v is String) return v.isNotEmpty;
        return v != null;
      case 'not':
        return !_toBool(evalExpr(val, ctx));
      case 'flatten':
        final v = evalExpr(val, ctx);
        if (v is List) {
          return v.expand((e) => e is List ? e : [e]).toList();
        }
        return v;
      case 'toString':
        return evalExpr(val, ctx).toString();
      case 'toInt':
        final v = evalExpr(val, ctx);
        if (v is int) return v;
        if (v is double) return v.toInt();
        if (v is String) return int.tryParse(v) ?? 0;
        return 0;
      case 'abs':
        final v = evalExpr(val, ctx);
        if (v is int) return v.abs();
        if (v is double) return v.abs();
        return 0;
    }
  }

  // Multi-key operators
  if (map.containsKey('op')) {
    return _evalOp(map, ctx);
  }

  // Arithmetic/comparison shorthand: {"+": [a, b]}
  for (final op in ['+', '-', '*', '/', '%', '==', '!=', '>', '<', '>=', '<=']) {
    if (map.containsKey(op)) {
      final args = (map[op] as List).map((e) => evalExpr(e, ctx)).toList();
      return _applyBinaryOp(op, args);
    }
  }

  // Logic
  if (map.containsKey('and')) {
    return (map['and'] as List).every((e) => _toBool(evalExpr(e, ctx)));
  }
  if (map.containsKey('or')) {
    return (map['or'] as List).any((e) => _toBool(evalExpr(e, ctx)));
  }

  // Conditional
  if (map.containsKey('if')) {
    final args = map['if'] as List;
    if (args.length < 2) return null;
    final cond = _toBool(evalExpr(args[0], ctx));
    return cond
        ? evalExpr(args[1], ctx)
        : (args.length > 2 ? evalExpr(args[2], ctx) : null);
  }

  // Collection: contains
  if (map.containsKey('contains')) {
    final args = map['contains'] as List;
    final list = evalExpr(args[0], ctx);
    final item = evalExpr(args[1], ctx);
    if (list is List) return list.contains(item);
    if (list is Map) return list.containsKey(item);
    return false;
  }

  // let/in: local variable binding for expressions
  if (map.containsKey('let') && map.containsKey('in')) {
    final bindings = map['let'] as Map<String, dynamic>;
    final body = map['in'];
    final locals = <String, dynamic>{};
    for (final entry in bindings.entries) {
      locals[entry.key] = evalExpr(entry.value, ctx.withLocals(locals));
    }
    return evalExpr(body, ctx.withLocals(locals));
  }

  // Collection: in (reversed contains)
  if (map.containsKey('in')) {
    final args = map['in'] as List;
    final item = evalExpr(args[0], ctx);
    final list = evalExpr(args[1], ctx);
    if (list is List) return list.contains(item);
    return false;
  }

  // Collection: get (index/key access)
  if (map.containsKey('get')) {
    final args = map['get'] as List;
    final coll = evalExpr(args[0], ctx);
    final key = evalExpr(args[1], ctx);
    if (coll is List && key is int && key >= 0 && key < coll.length) {
      return coll[key];
    }
    if (coll is Map) return coll[key?.toString() ?? key];
    return null;
  }

  // Collection: indexOf
  if (map.containsKey('indexOf')) {
    final args = map['indexOf'] as List;
    final list = evalExpr(args[0], ctx);
    final item = evalExpr(args[1], ctx);
    if (list is List) return list.indexOf(item);
    return -1;
  }

  // Collection: slice
  if (map.containsKey('slice')) {
    final cfg = map['slice'] as Map<String, dynamic>;
    final list = List.from(evalExpr(cfg['list'], ctx) as List? ?? []);
    if (cfg.containsKey('last')) {
      final n = evalExpr(cfg['last'], ctx) as int;
      return list.length > n ? list.sublist(list.length - n) : list;
    }
    final from = evalExpr(cfg['from'] ?? 0, ctx) as int;
    final count = cfg.containsKey('count')
        ? evalExpr(cfg['count'], ctx) as int
        : list.length - from;
    return list.sublist(from, min(from + count, list.length));
  }

  // Collection: filter
  if (map.containsKey('filter')) {
    final cfg = map['filter'] as Map<String, dynamic>;
    final list = List.from(evalExpr(cfg['list'], ctx) as List? ?? []);
    final asVar = cfg['as'] as String;
    final where = cfg['where'];
    return list.where((item) {
      final inner = ctx.withLocals({asVar: item});
      return _toBool(evalExpr(where, inner));
    }).toList();
  }

  // Collection: map
  if (map.containsKey('map')) {
    final cfg = map['map'] as Map<String, dynamic>;
    final list = List.from(evalExpr(cfg['list'], ctx) as List? ?? []);
    final asVar = cfg['as'] as String;
    final to = cfg['to'];
    return list.map((item) {
      final inner = ctx.withLocals({asVar: item});
      return evalExpr(to, inner);
    }).toList();
  }

  // Collection: reduce/fold
  if (map.containsKey('reduce')) {
    final cfg = map['reduce'] as Map<String, dynamic>;
    final list = List.from(evalExpr(cfg['list'], ctx) as List? ?? []);
    final asVar = cfg['as'] as String;
    final accVar = cfg['acc'] as String;
    final init = evalExpr(cfg['init'], ctx);
    final to = cfg['to'];
    return list.fold(init, (acc, item) {
      final inner = ctx.withLocals({asVar: item, accVar: acc});
      return evalExpr(to, inner);
    });
  }

  // Math: max, min
  if (map.containsKey('max')) {
    final args = (map['max'] as List).map((e) => _toNum(evalExpr(e, ctx)));
    return args.reduce((a, b) => a > b ? a : b);
  }
  if (map.containsKey('min')) {
    final args = (map['min'] as List).map((e) => _toNum(evalExpr(e, ctx)));
    return args.reduce((a, b) => a < b ? a : b);
  }

  // String: cat (concatenation)
  if (map.containsKey('cat')) {
    return (map['cat'] as List).map((e) => evalExpr(e, ctx).toString()).join();
  }

  // Random
  if (map.containsKey('shuffle')) {
    final list = List.from(evalExpr(map['shuffle'], ctx) as List? ?? []);
    list.shuffle(ctx.rng);
    return list;
  }
  if (map.containsKey('randomInt')) {
    final cfg = map['randomInt'] as Map<String, dynamic>;
    final lo = evalExpr(cfg['min'] ?? 0, ctx) as int;
    final hi = evalExpr(cfg['max'], ctx) as int;
    return lo + ctx.rng.nextInt(hi - lo + 1);
  }

  // List construction: range
  if (map.containsKey('range')) {
    final cfg = map['range'];
    if (cfg is int) return List.generate(cfg, (i) => i);
    if (cfg is Map<String, dynamic>) {
      // Check if it's a range config {start, end} or an expression to evaluate
      if (cfg.containsKey('start') || cfg.containsKey('end')) {
        final start = evalExpr(cfg['start'] ?? 0, ctx) as int;
        final end = evalExpr(cfg['end'], ctx) as int;
        return List.generate(end - start, (i) => start + i);
      }
      // Otherwise evaluate as expression (e.g. {"var": "$count"})
      final evaluated = evalExpr(cfg, ctx);
      if (evaluated is int) return List.generate(evaluated, (i) => i);
      return [];
    }
    return [];
  }

  // Sublist take/skip
  if (map.containsKey('take')) {
    final cfg = map['take'] as Map<String, dynamic>;
    final list = List.from(evalExpr(cfg['list'], ctx) as List? ?? []);
    final n = evalExpr(cfg['count'], ctx) as int;
    return list.take(n).toList();
  }
  if (map.containsKey('skip')) {
    final cfg = map['skip'] as Map<String, dynamic>;
    final list = List.from(evalExpr(cfg['list'], ctx) as List? ?? []);
    final n = evalExpr(cfg['count'], ctx) as int;
    return list.skip(n).toList();
  }

  // Default: return the map as-is (might be a literal map value)
  return map;
}

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

/// Resolve a dot-path variable reference.
///
/// Supports special prefixes:
/// - `playerId` → current player ID
/// - `playerOrder` → player order list
/// - `action.*` → action data
/// - `$varName` → local variable
/// - Otherwise → look up in `data`
///
/// Path segments like `{playerId}` are interpolated.
dynamic _resolveVar(String path, DslContext ctx) {
  final parts = path.split('.');
  dynamic current;

  final first = _interpolate(parts[0], ctx);

  if (first == 'playerId') {
    current = ctx.playerId;
  } else if (first == 'playerOrder') {
    current = ctx.playerOrder;
  } else if (first == 'action') {
    current = ctx.actionData;
  } else if (first.startsWith(r'$')) {
    current = ctx.locals[first];
  } else {
    current = ctx.data[first];
  }

  for (var i = (first == 'action' || first == 'playerOrder') ? 1 : 1;
      i < parts.length;
      i++) {
    if (current == null) return null;
    final segment = _interpolate(parts[i], ctx);

    if (current is Map) {
      current = current[segment];
    } else if (current is List) {
      final idx = int.tryParse(segment);
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

/// Replace `{varName}` placeholders in a string.
String _interpolate(String s, DslContext ctx) {
  return s.replaceAllMapped(RegExp(r'\{(\$?\w+)\}'), (m) {
    final name = m.group(1)!;
    if (name == 'playerId') return ctx.playerId ?? '';
    if (ctx.locals.containsKey(name)) return ctx.locals[name].toString();
    if (ctx.actionData.containsKey(name)) {
      return ctx.actionData[name].toString();
    }
    if (ctx.data.containsKey(name)) return ctx.data[name].toString();
    return m.group(0)!; // keep as-is if not found
  });
}

dynamic _evalOp(Map<String, dynamic> map, DslContext ctx) {
  final op = map['op'] as String;
  final args = (map['args'] as List?)?.map((e) => evalExpr(e, ctx)).toList();
  final left = map.containsKey('left') ? evalExpr(map['left'], ctx) : null;
  final right = map.containsKey('right') ? evalExpr(map['right'], ctx) : null;

  if (args != null) return _applyBinaryOp(op, args);
  if (left != null && right != null) {
    return _applyBinaryOp(op, [left, right]);
  }
  return null;
}

dynamic _applyBinaryOp(String op, List<dynamic> args) {
  if (args.length < 2) return null;
  final a = args[0];
  final b = args[1];

  switch (op) {
    case '+':
      if (a is String || b is String) return '${a}${b}';
      return _toNum(a) + _toNum(b);
    case '-':
      return _toNum(a) - _toNum(b);
    case '*':
      return _toNum(a) * _toNum(b);
    case '/':
      final divisor = _toNum(b);
      return divisor == 0 ? 0 : _toNum(a) / divisor;
    case '%':
      final divisor = _toNum(b);
      return divisor == 0 ? 0 : _toNum(a) % divisor;
    case '==':
      return a == b;
    case '!=':
      return a != b;
    case '>':
      return _toNum(a) > _toNum(b);
    case '<':
      return _toNum(a) < _toNum(b);
    case '>=':
      return _toNum(a) >= _toNum(b);
    case '<=':
      return _toNum(a) <= _toNum(b);
    default:
      return null;
  }
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

num _toNum(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? 0;
  if (v is bool) return v ? 1 : 0;
  return 0;
}
