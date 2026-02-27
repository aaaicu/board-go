import 'package:test/test.dart';

import '../../lib/server/processed_actions_cache.dart';

void main() {
  group('ProcessedActionsCache', () {
    late ProcessedActionsCache cache;

    setUp(() => cache = ProcessedActionsCache());

    test('new ID is not contained', () {
      expect(cache.contains('id-1'), isFalse);
    });

    test('add() returns false for a new ID and stores it', () {
      final isDuplicate = cache.add('id-1');
      expect(isDuplicate, isFalse);
      expect(cache.contains('id-1'), isTrue);
    });

    test('add() returns true (duplicate) when the same ID is added twice', () {
      cache.add('id-1');
      final isDuplicate = cache.add('id-1');
      expect(isDuplicate, isTrue);
    });

    test('isAlreadyProcessed() returns true after add()', () {
      cache.add('action-42');
      expect(cache.isAlreadyProcessed('action-42'), isTrue);
    });

    test('isAlreadyProcessed() returns false before any add()', () {
      expect(cache.isAlreadyProcessed('ghost'), isFalse);
    });

    test('clear() removes all entries', () {
      cache.add('a');
      cache.add('b');
      cache.clear();
      expect(cache.contains('a'), isFalse);
      expect(cache.contains('b'), isFalse);
    });

    test('exceeding maxSize evicts the oldest entry (LRU eviction)', () {
      const maxSize = 5;
      final small = ProcessedActionsCache(maxSize: maxSize);

      // Fill to capacity.
      for (var i = 0; i < maxSize; i++) {
        small.add('id-$i');
      }

      // Adding one more should evict 'id-0'.
      small.add('id-overflow');

      expect(small.contains('id-0'), isFalse,
          reason: 'oldest entry must be evicted when maxSize is exceeded');
      expect(small.contains('id-overflow'), isTrue,
          reason: 'new entry must be present after eviction');

      // The remaining entries (id-1 through id-4) should still be present.
      for (var i = 1; i < maxSize; i++) {
        expect(small.contains('id-$i'), isTrue,
            reason: 'id-$i should survive the eviction');
      }
    });

    test('default maxSize is 1000 — 1001st entry evicts the first', () {
      const defaultMax = 1000;
      for (var i = 0; i < defaultMax; i++) {
        cache.add('id-$i');
      }
      cache.add('id-1000');

      expect(cache.contains('id-0'), isFalse,
          reason: 'id-0 should be evicted after inserting 1001 entries');
      expect(cache.contains('id-1000'), isTrue);
    });

    test('size matches number of unique entries added', () {
      cache.add('a');
      cache.add('b');
      cache.add('a'); // duplicate — should not increase size
      expect(cache.size, equals(2));
    });
  });
}
