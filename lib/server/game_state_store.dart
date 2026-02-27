import 'dart:convert';

import 'package:sqflite_common/sqflite.dart';

import '../shared/game_session/game_session_state.dart';

/// SQLite-backed persistence store for [GameSessionState].
///
/// Uses a single `sessions` table with the session JSON stored as a blob.
/// An in-memory database (`':memory:'`) is used when no explicit [path] is
/// given, making this trivially testable without a file system.
///
/// Typical usage:
/// ```dart
/// final store = GameStateStore();
/// await store.open();           // opens ':memory:' by default
/// await store.save(state);
/// final loaded = await store.load(state.sessionId);
/// await store.close();
/// ```
class GameStateStore {
  Database? _db;

  static const _tableName = 'sessions';
  static const _colSessionId = 'sessionId';
  static const _colStateJson = 'stateJson';
  static const _colUpdatedAt = 'updatedAt';

  /// Opens (or creates) the database.
  ///
  /// Pass [path] = `':memory:'` or omit for an in-memory database (tests).
  Future<void> open({String? path}) async {
    final resolvedPath = path ?? ':memory:';
    _db = await openDatabase(
      resolvedPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            $_colSessionId TEXT PRIMARY KEY,
            $_colStateJson TEXT NOT NULL,
            $_colUpdatedAt INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  /// Closes the database connection.
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Persists [state] using an UPSERT (insert or replace).
  Future<void> save(GameSessionState state) async {
    final db = _requireOpen();
    await db.insert(
      _tableName,
      {
        _colSessionId: state.sessionId,
        _colStateJson: jsonEncode(state.toJson()),
        _colUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Loads the [GameSessionState] for [sessionId], or `null` if not found.
  Future<GameSessionState?> load(String sessionId) async {
    final db = _requireOpen();
    final rows = await db.query(
      _tableName,
      where: '$_colSessionId = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final json = jsonDecode(rows.first[_colStateJson] as String)
        as Map<String, dynamic>;
    return GameSessionState.fromJson(json);
  }

  /// Removes the record for [sessionId].  No-op if it does not exist.
  Future<void> delete(String sessionId) async {
    final db = _requireOpen();
    await db.delete(
      _tableName,
      where: '$_colSessionId = ?',
      whereArgs: [sessionId],
    );
  }

  Database _requireOpen() {
    final db = _db;
    if (db == null) {
      throw StateError('GameStateStore: call open() before using the store');
    }
    return db;
  }
}
