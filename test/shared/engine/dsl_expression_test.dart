import 'dart:math';

import 'package:test/test.dart';

import '../../../lib/shared/game_pack/engine/dsl_expression.dart';

void main() {
  group('evalExpr', () {
    late DslContext ctx;

    setUp(() {
      ctx = DslContext(
        data: {
          'scores': {'p1': 10, 'p2': 5},
          'deck': ['A', 'B', 'C'],
          'phase': 'main',
          'hands': {
            'p1': ['card1', 'card2'],
            'p2': ['card3'],
          },
          'nested': {
            'deep': {'value': 42},
          },
        },
        playerOrder: ['p1', 'p2'],
        playerId: 'p1',
        actionData: {'cardId': 'card1', 'amount': 3},
        rng: Random(42),
      );
    });

    // -----------------------------------------------------------------
    // Literals
    // -----------------------------------------------------------------

    test('literal values pass through', () {
      expect(evalExpr(42, ctx), 42);
      expect(evalExpr(3.14, ctx), 3.14);
      expect(evalExpr(true, ctx), true);
      expect(evalExpr(null, ctx), null);
    });

    test('string without interpolation passes through', () {
      expect(evalExpr('hello', ctx), 'hello');
    });

    test('string interpolation with {playerId}', () {
      expect(evalExpr('player-{playerId}', ctx), 'player-p1');
    });

    test('list evaluates each element', () {
      expect(evalExpr([1, 2, {'var': 'phase'}], ctx), [1, 2, 'main']);
    });

    test('literal operator returns value without evaluation', () {
      expect(
        evalExpr({'literal': {'var': 'something'}}, ctx),
        {'var': 'something'},
      );
    });

    // -----------------------------------------------------------------
    // Variable resolution
    // -----------------------------------------------------------------

    test('var resolves top-level data key', () {
      expect(evalExpr({'var': 'phase'}, ctx), 'main');
    });

    test('var resolves nested path', () {
      expect(evalExpr({'var': 'nested.deep.value'}, ctx), 42);
    });

    test('var resolves playerId', () {
      expect(evalExpr({'var': 'playerId'}, ctx), 'p1');
    });

    test('var resolves playerOrder', () {
      expect(evalExpr({'var': 'playerOrder'}, ctx), ['p1', 'p2']);
    });

    test('var resolves action data', () {
      expect(evalExpr({'var': 'action.cardId'}, ctx), 'card1');
    });

    test('var resolves local variables', () {
      final ctxWithLocals = ctx.withLocals({r'$item': 'hello'});
      expect(evalExpr({'var': r'$item'}, ctxWithLocals), 'hello');
    });

    test('var with {playerId} interpolation in path', () {
      expect(evalExpr({'var': 'hands.{playerId}'}, ctx), ['card1', 'card2']);
    });

    test('var returns null for missing path', () {
      expect(evalExpr({'var': 'nonexistent.path'}, ctx), null);
    });

    // -----------------------------------------------------------------
    // Arithmetic
    // -----------------------------------------------------------------

    test('addition', () {
      expect(evalExpr({'+': [3, 4]}, ctx), 7);
    });

    test('string concatenation via +', () {
      expect(evalExpr({'+': ['hello', ' world']}, ctx), 'hello world');
    });

    test('subtraction', () {
      expect(evalExpr({'-': [10, 3]}, ctx), 7);
    });

    test('multiplication', () {
      expect(evalExpr({'*': [3, 4]}, ctx), 12);
    });

    test('division', () {
      expect(evalExpr({'/': [10, 3]}, ctx), closeTo(3.33, 0.01));
    });

    test('division by zero returns 0', () {
      expect(evalExpr({'/': [10, 0]}, ctx), 0);
    });

    test('modulo', () {
      expect(evalExpr({'%': [10, 3]}, ctx), 1);
    });

    // -----------------------------------------------------------------
    // Comparison
    // -----------------------------------------------------------------

    test('equality', () {
      expect(evalExpr({'==': [3, 3]}, ctx), true);
      expect(evalExpr({'==': [3, 4]}, ctx), false);
    });

    test('inequality', () {
      expect(evalExpr({'!=': [3, 4]}, ctx), true);
    });

    test('greater than', () {
      expect(evalExpr({'>': [5, 3]}, ctx), true);
      expect(evalExpr({'>': [3, 5]}, ctx), false);
    });

    test('less than', () {
      expect(evalExpr({'<': [3, 5]}, ctx), true);
    });

    test('greater or equal', () {
      expect(evalExpr({'>=': [5, 5]}, ctx), true);
      expect(evalExpr({'>=': [4, 5]}, ctx), false);
    });

    test('less or equal', () {
      expect(evalExpr({'<=': [5, 5]}, ctx), true);
    });

    // -----------------------------------------------------------------
    // Logic
    // -----------------------------------------------------------------

    test('and', () {
      expect(evalExpr({'and': [true, true]}, ctx), true);
      expect(evalExpr({'and': [true, false]}, ctx), false);
    });

    test('or', () {
      expect(evalExpr({'or': [false, true]}, ctx), true);
      expect(evalExpr({'or': [false, false]}, ctx), false);
    });

    test('not (!)', () {
      expect(evalExpr({'!': true}, ctx), false);
      expect(evalExpr({'!': false}, ctx), true);
    });

    // -----------------------------------------------------------------
    // Conditional
    // -----------------------------------------------------------------

    test('if-then-else', () {
      expect(evalExpr({'if': [true, 'yes', 'no']}, ctx), 'yes');
      expect(evalExpr({'if': [false, 'yes', 'no']}, ctx), 'no');
    });

    test('if-then (no else)', () {
      expect(evalExpr({'if': [true, 'yes']}, ctx), 'yes');
      expect(evalExpr({'if': [false, 'yes']}, ctx), null);
    });

    // -----------------------------------------------------------------
    // Collections
    // -----------------------------------------------------------------

    test('length of list', () {
      expect(evalExpr({'length': {'var': 'deck'}}, ctx), 3);
    });

    test('length of map', () {
      expect(evalExpr({'length': {'var': 'scores'}}, ctx), 2);
    });

    test('contains in list', () {
      expect(evalExpr({'contains': [{'var': 'deck'}, 'A']}, ctx), true);
      expect(evalExpr({'contains': [{'var': 'deck'}, 'X']}, ctx), false);
    });

    test('contains in map (containsKey)', () {
      expect(
          evalExpr({'contains': [{'var': 'scores'}, 'p1']}, ctx), true);
    });

    test('in (reversed contains)', () {
      expect(evalExpr({'in': ['A', {'var': 'deck'}]}, ctx), true);
      expect(evalExpr({'in': ['X', {'var': 'deck'}]}, ctx), false);
    });

    test('get by index', () {
      expect(evalExpr({'get': [{'var': 'deck'}, 0]}, ctx), 'A');
    });

    test('get by key', () {
      expect(evalExpr({'get': [{'var': 'scores'}, 'p1']}, ctx), 10);
    });

    test('indexOf', () {
      expect(evalExpr({'indexOf': [{'var': 'deck'}, 'B']}, ctx), 1);
    });

    test('keys', () {
      expect(evalExpr({'keys': {'var': 'scores'}}, ctx), ['p1', 'p2']);
    });

    test('values', () {
      expect(evalExpr({'values': {'var': 'scores'}}, ctx), [10, 5]);
    });

    test('isEmpty / isNotEmpty', () {
      expect(evalExpr({'isEmpty': {'var': 'deck'}}, ctx), false);
      expect(evalExpr({'isNotEmpty': {'var': 'deck'}}, ctx), true);
    });

    test('flatten', () {
      final nestedCtx = DslContext(
        data: {'list': [['a', 'b'], ['c'], 'd']},
        rng: Random(0),
      );
      expect(evalExpr({'flatten': {'var': 'list'}}, nestedCtx),
          ['a', 'b', 'c', 'd']);
    });

    // -----------------------------------------------------------------
    // Collection transforms
    // -----------------------------------------------------------------

    test('filter', () {
      final result = evalExpr({
        'filter': {
          'list': {'var': 'deck'},
          'as': r'$card',
          'where': {'!=': [{'var': r'$card'}, 'B']},
        }
      }, ctx);
      expect(result, ['A', 'C']);
    });

    test('map', () {
      final result = evalExpr({
        'map': {
          'list': [1, 2, 3],
          'as': r'$n',
          'to': {'*': [{'var': r'$n'}, 2]},
        }
      }, ctx);
      expect(result, [2, 4, 6]);
    });

    test('reduce', () {
      final result = evalExpr({
        'reduce': {
          'list': [1, 2, 3, 4],
          'as': r'$n',
          'acc': r'$sum',
          'init': 0,
          'to': {'+': [{'var': r'$sum'}, {'var': r'$n'}]},
        }
      }, ctx);
      expect(result, 10);
    });

    // -----------------------------------------------------------------
    // Math & String
    // -----------------------------------------------------------------

    test('max', () {
      expect(evalExpr({'max': [3, 7, 1]}, ctx), 7);
    });

    test('min', () {
      expect(evalExpr({'min': [3, 7, 1]}, ctx), 1);
    });

    test('abs', () {
      expect(evalExpr({'abs': -5}, ctx), 5);
    });

    test('cat', () {
      expect(
        evalExpr({'cat': ['Hello', ' ', 'World']}, ctx),
        'Hello World',
      );
    });

    test('toString', () {
      expect(evalExpr({'toString': 42}, ctx), '42');
    });

    test('toInt', () {
      expect(evalExpr({'toInt': 3.7}, ctx), 3);
      expect(evalExpr({'toInt': '42'}, ctx), 42);
    });

    // -----------------------------------------------------------------
    // Range & Slice
    // -----------------------------------------------------------------

    test('range (int)', () {
      expect(evalExpr({'range': 5}, ctx), [0, 1, 2, 3, 4]);
    });

    test('range (start/end)', () {
      expect(evalExpr({'range': {'start': 2, 'end': 5}}, ctx), [2, 3, 4]);
    });

    test('take', () {
      expect(evalExpr({
        'take': {'list': {'var': 'deck'}, 'count': 2}
      }, ctx), ['A', 'B']);
    });

    test('skip', () {
      expect(evalExpr({
        'skip': {'list': {'var': 'deck'}, 'count': 1}
      }, ctx), ['B', 'C']);
    });

    test('slice with from/count', () {
      expect(evalExpr({
        'slice': {'list': {'var': 'deck'}, 'from': 1, 'count': 1}
      }, ctx), ['B']);
    });

    test('slice with last', () {
      expect(evalExpr({
        'slice': {'list': {'var': 'deck'}, 'last': 2}
      }, ctx), ['B', 'C']);
    });

    // -----------------------------------------------------------------
    // Random
    // -----------------------------------------------------------------

    test('shuffle returns all elements', () {
      final result = evalExpr({'shuffle': [1, 2, 3, 4, 5]}, ctx) as List;
      expect(result.length, 5);
      expect(result.toSet(), {1, 2, 3, 4, 5});
    });

    test('randomInt is in range', () {
      final result = evalExpr(
          {'randomInt': {'min': 1, 'max': 6}}, ctx) as int;
      expect(result, greaterThanOrEqualTo(1));
      expect(result, lessThanOrEqualTo(6));
    });

    // -----------------------------------------------------------------
    // Op syntax
    // -----------------------------------------------------------------

    test('op with args', () {
      expect(evalExpr({'op': '+', 'args': [2, 3]}, ctx), 5);
    });

    test('op with left/right', () {
      expect(evalExpr({'op': '*', 'left': 4, 'right': 5}, ctx), 20);
    });
  });
}
