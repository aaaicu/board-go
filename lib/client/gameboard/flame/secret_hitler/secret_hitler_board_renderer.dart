import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart';

import '../../../../shared/game_pack/game_board_renderer.dart';
import '../../../../shared/game_pack/views/board_view.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Authentic Secret Hitler color palette
// ─────────────────────────────────────────────────────────────────────────────

// Liberal (Blue) board
const Color _kLibBg = Color(0xFF1B3A6B);
const Color _kLibBgLight = Color(0xFF254D8A);
const Color _kLibAccent = Color(0xFF4A7AB5);
const Color _kLibBorder = Color(0xFF5B8CC7);
const Color _kLibColumn = Color(0xFF7BA3D0);

// Fascist (Red) board
const Color _kFasBg = Color(0xFF6B1F1F);
const Color _kFasBgLight = Color(0xFF7B2A2A);
const Color _kFasAccent = Color(0xFFB84040);
const Color _kFasBorder = Color(0xFF8B3A2A);
const Color _kFasChain = Color(0xFFA0522D);

// Shared
const Color _kCream = Color(0xFFF5E6C8);

const Color _kWoodLight = Color(0xFFD4A84A);
const Color _kWoodMid = Color(0xFFC49535);
const Color _kWoodDark = Color(0xFFB08830);
const Color _kWoodGrain = Color(0xFFA07828);
const Color _kTextDark = Color(0xFF1A1A1A);
const Color _kTextLight = Color(0xFFF5F5F5);

const Color _kGold = Color(0xFFFFD54F);
const Color _kDead = Color(0xFF616161);

// ─────────────────────────────────────────────────────────────────────────────
// Layout constants
// ─────────────────────────────────────────────────────────────────────────────

const double _kBoardW = 920.0;
const double _kBoardH = 720.0;

// Track dimensions
const double _kTrackX = 30.0;
const double _kTrackW = 860.0;
const double _kTrackH = 260.0;
const double _kLibTrackY = 15.0;
const double _kFasTrackY = 290.0;

// Policy slot dimensions
const double _kSlotW = 90.0;
const double _kSlotH = 125.0;
const double _kSlotGap = 14.0;

// Player seats
const double _kSeatsY = 570.0;
const double _kSeatsH = 140.0;

// Phase labels
const Map<String, String> _kPhaseLabels = {
  'ROLE_REVEAL': '역할 확인',
  'CHANCELLOR_NOMINATION': '수상 지명',
  'VOTING': '투표 진행',
  'LEGISLATIVE_PRESIDENT': '대통령 입법',
  'LEGISLATIVE_CHANCELLOR': '수상 입법',
  'VETO_RESPONSE': '거부권 응답',
  'EXECUTIVE_ACTION': '대통령 행정 권한',
};



// Exec actions per slot by player count (5-6 default)
const List<String> _kExecActions56 = [
  '', '', '정책 엿보기', '처형\n거부권 행사 가능', '처형\n거부권 행사 가능',
  '히틀러가 수상이\n되면 파시스트 승리',
];
const List<String> _kExecActions78 = [
  '', '조사', '특별 선거', '처형\n거부권 행사 가능', '처형\n거부권 행사 가능',
  '히틀러가 수상이\n되면 파시스트 승리',
];
const List<String> _kExecActions910 = [
  '조사', '조사', '특별 선거', '처형\n거부권 행사 가능', '처형\n거부권 행사 가능',
  '히틀러가 수상이\n되면 파시스트 승리',
];

// ─────────────────────────────────────────────────────────────────────────────
// SecretHitlerBoardRenderer
// ─────────────────────────────────────────────────────────────────────────────

class SecretHitlerBoardRenderer implements GameBoardRenderer {
  final Map<String, String> playerNames;

  late final World _world;
  _SHBoardComponent? _board;
  BoardView? _pendingView;

  SecretHitlerBoardRenderer({required this.playerNames});

  @override
  World get world => _world;

  @override
  Future<void> onMount(FlameGame game) async {
    _world = game.world;
    final board = _SHBoardComponent(playerNames: playerNames);
    _board = board;
    await _world.add(board);

    if (_pendingView != null) {
      onBoardViewUpdate(_pendingView!);
      _pendingView = null;
    }
  }

  @override
  void onBoardViewUpdate(BoardView boardView) {
    if (boardView.data['packId'] != 'secret_hitler') return;
    if (_board == null) {
      _pendingView = boardView;
      return;
    }
    _board!.updateData(boardView.data);
  }

  @override
  void onDispose() {
    _world.removeAll(_world.children.toList());
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main board component — all canvas drawing
// ─────────────────────────────────────────────────────────────────────────────

class _SHBoardComponent extends PositionComponent {
  final Map<String, String> playerNames;

  int _liberalPolicies = 0;
  int _fascistPolicies = 0;
  int _electionTracker = 0;
  String _phase = 'ROLE_REVEAL';
  String? _presidentId;
  String? _chancellorId;
  String? _chancellorCandidateId;
  String? _winner;
  int _deckCount = 0;
  int _discardCount = 0;
  List<String> _playerOrder = [];
  Map<String, dynamic> _playerInfo = {};
  Map<String, String> _completedVotes = {};
  String? _voteResult;

  _SHBoardComponent({required this.playerNames}) {
    anchor = Anchor.center;
    position = Vector2.zero();
    size = Vector2(_kBoardW, _kBoardH);
  }

  void updateData(Map<String, dynamic> data) {
    _liberalPolicies = data['liberalPolicies'] as int? ?? 0;
    _fascistPolicies = data['fascistPolicies'] as int? ?? 0;
    _electionTracker = data['electionTracker'] as int? ?? 0;
    _phase = data['phase'] as String? ?? 'ROLE_REVEAL';
    _presidentId = data['presidentId'] as String?;
    _chancellorId = data['chancellorId'] as String?;
    _chancellorCandidateId = data['chancellorCandidateId'] as String?;
    _winner = data['winner'] as String?;
    _deckCount = data['deckCount'] as int? ?? 0;
    _discardCount = data['discardCount'] as int? ?? 0;
    _playerOrder = List<String>.from(data['playerOrder'] as List? ?? []);
    _playerInfo =
        Map<String, dynamic>.from(data['playerInfo'] as Map? ?? {});
    _voteResult = data['voteResult'] as String?;
    if (data['completedVotes'] != null) {
      _completedVotes =
          Map<String, String>.from(data['completedVotes'] as Map);
    } else {
      _completedVotes = {};
    }
  }

  String _nick(String pid) {
    if (playerNames.containsKey(pid)) return playerNames[pid]!;
    final info = _playerInfo[pid] as Map<String, dynamic>?;
    return info?['nickname'] as String? ?? pid;
  }

  bool _isDead(String pid) {
    final info = _playerInfo[pid] as Map<String, dynamic>?;
    return info?['isDead'] as bool? ?? false;
  }

  List<String> get _execActions {
    final n = _playerOrder.length;
    if (n >= 9) return _kExecActions910;
    if (n >= 7) return _kExecActions78;
    return _kExecActions56;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    _drawBoardBackground(canvas);
    _drawLiberalTrack(canvas);
    _drawFascistTrack(canvas);
    _drawElectionTracker(canvas);
    _drawPlayerSeats(canvas);
    _drawPhaseIndicator(canvas);
    _drawVoteResults(canvas);
    _drawWinnerOverlay(canvas);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BACKGROUND
  // ═══════════════════════════════════════════════════════════════════════════

  void _drawBoardBackground(Canvas canvas) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.x, size.y),
        const Radius.circular(14),
      ),
      Paint()..color = const Color(0xFF0E0E1A),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LIBERAL TRACK
  // ═══════════════════════════════════════════════════════════════════════════

  void _drawLiberalTrack(Canvas canvas) {
    final trackRect =
        Rect.fromLTWH(_kTrackX, _kLibTrackY, _kTrackW, _kTrackH);

    // — Blue background with inner gradient
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_kLibBgLight, _kLibBg],
      ).createShader(trackRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, const Radius.circular(10)),
      bgPaint,
    );

    // — Double border frame
    final borderPaint = Paint()
      ..color = _kLibBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, const Radius.circular(10)),
      borderPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        trackRect.deflate(6), const Radius.circular(7)),
      Paint()
        ..color = _kLibAccent.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // — Roman columns on left and right
    _drawColumn(canvas, _kTrackX + 18, _kLibTrackY + 30, 24, 180, _kLibColumn);
    _drawColumn(canvas, _kTrackX + _kTrackW - 42, _kLibTrackY + 30, 24, 180,
        _kLibColumn);

    // — "LIBERAL" header
    _drawTrackHeader(canvas, 'LIBERAL', _kTrackX, _kLibTrackY, _kTrackW,
        _kLibBorder, _kCream);

    // — "DRAW PILE" indicator (left)
    _drawDeckLabel(
        canvas, 'DRAW\nPILE', _kTrackX + 52, _kLibTrackY + 65, _kLibAccent,
        count: _deckCount);

    // — "DISCARD PILE" indicator (right)
    _drawDeckLabel(canvas, 'DISCARD\nPILE',
        _kTrackX + _kTrackW - 92, _kLibTrackY + 65, _kLibAccent,
        count: _discardCount);

    // — 5 policy slots
    final slotsStartX =
        _kTrackX + (_kTrackW - (5 * _kSlotW + 4 * _kSlotGap)) / 2;
    final slotsY = _kLibTrackY + 55;
    for (int i = 0; i < 5; i++) {
      final x = slotsStartX + i * (_kSlotW + _kSlotGap);
      final isFilled = i < _liberalPolicies;
      _drawPolicySlot(canvas, x, slotsY, _kSlotW, _kSlotH, true, isFilled);
    }

    // — Dove emblem (bottom-right of track)
    _drawDoveEmblem(canvas, _kTrackX + _kTrackW - 90, _kLibTrackY + 150, 70,
        _kLibAccent.withValues(alpha: 0.35));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FASCIST TRACK
  // ═══════════════════════════════════════════════════════════════════════════

  void _drawFascistTrack(Canvas canvas) {
    final trackRect =
        Rect.fromLTWH(_kTrackX, _kFasTrackY, _kTrackW, _kTrackH);

    // — Red/brown background
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_kFasBgLight, _kFasBg],
      ).createShader(trackRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, const Radius.circular(10)),
      bgPaint,
    );

    // — Double border
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, const Radius.circular(10)),
      Paint()
        ..color = _kFasBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        trackRect.deflate(6), const Radius.circular(7)),
      Paint()
        ..color = _kFasAccent.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // — Chain decorations along top and bottom borders
    _drawChainBorder(
        canvas, _kTrackX + 10, _kFasTrackY + 4, _kTrackW - 20, _kFasChain);
    _drawChainBorder(canvas, _kTrackX + 10,
        _kFasTrackY + _kTrackH - 10, _kTrackW - 20, _kFasChain);

    // — "FASCIST" header
    _drawTrackHeader(canvas, 'FASC1ST', _kTrackX, _kFasTrackY, _kTrackW,
        _kFasBorder, _kCream);

    // — 6 policy slots with exec action labels
    final slotsStartX =
        _kTrackX + (_kTrackW - (6 * _kSlotW + 5 * _kSlotGap)) / 2;
    final slotsY = _kFasTrackY + 55;
    final actions = _execActions;
    for (int i = 0; i < 6; i++) {
      final x = slotsStartX + i * (_kSlotW + _kSlotGap);
      final isFilled = i < _fascistPolicies;
      _drawPolicySlot(canvas, x, slotsY, _kSlotW, _kSlotH, false, isFilled);

      // Exec action label below slot
      if (i < actions.length && actions[i].isNotEmpty) {
        _drawExecLabel(canvas, actions[i], x, slotsY + _kSlotH + 4, _kSlotW);
      }
    }

    // — Player count note at bottom
    final noteText = _playerOrder.length <= 6
        ? '5 OR 6 플레이어: 파시스트 1명 그리고 히틀러를 사용합니다.'
        : _playerOrder.length <= 8
            ? '7 OR 8 플레이어: 파시스트 2명 그리고 히틀러를 사용합니다.'
            : '9 OR 10 플레이어: 파시스트 3명 그리고 히틀러를 사용합니다.';
    _drawText(canvas, noteText, _kTrackX + _kTrackW / 2,
        _kFasTrackY + _kTrackH - 16, 9,
        color: _kCream.withValues(alpha: 0.5), center: true);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ELECTION TRACKER (below liberal track)
  // ═══════════════════════════════════════════════════════════════════════════

  void _drawElectionTracker(Canvas canvas) {
    final y = _kLibTrackY + _kTrackH - 28;
    final cx = _kTrackX + _kTrackW / 2;

    // Label
    _drawText(canvas, '선거 트래커', cx - 130, y + 4, 10,
        color: _kCream.withValues(alpha: 0.7));

    // 3 circles for election tracker
    for (int i = 0; i < 3; i++) {
      final dotX = cx - 20 + i * 40.0;
      final isFilled = i < _electionTracker;

      canvas.drawCircle(
        Offset(dotX, y + 6),
        10,
        Paint()
          ..color = isFilled ? _kGold : _kLibAccent.withValues(alpha: 0.3)
          ..style = isFilled ? PaintingStyle.fill : PaintingStyle.stroke
          ..strokeWidth = 2,
      );

      // Arrow between dots
      if (i < 2) {
        _drawText(canvas, '→', dotX + 15, y, 12,
            color: _kCream.withValues(alpha: 0.5));
      }
    }

    // "실패" labels
    _drawText(canvas, '실패', cx - 20, y + 20, 8,
        color: _kCream.withValues(alpha: 0.4), center: true);
    _drawText(canvas, '실패', cx + 20, y + 20, 8,
        color: _kCream.withValues(alpha: 0.4), center: true);
    _drawText(canvas, '실패', cx + 60, y + 20, 8,
        color: _kCream.withValues(alpha: 0.4), center: true);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PLAYER SEATS with wooden President/Chancellor placards
  // ═══════════════════════════════════════════════════════════════════════════

  void _drawPlayerSeats(Canvas canvas) {
    if (_playerOrder.isEmpty) return;

    final n = _playerOrder.length;
    final seatW = math.min(110.0, (_kTrackW - 20) / n - 6);
    final totalW = n * seatW + (n - 1) * 6;
    final startX = _kTrackX + (_kTrackW - totalW) / 2;

    for (int i = 0; i < n; i++) {
      final pid = _playerOrder[i];
      final x = startX + i * (seatW + 6);
      final isDead = _isDead(pid);
      final isPresident = pid == _presidentId;
      final isChancellor = pid == _chancellorId;
      final isCandidate = pid == _chancellorCandidateId;

      // — Background card
      final cardColor = isDead
          ? _kDead.withValues(alpha: 0.3)
          : isPresident
              ? _kWoodLight.withValues(alpha: 0.15)
              : isChancellor
                  ? _kLibAccent.withValues(alpha: 0.12)
                  : const Color(0xFF1E2A45).withValues(alpha: 0.7);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, _kSeatsY, seatW, _kSeatsH),
          const Radius.circular(8),
        ),
        Paint()..color = cardColor,
      );

      // — Wooden placard for President / Chancellor
      if (isPresident && !isDead) {
        _drawWoodenPlacard(canvas, 'PRESIDENT', x + 4, _kSeatsY + 4,
            seatW - 8, 28);
      } else if ((isChancellor || isCandidate) && !isDead) {
        _drawWoodenPlacard(canvas, 'CHANCELLOR', x + 4, _kSeatsY + 4,
            seatW - 8, 28);
      }

      // — Player avatar circle
      final avatarY = _kSeatsY + (isPresident || isChancellor || isCandidate
          ? 52 : 30);
      final avatarR = 22.0;
      final avatarColor = isDead
          ? _kDead
          : isPresident
              ? _kWoodLight
              : isChancellor || isCandidate
                  ? _kLibAccent
                  : const Color(0xFF5C6B8A);

      canvas.drawCircle(
        Offset(x + seatW / 2, avatarY),
        avatarR,
        Paint()..color = avatarColor.withValues(alpha: 0.2),
      );
      canvas.drawCircle(
        Offset(x + seatW / 2, avatarY),
        avatarR,
        Paint()
          ..color = avatarColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );

      // Initial letter
      final name = _nick(pid);
      _drawText(canvas, name.isNotEmpty ? name[0].toUpperCase() : '?',
          x + seatW / 2, avatarY - 7, 16,
          color: avatarColor, center: true, bold: true);

      // — Player name
      _drawText(canvas, name, x + seatW / 2, avatarY + avatarR + 6, 11,
          color: isDead ? _kDead : _kTextLight,
          center: true,
          maxWidth: seatW - 8);

      // — Vote badge (if voting phase)
      if (_completedVotes.containsKey(pid)) {
        final vote = _completedVotes[pid]!;
        final voteColor =
            vote == 'JA' ? const Color(0xFF4CAF50) : _kFasAccent;
        final voteText = vote == 'JA' ? 'Ja!' : 'Nein!';
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x + seatW - 32, _kSeatsY + _kSeatsH - 22, 28, 16),
            const Radius.circular(4),
          ),
          Paint()..color = voteColor.withValues(alpha: 0.8),
        );
        _drawText(canvas, voteText, x + seatW - 18,
            _kSeatsY + _kSeatsH - 20, 9,
            color: _kCream, center: true, bold: true);
      }

      // — Dead X overlay
      if (isDead) {
        final p = Paint()
          ..color = _kFasAccent.withValues(alpha: 0.6)
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke;
        canvas.drawLine(
          Offset(x + 10, _kSeatsY + 10),
          Offset(x + seatW - 10, _kSeatsY + _kSeatsH - 10),
          p,
        );
        canvas.drawLine(
          Offset(x + seatW - 10, _kSeatsY + 10),
          Offset(x + 10, _kSeatsY + _kSeatsH - 10),
          p,
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DRAWING HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Draw a Roman-style column pillar
  void _drawColumn(Canvas canvas, double x, double y, double w, double h,
      Color color) {
    final paint = Paint()..color = color.withValues(alpha: 0.35);

    // Capital (top decorative piece)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 4, y, w + 8, 12),
        const Radius.circular(3),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 2, y + 10, w + 4, 6),
        const Radius.circular(2),
      ),
      paint,
    );

    // Shaft
    canvas.drawRect(
      Rect.fromLTWH(x, y + 16, w, h - 30),
      paint,
    );
    // Fluting lines
    for (int i = 0; i < 3; i++) {
      canvas.drawLine(
        Offset(x + 6 + i * 7.0, y + 18),
        Offset(x + 6 + i * 7.0, y + h - 16),
        Paint()
          ..color = color.withValues(alpha: 0.15)
          ..strokeWidth = 1,
      );
    }

    // Base
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 2, y + h - 14, w + 4, 6),
        const Radius.circular(2),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 4, y + h - 8, w + 8, 10),
        const Radius.circular(3),
      ),
      paint,
    );
  }

  /// Draw chain border decoration (fascist track)
  void _drawChainBorder(
      Canvas canvas, double x, double y, double width, Color color) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final linkW = 12.0;
    final count = (width / linkW).floor();
    for (int i = 0; i < count; i++) {
      final lx = x + i * linkW;
      canvas.drawOval(
        Rect.fromLTWH(lx, y, linkW - 2, 6),
        paint,
      );
    }
  }

  /// Draw "LIBERAL" / "FASC1ST" track header
  void _drawTrackHeader(Canvas canvas, String text, double trackX,
      double trackY, double trackW, Color lineColor, Color textColor) {
    // Decorative lines flanking the title
    final midX = trackX + trackW / 2;
    final lineY = trackY + 22;
    canvas.drawLine(
      Offset(trackX + 50, lineY),
      Offset(midX - 80, lineY),
      Paint()
        ..color = lineColor.withValues(alpha: 0.4)
        ..strokeWidth = 1.5,
    );
    canvas.drawLine(
      Offset(midX + 80, lineY),
      Offset(trackX + trackW - 50, lineY),
      Paint()
        ..color = lineColor.withValues(alpha: 0.4)
        ..strokeWidth = 1.5,
    );

    // Header text
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: textColor,
          fontSize: 26,
          fontWeight: FontWeight.w900,
          letterSpacing: 8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(midX - tp.width / 2, trackY + 8));
  }

  /// Draw a single policy slot (empty or filled with policy card)
  void _drawPolicySlot(Canvas canvas, double x, double y, double w, double h,
      bool isLiberal, bool isFilled) {
    final slotRect = Rect.fromLTWH(x, y, w, h);

    if (!isFilled) {
      // Empty slot — dashed border
      canvas.drawRRect(
        RRect.fromRectAndRadius(slotRect, const Radius.circular(6)),
        Paint()
          ..color = (isLiberal ? _kLibAccent : _kFasAccent)
              .withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      // Crosshair/dot in center
      canvas.drawCircle(
        Offset(x + w / 2, y + h / 2),
        4,
        Paint()
          ..color = (isLiberal ? _kLibAccent : _kFasAccent)
              .withValues(alpha: 0.2),
      );
    } else {
      // Filled policy card — cream background with colored border
      _drawPolicyCard(canvas, x, y, w, h, isLiberal);
    }
  }

  /// Draw a filled policy card (authentic "LIBERAL/FASCIST ARTICLE" style)
  void _drawPolicyCard(Canvas canvas, double x, double y, double w, double h,
      bool isLiberal) {
    final cardRect = Rect.fromLTWH(x, y, w, h);
    final color = isLiberal ? _kLibAccent : _kFasAccent;

    // Cream base
    canvas.drawRRect(
      RRect.fromRectAndRadius(cardRect, const Radius.circular(6)),
      Paint()..color = _kCream,
    );

    // Colored border (inner frame)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        cardRect.deflate(4), const Radius.circular(4)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Icon (dove or skull)
    final iconY = y + 18;
    if (isLiberal) {
      _drawSmallDove(canvas, x + w / 2, iconY, 18, color);
    } else {
      _drawSmallSkull(canvas, x + w / 2, iconY, 16, color);
    }

    // "LIBERAL" or "FASC1ST" text
    final label = isLiberal ? 'LIBERAL' : 'FASC1ST';
    _drawText(canvas, label, x + w / 2, y + 50, 11,
        color: color, center: true, bold: true);

    // "ARTICLE" text
    _drawText(canvas, 'ARTICLE', x + w / 2, y + 65, 9,
        color: color.withValues(alpha: 0.7), center: true);

    // Decorative lines (document style)
    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..strokeWidth = 1;
    for (int i = 0; i < 4; i++) {
      final ly = y + 82 + i * 8.0;
      canvas.drawLine(
        Offset(x + 12, ly), Offset(x + w - 12, ly), linePaint);
    }
  }

  /// Draw the dove emblem (liberal track background decoration)
  void _drawDoveEmblem(
      Canvas canvas, double cx, double cy, double size, Color color) {
    final paint = Paint()..color = color;

    // Body (oval)
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, cy), width: size * 0.5, height: size * 0.3),
      paint,
    );

    // Left wing
    final lwing = Path()
      ..moveTo(cx - size * 0.1, cy - size * 0.05)
      ..quadraticBezierTo(
          cx - size * 0.45, cy - size * 0.5, cx - size * 0.3, cy + size * 0.1);
    canvas.drawPath(lwing, paint);

    // Right wing
    final rwing = Path()
      ..moveTo(cx + size * 0.1, cy - size * 0.05)
      ..quadraticBezierTo(
          cx + size * 0.45, cy - size * 0.5, cx + size * 0.3, cy + size * 0.1);
    canvas.drawPath(rwing, paint);

    // Head
    canvas.drawCircle(
      Offset(cx + size * 0.2, cy - size * 0.12),
      size * 0.08,
      paint,
    );

    // Laurel wreath arcs
    final wreathPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawArc(
      Rect.fromCenter(
          center: Offset(cx, cy + size * 0.1),
          width: size * 0.7,
          height: size * 0.4),
      math.pi * 0.2,
      math.pi * 0.6,
      false,
      wreathPaint,
    );
    canvas.drawArc(
      Rect.fromCenter(
          center: Offset(cx, cy + size * 0.1),
          width: size * 0.7,
          height: size * 0.4),
      -math.pi * 0.8,
      math.pi * 0.6,
      false,
      wreathPaint,
    );
  }

  /// Draw small dove icon for policy card
  void _drawSmallDove(
      Canvas canvas, double cx, double cy, double s, Color color) {
    final p = Paint()..color = color;
    // Simplified dove: body + wings
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, cy), width: s * 0.65, height: s * 0.35),
      p,
    );
    final wing = Path()
      ..moveTo(cx, cy - s * 0.05)
      ..quadraticBezierTo(cx - s * 0.4, cy - s * 0.55, cx - s * 0.15, cy)
      ..quadraticBezierTo(cx + s * 0.4, cy - s * 0.55, cx + s * 0.15, cy);
    canvas.drawPath(wing, p);
    canvas.drawCircle(Offset(cx + s * 0.2, cy - s * 0.12), s * 0.1, p);
  }

  /// Draw small skull icon for policy card
  void _drawSmallSkull(
      Canvas canvas, double cx, double cy, double s, Color color) {
    final p = Paint()..color = color;

    // Skull head
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, cy - s * 0.1),
          width: s * 0.85,
          height: s * 0.75),
      p,
    );

    // Eye sockets
    final eyeP = Paint()..color = _kCream;
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx - s * 0.15, cy - s * 0.15),
          width: s * 0.22,
          height: s * 0.2),
      eyeP,
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx + s * 0.15, cy - s * 0.15),
          width: s * 0.22,
          height: s * 0.2),
      eyeP,
    );

    // Nose
    final nose = Path()
      ..moveTo(cx, cy)
      ..lineTo(cx - s * 0.06, cy + s * 0.1)
      ..lineTo(cx + s * 0.06, cy + s * 0.1)
      ..close();
    canvas.drawPath(nose, eyeP);

    // Jaw
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
            cx - s * 0.28, cy + s * 0.15, s * 0.56, s * 0.2),
        const Radius.circular(3),
      ),
      p,
    );
    // Teeth lines
    for (int i = 0; i < 3; i++) {
      canvas.drawLine(
        Offset(cx - s * 0.15 + i * s * 0.15, cy + s * 0.17),
        Offset(cx - s * 0.15 + i * s * 0.15, cy + s * 0.33),
        Paint()
          ..color = _kCream
          ..strokeWidth = 1,
      );
    }
  }

  /// Draw wooden placard (President / Chancellor nameplate)
  void _drawWoodenPlacard(
      Canvas canvas, String text, double x, double y, double w, double h) {
    final placardRect = Rect.fromLTWH(x, y, w, h);

    // Wood background gradient
    final woodPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_kWoodLight, _kWoodMid, _kWoodDark],
        stops: [0.0, 0.5, 1.0],
      ).createShader(placardRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(placardRect, const Radius.circular(3)),
      woodPaint,
    );

    // Wood grain lines
    final grainPaint = Paint()
      ..color = _kWoodGrain.withValues(alpha: 0.25)
      ..strokeWidth = 0.5;
    for (int i = 0; i < 5; i++) {
      final gy = y + 4 + i * (h / 5);
      canvas.drawLine(
          Offset(x + 3, gy), Offset(x + w - 3, gy), grainPaint);
    }

    // Dark border
    canvas.drawRRect(
      RRect.fromRectAndRadius(placardRect, const Radius.circular(3)),
      Paint()
        ..color = const Color(0xFF4A3520)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Text
    _drawText(canvas, text, x + w / 2, y + (h - 12) / 2, 10,
        color: _kTextDark, center: true, bold: true, letterSpacing: 3);
  }

  /// Draw deck/discard pile label
  void _drawDeckLabel(Canvas canvas, String label, double x, double y,
      Color color, {int count = 0}) {
    // Stack icon
    final iconPaint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (int i = 0; i < 3; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
              x + 5 - i * 2.0, y + 20 - i * 3.0, 30, 40),
          const Radius.circular(3),
        ),
        iconPaint,
      );
    }

    // Label
    _drawText(canvas, label, x + 20, y + 68, 8,
        color: color.withValues(alpha: 0.5), center: true);

    // Count
    if (count > 0) {
      _drawText(canvas, '$count', x + 20, y + 88, 12,
          color: color.withValues(alpha: 0.7), center: true, bold: true);
    }
  }

  /// Draw executive action label below fascist slot
  void _drawExecLabel(
      Canvas canvas, String text, double x, double y, double w) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: _kCream.withValues(alpha: 0.5),
          fontSize: 7,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: w);
    tp.paint(canvas, Offset(x + (w - tp.width) / 2, y));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE INDICATOR
  // ═══════════════════════════════════════════════════════════════════════════

  void _drawPhaseIndicator(Canvas canvas) {
    final label = _kPhaseLabels[_phase] ?? _phase;
    final y = _kFasTrackY + _kTrackH + 8;

    // Phase chip
    final tp = TextPainter(
      text: TextSpan(
        text: '  $label  ',
        style: const TextStyle(
          color: _kGold,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final chipX = _kTrackX + _kTrackW / 2 - tp.width / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(chipX - 4, y, tp.width + 8, 22),
        const Radius.circular(11),
      ),
      Paint()..color = _kGold.withValues(alpha: 0.12),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(chipX - 4, y, tp.width + 8, 22),
        const Radius.circular(11),
      ),
      Paint()
        ..color = _kGold.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    tp.paint(canvas, Offset(chipX, y + 3));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VOTE RESULTS
  // ═══════════════════════════════════════════════════════════════════════════

  void _drawVoteResults(Canvas canvas) {
    if (_completedVotes.isEmpty || _voteResult == null) return;
    if (_phase != 'VOTING' &&
        _phase != 'LEGISLATIVE_PRESIDENT' &&
        _phase != 'LEGISLATIVE_CHANCELLOR') {
      return;
    }

    final isPass = _voteResult == 'PASSED';
    final color = isPass ? const Color(0xFF4CAF50) : _kFasAccent;
    final text = isPass ? '가결' : '부결';

    // Badge
    final bx = _kTrackX + _kTrackW / 2;
    final by = _kFasTrackY + _kTrackH + 34;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(bx - 40, by, 80, 24),
        const Radius.circular(12),
      ),
      Paint()..color = color,
    );
    _drawText(canvas, text, bx, by + 4, 14,
        color: _kCream, center: true, bold: true);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WINNER OVERLAY
  // ═══════════════════════════════════════════════════════════════════════════

  void _drawWinnerOverlay(Canvas canvas) {
    if (_winner == null) return;

    final isLiberal = _winner == 'LIBERAL';
    final color = isLiberal ? _kLibAccent : _kFasAccent;
    final teamLabel = isLiberal ? '자유주의 승리!' : '파시스트 승리!';

    // Dim overlay
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.x, size.y),
        const Radius.circular(14),
      ),
      Paint()..color = const Color(0xCC000000),
    );

    // Winner text
    final tp = TextPainter(
      text: TextSpan(
        text: teamLabel,
        style: TextStyle(
          color: color,
          fontSize: 38,
          fontWeight: FontWeight.w900,
          letterSpacing: 4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas,
        Offset((size.x - tp.width) / 2, (size.y - tp.height) / 2));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TEXT UTILITY
  // ═══════════════════════════════════════════════════════════════════════════

  void _drawText(Canvas canvas, String text, double x, double y, double fontSize,
      {Color color = _kTextLight,
      bool center = false,
      bool bold = false,
      double? maxWidth,
      double letterSpacing = 0}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
          letterSpacing: letterSpacing,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? 400);
    if (center) {
      tp.paint(canvas, Offset(x - tp.width / 2, y));
    } else {
      tp.paint(canvas, Offset(x, y));
    }
  }
}
