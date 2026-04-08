import 'dart:math';

import 'package:test/test.dart';

import '../../../lib/shared/game_pack/engine/dsl_effect.dart';
import '../../../lib/shared/game_pack/engine/dsl_expression.dart';

void main() {
  group('executeEffects', () {
    late DslContext ctx;

    setUp(() {
      ctx = DslContext(
        data: {
          'scores': {'p1': 10, 'p2': 5},
          'deck': ['A', 'B', 'C', 'D', 'E'],
          'hands': {
            'p1': ['X'],
            'p2': ['Y'],
          },
          'phase': 'main',
          'discard': <String>[],
          'counter': 0,
        },
        playerOrder: ['p1', 'p2'],
        playerId: 'p1',
        actionData: {'cardId': 'X', 'amount': 3},
        rng: Random(42),
      );
    });

    // -----------------------------------------------------------------
    // set
    // -----------------------------------------------------------------

    test('set at top-level path', () {
      final result = executeEffects([
        {'set': 'newPhase', 'path': 'phase'},
      ], ctx);
      expect(result.data['phase'], 'newPhase');
    });

    test('set at nested path', () {
      final result = executeEffects([
        {'set': 99, 'path': 'scores.p1'},
      ], ctx);
      expect(result.data['scores']['p1'], 99);
    });

    test('set with {playerId} interpolation', () {
      final result = executeEffects([
        {'set': 99, 'path': 'scores.{playerId}'},
      ], ctx);
      expect(result.data['scores']['p1'], 99);
    });

    // -----------------------------------------------------------------
    // increment
    // -----------------------------------------------------------------

    test('increment by default (1)', () {
      final result = executeEffects([
        {'increment': 'counter'},
      ], ctx);
      expect(result.data['counter'], 1);
    });

    test('increment by specific amount', () {
      final result = executeEffects([
        {'increment': 'scores.p1', 'by': 5},
      ], ctx);
      expect(result.data['scores']['p1'], 15);
    });

    test('increment with expression', () {
      final result = executeEffects([
        {'increment': 'scores.p1', 'by': {'var': 'action.amount'}},
      ], ctx);
      expect(result.data['scores']['p1'], 13);
    });

    // -----------------------------------------------------------------
    // append / remove
    // -----------------------------------------------------------------

    test('append to list', () {
      final result = executeEffects([
        {'append': 'discard', 'value': 'Z'},
      ], ctx);
      expect(result.data['discard'], ['Z']);
    });

    test('remove from list', () {
      final result = executeEffects([
        {'remove': 'deck', 'value': 'C'},
      ], ctx);
      expect(result.data['deck'], ['A', 'B', 'D', 'E']);
    });

    // -----------------------------------------------------------------
    // insert
    // -----------------------------------------------------------------

    test('insert at specific index', () {
      final result = executeEffects([
        {'insert': 'deck', 'value': 'Z', 'at': 1},
      ], ctx);
      expect(result.data['deck'], ['A', 'Z', 'B', 'C', 'D', 'E']);
    });

    // -----------------------------------------------------------------
    // merge / delete
    // -----------------------------------------------------------------

    test('merge into map', () {
      final result = executeEffects([
        {'merge': 'scores', 'value': {'p3': 0}},
      ], ctx);
      expect(result.data['scores']['p3'], 0);
      expect(result.data['scores']['p1'], 10);
    });

    test('delete key from map', () {
      final result = executeEffects([
        {'delete': 'scores.p2'},
      ], ctx);
      expect(result.data['scores'].containsKey('p2'), false);
    });

    // -----------------------------------------------------------------
    // if
    // -----------------------------------------------------------------

    test('if-then executes on true condition', () {
      final result = executeEffects([
        {
          'if': {'==': [{'var': 'phase'}, 'main']},
          'then': [
            {'set': 'next', 'path': 'phase'}
          ],
        }
      ], ctx);
      expect(result.data['phase'], 'next');
    });

    test('if-else executes on false condition', () {
      final result = executeEffects([
        {
          'if': {'==': [{'var': 'phase'}, 'other']},
          'then': [
            {'set': 'wrong', 'path': 'phase'}
          ],
          'else': [
            {'set': 'correct', 'path': 'phase'}
          ],
        }
      ], ctx);
      expect(result.data['phase'], 'correct');
    });

    // -----------------------------------------------------------------
    // forEach
    // -----------------------------------------------------------------

    test('forEach iterates over list', () {
      final result = executeEffects([
        {
          'forEach': ['p1', 'p2'],
          'as': r'$pid',
          'do': [
            {'set': 0, 'path': r'scores.{$pid}'},
          ],
        }
      ], ctx);
      expect(result.data['scores']['p1'], 0);
      expect(result.data['scores']['p2'], 0);
    });

    test('forEach with index variable', () {
      final result = executeEffects([
        {
          'forEach': ['a', 'b'],
          'as': r'$item',
          'index': r'$i',
          'do': [
            {'set': {'var': r'$i'}, 'path': r'scores.{$item}'},
          ],
        }
      ], ctx);
      expect(result.data['scores']['a'], 0);
      expect(result.data['scores']['b'], 1);
    });

    // -----------------------------------------------------------------
    // let
    // -----------------------------------------------------------------

    test('let defines local variables for effects', () {
      final result = executeEffects([
        {
          'let': {
            r'$doubled': {'+': [{'var': 'counter'}, {'var': 'counter'}]},
          },
          'do': [
            {'set': {'var': r'$doubled'}, 'path': 'counter'},
          ],
        }
      ], ctx);
      expect(result.data['counter'], 0); // 0+0=0 (counter starts at 0)
    });

    // -----------------------------------------------------------------
    // log
    // -----------------------------------------------------------------

    test('log collects entries', () {
      final result = executeEffects([
        {'log': 'system', 'message': 'Game started'},
        {'log': 'action', 'message': 'Player acted'},
      ], ctx);
      expect(result.logs.length, 2);
      expect(result.logs[0].eventType, 'system');
      expect(result.logs[0].description, 'Game started');
    });

    // -----------------------------------------------------------------
    // setPhase
    // -----------------------------------------------------------------

    test('setPhase changes phase', () {
      final result = executeEffects([
        {'setPhase': 'voting'},
      ], ctx);
      expect(result.data['phase'], 'voting');
    });

    // -----------------------------------------------------------------
    // shuffleDeck
    // -----------------------------------------------------------------

    test('shuffleDeck shuffles in place', () {
      final result = executeEffects([
        {'shuffleDeck': 'deck'},
      ], ctx);
      expect(result.data['deck'].length, 5);
      expect((result.data['deck'] as List).toSet(), {'A', 'B', 'C', 'D', 'E'});
    });

    // -----------------------------------------------------------------
    // drawCards
    // -----------------------------------------------------------------

    test('drawCards moves N cards from one list to another', () {
      final result = executeEffects([
        {
          'drawCards': {
            'from': 'deck',
            'to': 'hands.p1',
            'count': 2,
          }
        }
      ], ctx);
      expect(result.data['deck'].length, 3);
      expect(result.data['hands']['p1'].length, 3); // had 1, drew 2
      expect(result.data['hands']['p1'], ['X', 'A', 'B']);
    });

    // -----------------------------------------------------------------
    // dealCards
    // -----------------------------------------------------------------

    test('dealCards deals to all players', () {
      final result = executeEffects([
        {
          'dealCards': {
            'from': 'deck',
            'to': 'hands',
            'count': 2,
          }
        }
      ], ctx);
      // p1 had ['X'], p2 had ['Y'], each gets 2 from deck
      expect(result.data['hands']['p1'].length, 3);
      expect(result.data['hands']['p2'].length, 3);
      expect(result.data['deck'].length, 1); // 5 - 2*2 = 1
    });

    // -----------------------------------------------------------------
    // returnCards
    // -----------------------------------------------------------------

    test('returnCards moves all from source to target', () {
      final result = executeEffects([
        {
          'returnCards': {'from': 'hands.p1', 'to': 'discard'}
        }
      ], ctx);
      expect(result.data['hands']['p1'], isEmpty);
      expect(result.data['discard'], ['X']);
    });

    // -----------------------------------------------------------------
    // setTurn
    // -----------------------------------------------------------------

    test('setTurn updates turn state', () {
      final result = executeEffects([
        {
          'setTurn': {
            'round': 2,
            'step': 'END',
            'actionCountThisTurn': 0,
          }
        }
      ], ctx);
      expect(result.turnUpdate?.round, 2);
      expect(result.turnUpdate?.step, 'END');
      expect(result.turnUpdate?.actionCountThisTurn, 0);
    });

    // -----------------------------------------------------------------
    // setActivePlayer
    // -----------------------------------------------------------------

    test('setActivePlayer changes active player', () {
      final result = executeEffects([
        {'setActivePlayer': 'p2'},
      ], ctx);
      expect(result.activePlayerOverride, 'p2');
    });

    // -----------------------------------------------------------------
    // noop
    // -----------------------------------------------------------------

    test('noop does nothing', () {
      final result = executeEffects([
        {'noop': true},
      ], ctx);
      expect(result.data['phase'], 'main');
      expect(result.logs, isEmpty);
    });
  });
}
