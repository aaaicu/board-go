import 'dart:collection';

/// A bounded LRU cache of processed action IDs used to detect and reject
/// duplicate client-submitted actions (idempotency guard).
///
/// Internally backed by a [Queue] (insertion-ordered) and a [Set] (O(1) look-up).
/// When the cache exceeds [maxSize] the oldest entry is evicted before the new
/// one is inserted.
class ProcessedActionsCache {
  /// Maximum number of action IDs retained simultaneously.
  final int maxSize;

  final Queue<String> _queue = Queue();
  final Set<String> _set = {};

  ProcessedActionsCache({this.maxSize = 1000});

  /// Returns the current number of entries in the cache.
  int get size => _set.length;

  /// Returns `true` if [id] is in the cache.
  bool contains(String id) => _set.contains(id);

  /// Convenience alias for [contains] with a more descriptive name.
  bool isAlreadyProcessed(String id) => _set.contains(id);

  /// Attempts to add [id] to the cache.
  ///
  /// Returns `true` if [id] was already present (i.e. a duplicate).
  /// Returns `false` if [id] was new and has been stored successfully.
  ///
  /// When the cache already holds [maxSize] entries, the oldest entry is
  /// evicted before the new one is inserted.
  bool add(String id) {
    if (_set.contains(id)) return true;

    if (_queue.length >= maxSize) {
      final evicted = _queue.removeFirst();
      _set.remove(evicted);
    }

    _queue.addLast(id);
    _set.add(id);
    return false;
  }

  /// Removes all entries from the cache.
  void clear() {
    _queue.clear();
    _set.clear();
  }
}
