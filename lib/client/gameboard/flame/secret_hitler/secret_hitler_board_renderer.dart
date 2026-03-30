import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart';

import '../../../../shared/game_pack/game_board_renderer.dart';
import '../../../../shared/game_pack/views/board_view.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Color palette — dark moody Secret Hitler aesthetic
// ─────────────────────────────────────────────────────────────────────────────

const Color _kBgDark = Color(0xFF1A1A2E);
const Color _kBgMid = Color(0xFF16213E);
const Color _kBgLight = Color(0xFF0F3460);

const Color _kLiberalBlue = Color(0xFF2196F3);
const Color _kLiberalLight = Color(0xFF64B5F6);
const Color _kLiberalDark = Color(0xFF1565C0);

const Color _kFascistRed = Color(0xFFE53935);
const Color _kFascistLight = Color(0xFFEF5350);
const Color _kFascistDark = Color(0xFFC62828);

const Color _kGold = Color(0xFFFFD54F);
const Color _kGoldDark = Color(0xFFF9A825);


const Color _kTextLight = Color(0xFFF5F5F5);
const Color _kTextMuted = Color(0xFFBDBDBD);
const Color _kDead = Color(0xFF616161);
const Color _kAlive = Color(0xFFE0E0E0);

// ─────────────────────────────────────────────────────────────────────────────
// Layout constants
// ─────────────────────────────────────────────────────────────────────────────

const double _kBoardWidth = 900.0;
const double _kBoardHeight = 520.0;

const double _kTrackSlotSize = 60.0;
const double _kTrackSlotGap = 10.0;
const double _kTrackHeight = 80.0;
const double _kTrackY = -80.0;

const double _kTrackerY = 60.0;

const double _kPlayerSeatRadius = 200.0;
const double _kPlayerSeatY = 190.0;

// Phase Korean labels
const Map<String, String> _kPhaseLabels = {
  'ROLE_REVEAL': '역할 확인',
  'CHANCELLOR_NOMINATION': '수상 지명',
  'VOTING': '투표 진행',
  'LEGISLATIVE_PRESIDENT': '대통령 입법',
  'LEGISLATIVE_CHANCELLOR': '수상 입법',
  'VETO_RESPONSE': '거부권 응답',
  'EXECUTIVE_ACTION': '대통령 행정 권한',
};

// Executive action display names
const Map<String, String> _kExecLabels = {
  'INVESTIGATE': '조사',
  'SPECIAL_ELECTION': '특별 선거',
  'EXECUTION': '처형',
  'POLICY_PEEK': '정책 엿보기',
  'NONE': '',
};

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
// Main board composite component
// ─────────────────────────────────────────────────────────────────────────────

class _SHBoardComponent extends PositionComponent {
  final Map<String, String> playerNames;

  // Cached data
  int _liberalPolicies = 0;
  int _fascistPolicies = 0;
  int _electionTracker = 0;
  String _phase = 'ROLE_REVEAL';
  String? _presidentId;
  String? _chancellorId;
  String? _chancellorCandidateId;
  String? _winner;
  String _execType = 'NONE';
  int _deckCount = 0;
  int _discardCount = 0;
  List<String> _playerOrder = [];
  Map<String, dynamic> _playerInfo = {};
  Map<String, String> _completedVotes = {};
  String? _voteResult;

  _SHBoardComponent({required this.playerNames}) {
    anchor = Anchor.center;
    position = Vector2.zero();
    size = Vector2(_kBoardWidth, _kBoardHeight);
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
    _execType = data['executiveActionType'] as String? ?? 'NONE';
    _deckCount = data['deckCount'] as int? ?? 0;
    _discardCount = data['discardCount'] as int? ?? 0;
    _playerOrder =
        List<String>.from(data['playerOrder'] as List? ?? []);
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

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    _drawBackground(canvas);
    _drawTitle(canvas);
    _drawLiberalTrack(canvas);
    _drawFascistTrack(canvas);
    _drawElectionTracker(canvas);
    _drawPlayerSeats(canvas);
    _drawPhaseInfo(canvas);
    _drawDeckInfo(canvas);
    _drawVoteResults(canvas);
    _drawWinnerOverlay(canvas);
  }

  // ── Background ────────────────────────────────────────────────────────────

  void _drawBackground(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);

    // Dark gradient background
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [_kBgDark, _kBgMid, _kBgDark],
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(20)),
      Paint()..shader = gradient.createShader(rect),
    );

    // Subtle border
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(20)),
      Paint()
        ..color = _kGold.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Inner glow border
    final innerRect = rect.deflate(8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(innerRect, const Radius.circular(16)),
      Paint()
        ..color = _kGold.withValues(alpha: 0.06)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  // ── Title ─────────────────────────────────────────────────────────────────

  void _drawTitle(Canvas canvas) {
    final titlePainter = TextPainter(
      text: const TextSpan(
        text: 'SECRET HITLER',
        style: TextStyle(
          color: _kGold,
          fontSize: 22,
          fontWeight: FontWeight.w900,
          letterSpacing: 6,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    titlePainter.paint(
      canvas,
      Offset((size.x - titlePainter.width) / 2, 14),
    );
  }

  // ── Liberal Track (Blue) ──────────────────────────────────────────────────

  void _drawLiberalTrack(Canvas canvas) {
    const int totalSlots = 5;
    final trackWidth =
        totalSlots * _kTrackSlotSize + (totalSlots - 1) * _kTrackSlotGap;
    final startX = (size.x - trackWidth) / 2 - 130;
    final trackYLocal = size.y / 2 + _kTrackY;

    // Track background
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
          startX - 12, trackYLocal - 12, trackWidth + 24, _kTrackHeight + 24),
      const Radius.circular(14),
    );
    canvas.drawRRect(
      trackRect,
      Paint()..color = _kLiberalDark.withValues(alpha: 0.35),
    );
    canvas.drawRRect(
      trackRect,
      Paint()
        ..color = _kLiberalBlue.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Label
    final labelPainter = TextPainter(
      text: const TextSpan(
        text: 'LIBERAL',
        style: TextStyle(
          color: _kLiberalLight,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    labelPainter.paint(
      canvas,
      Offset(startX - 4, trackYLocal - 10),
    );

    for (int i = 0; i < totalSlots; i++) {
      final x = startX + i * (_kTrackSlotSize + _kTrackSlotGap);
      final slotRect =
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, trackYLocal + 6, _kTrackSlotSize, _kTrackSlotSize),
            const Radius.circular(10),
          );

      if (i < _liberalPolicies) {
        // Filled slot
        canvas.drawRRect(
          slotRect,
          Paint()..color = _kLiberalBlue,
        );
        // Eagle symbol
        _drawPolicySymbol(canvas, x + _kTrackSlotSize / 2,
            trackYLocal + 6 + _kTrackSlotSize / 2, true);
      } else {
        // Empty slot
        canvas.drawRRect(
          slotRect,
          Paint()..color = _kLiberalDark.withValues(alpha: 0.2),
        );
        canvas.drawRRect(
          slotRect,
          Paint()
            ..color = _kLiberalBlue.withValues(alpha: 0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
        // Slot number
        final numPainter = TextPainter(
          text: TextSpan(
            text: '${i + 1}',
            style: TextStyle(
              color: _kLiberalBlue.withValues(alpha: 0.3),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        numPainter.paint(
          canvas,
          Offset(x + (_kTrackSlotSize - numPainter.width) / 2,
              trackYLocal + 6 + (_kTrackSlotSize - numPainter.height) / 2),
        );
      }
    }
  }

  // ── Fascist Track (Red) ───────────────────────────────────────────────────

  void _drawFascistTrack(Canvas canvas) {
    const int totalSlots = 6;
    final trackWidth =
        totalSlots * _kTrackSlotSize + (totalSlots - 1) * _kTrackSlotGap;
    final startX = (size.x - trackWidth) / 2 + 130;
    final trackYLocal = size.y / 2 + _kTrackY;

    // Track background
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
          startX - 12, trackYLocal - 12, trackWidth + 24, _kTrackHeight + 24),
      const Radius.circular(14),
    );
    canvas.drawRRect(
      trackRect,
      Paint()..color = _kFascistDark.withValues(alpha: 0.35),
    );
    canvas.drawRRect(
      trackRect,
      Paint()
        ..color = _kFascistRed.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Label
    final labelPainter = TextPainter(
      text: const TextSpan(
        text: 'FASCIST',
        style: TextStyle(
          color: _kFascistLight,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    labelPainter.paint(
      canvas,
      Offset(startX - 4, trackYLocal - 10),
    );

    // Executive power labels for fascist track
    final execPowers = _getExecPowers(_playerOrder.length);

    for (int i = 0; i < totalSlots; i++) {
      final x = startX + i * (_kTrackSlotSize + _kTrackSlotGap);
      final slotRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, trackYLocal + 6, _kTrackSlotSize, _kTrackSlotSize),
        const Radius.circular(10),
      );

      if (i < _fascistPolicies) {
        // Filled slot
        canvas.drawRRect(slotRect, Paint()..color = _kFascistRed);
        _drawPolicySymbol(canvas, x + _kTrackSlotSize / 2,
            trackYLocal + 6 + _kTrackSlotSize / 2, false);
      } else {
        // Empty slot
        canvas.drawRRect(
          slotRect,
          Paint()..color = _kFascistDark.withValues(alpha: 0.2),
        );
        canvas.drawRRect(
          slotRect,
          Paint()
            ..color = _kFascistRed.withValues(alpha: 0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }

      // Executive power label below slot
      if (i < execPowers.length && execPowers[i].isNotEmpty) {
        final powerPainter = TextPainter(
          text: TextSpan(
            text: execPowers[i],
            style: TextStyle(
              color: _kFascistLight.withValues(alpha: 0.7),
              fontSize: 7,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        powerPainter.paint(
          canvas,
          Offset(x + (_kTrackSlotSize - powerPainter.width) / 2,
              trackYLocal + 6 + _kTrackSlotSize + 4),
        );
      }
    }
  }

  /// Returns exec power labels by fascist slot position for given player count.
  List<String> _getExecPowers(int count) {
    if (count >= 9) {
      return ['조사', '조사', '특별선거', '처형', '처형', ''];
    } else if (count >= 7) {
      return ['', '조사', '특별선거', '처형', '처형', ''];
    } else {
      return ['', '', '엿보기', '처형', '처형', ''];
    }
  }

  // ── Policy Symbol ─────────────────────────────────────────────────────────

  void _drawPolicySymbol(
      Canvas canvas, double cx, double cy, bool isLiberal) {
    final paint = Paint()
      ..color = isLiberal
          ? const Color(0xFFE3F2FD)
          : const Color(0xFFFFEBEE)
      ..style = PaintingStyle.fill;

    if (isLiberal) {
      // Dove / peace symbol — simple star
      final path = Path();
      for (int i = 0; i < 5; i++) {
        final angle = -math.pi / 2 + i * 2 * math.pi / 5;
        final x = cx + 14 * math.cos(angle);
        final y = cy + 14 * math.sin(angle);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      canvas.drawPath(path, paint);
    } else {
      // Skull symbol — simple skull shape
      canvas.drawCircle(Offset(cx, cy - 3), 12, paint);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, cy + 8), width: 14, height: 8),
          const Radius.circular(2),
        ),
        paint,
      );
      // Eyes
      final eyePaint = Paint()..color = _kFascistDark;
      canvas.drawCircle(Offset(cx - 4, cy - 5), 3, eyePaint);
      canvas.drawCircle(Offset(cx + 4, cy - 5), 3, eyePaint);
    }
  }

  // ── Election Tracker ──────────────────────────────────────────────────────

  void _drawElectionTracker(Canvas canvas) {
    const int totalSlots = 3;
    const slotSize = 30.0;
    const gap = 12.0;
    final totalWidth = totalSlots * slotSize + (totalSlots - 1) * gap;
    final startX = (size.x - totalWidth) / 2;
    final y = size.y / 2 + _kTrackerY;

    // Label
    final labelPainter = TextPainter(
      text: const TextSpan(
        text: '선거 트래커',
        style: TextStyle(
          color: _kTextMuted,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    labelPainter.paint(
      canvas,
      Offset((size.x - labelPainter.width) / 2, y - 16),
    );

    for (int i = 0; i < totalSlots; i++) {
      final x = startX + i * (slotSize + gap);
      final center = Offset(x + slotSize / 2, y + slotSize / 2);

      if (i < _electionTracker) {
        // Filled
        canvas.drawCircle(center, slotSize / 2, Paint()..color = _kGold);
        canvas.drawCircle(
            center, slotSize / 2 - 2, Paint()..color = _kGoldDark);

        // X mark
        final xPaint = Paint()
          ..color = _kBgDark
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
            center + const Offset(-6, -6), center + const Offset(6, 6), xPaint);
        canvas.drawLine(
            center + const Offset(6, -6), center + const Offset(-6, 6), xPaint);
      } else {
        // Empty
        canvas.drawCircle(
          center,
          slotSize / 2,
          Paint()
            ..color = _kGold.withValues(alpha: 0.15)
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          center,
          slotSize / 2,
          Paint()
            ..color = _kGold.withValues(alpha: 0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }

    // "3 failures = chaos" label
    if (_electionTracker >= 2) {
      final warnPainter = TextPainter(
        text: const TextSpan(
          text: '⚠ 혼란 임박!',
          style: TextStyle(
            color: _kGold,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      warnPainter.paint(
        canvas,
        Offset((size.x - warnPainter.width) / 2,
            y + slotSize + 6),
      );
    }
  }

  // ── Player Seats ──────────────────────────────────────────────────────────

  void _drawPlayerSeats(Canvas canvas) {
    if (_playerOrder.isEmpty) return;

    final centerX = size.x / 2;
    final centerY = _kPlayerSeatY + size.y / 2 - 80;
    final count = _playerOrder.length;

    for (int i = 0; i < count; i++) {
      final pid = _playerOrder[i];
      final info = _playerInfo[pid] as Map<String, dynamic>? ?? {};
      final nickname =
          playerNames[pid] ?? info['nickname'] as String? ?? pid;
      final isDead = info['isDead'] as bool? ?? false;

      // Arc layout
      final angle = math.pi + (math.pi * i / (count - 1));
      final x = centerX + _kPlayerSeatRadius * math.cos(angle);
      final y = centerY + _kPlayerSeatRadius * 0.4 * math.sin(angle);

      _drawPlayerSeat(
        canvas,
        x,
        y,
        nickname,
        isDead: isDead,
        isPresident: pid == _presidentId,
        isChancellor: pid == _chancellorId,
        isCandidate: pid == _chancellorCandidateId &&
            pid != _chancellorId,
      );
    }
  }

  void _drawPlayerSeat(
    Canvas canvas,
    double x,
    double y,
    String name, {
    bool isDead = false,
    bool isPresident = false,
    bool isChancellor = false,
    bool isCandidate = false,
  }) {
    final radius = 24.0;

    // Ring color
    Color ringColor = _kAlive.withValues(alpha: 0.4);
    if (isDead) {
      ringColor = _kDead.withValues(alpha: 0.3);
    } else if (isPresident) {
      ringColor = _kGold;
    } else if (isChancellor) {
      ringColor = _kLiberalBlue;
    } else if (isCandidate) {
      ringColor = _kGold.withValues(alpha: 0.5);
    }

    // Background circle
    canvas.drawCircle(
      Offset(x, y),
      radius,
      Paint()..color = isDead ? _kDead.withValues(alpha: 0.2) : _kBgLight.withValues(alpha: 0.4),
    );

    // Ring
    canvas.drawCircle(
      Offset(x, y),
      radius,
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = isDead ? 1.5 : 2.5,
    );

    // Death X
    if (isDead) {
      final xPaint = Paint()
        ..color = _kFascistRed.withValues(alpha: 0.6)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(x - 10, y - 10),
        Offset(x + 10, y + 10),
        xPaint,
      );
      canvas.drawLine(
        Offset(x + 10, y - 10),
        Offset(x - 10, y + 10),
        xPaint,
      );
    }

    // Initial letter
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final initialPainter = TextPainter(
      text: TextSpan(
        text: initial,
        style: TextStyle(
          color: isDead ? _kDead : _kTextLight,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    initialPainter.paint(
      canvas,
      Offset(x - initialPainter.width / 2, y - initialPainter.height / 2),
    );

    // Name label below
    final truncatedName = name.length > 8 ? '${name.substring(0, 7)}…' : name;
    final namePainter = TextPainter(
      text: TextSpan(
        text: truncatedName,
        style: TextStyle(
          color: isDead ? _kDead : _kTextMuted,
          fontSize: 9,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    namePainter.paint(
      canvas,
      Offset(x - namePainter.width / 2, y + radius + 4),
    );

    // Role badge
    if (isPresident) {
      _drawBadge(canvas, x, y - radius - 8, '대통령', _kGold, _kBgDark);
    } else if (isChancellor) {
      _drawBadge(canvas, x, y - radius - 8, '수상', _kLiberalBlue, _kTextLight);
    } else if (isCandidate) {
      _drawBadge(
          canvas, x, y - radius - 8, '후보', _kGold.withValues(alpha: 0.7), _kBgDark);
    }
  }

  void _drawBadge(Canvas canvas, double x, double y, String text,
      Color bgColor, Color textColor) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: textColor,
          fontSize: 8,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(x, y),
        width: painter.width + 10,
        height: painter.height + 6,
      ),
      const Radius.circular(6),
    );
    canvas.drawRRect(badgeRect, Paint()..color = bgColor);
    painter.paint(
      canvas,
      Offset(x - painter.width / 2, y - painter.height / 2),
    );
  }

  // ── Phase Info ────────────────────────────────────────────────────────────

  void _drawPhaseInfo(Canvas canvas) {
    final phaseLabel = _kPhaseLabels[_phase] ?? _phase;
    String statusText = phaseLabel;

    if (_phase == 'EXECUTIVE_ACTION') {
      final execLabel = _kExecLabels[_execType] ?? _execType;
      statusText = '$phaseLabel: $execLabel';
    }

    final painter = TextPainter(
      text: TextSpan(
        text: statusText,
        style: const TextStyle(
          color: _kGold,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.x / 2, 46),
        width: painter.width + 28,
        height: painter.height + 14,
      ),
      const Radius.circular(8),
    );
    canvas.drawRRect(
        bgRect, Paint()..color = _kGold.withValues(alpha: 0.1));
    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = _kGold.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    painter.paint(
      canvas,
      Offset((size.x - painter.width) / 2, 46 - painter.height / 2),
    );
  }

  // ── Deck/Discard Info ─────────────────────────────────────────────────────

  void _drawDeckInfo(Canvas canvas) {
    // Deck (left side)
    _drawInfoBox(canvas, 30, size.y - 50, '덱', '$_deckCount', _kBgLight);
    // Discard (right side)
    _drawInfoBox(
        canvas, size.x - 90, size.y - 50, '버림', '$_discardCount', _kBgLight);
  }

  void _drawInfoBox(Canvas canvas, double x, double y, String label,
      String value, Color color) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, 60, 36),
      const Radius.circular(8),
    );
    canvas.drawRRect(rect, Paint()..color = color.withValues(alpha: 0.4));
    canvas.drawRRect(
      rect,
      Paint()
        ..color = _kTextMuted.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final labelPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: _kTextMuted.withValues(alpha: 0.7),
          fontSize: 8,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    labelPainter.paint(canvas, Offset(x + (60 - labelPainter.width) / 2, y + 4));

    final valuePainter = TextPainter(
      text: TextSpan(
        text: value,
        style: const TextStyle(
          color: _kTextLight,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    valuePainter.paint(
        canvas, Offset(x + (60 - valuePainter.width) / 2, y + 16));
  }

  // ── Vote Results ──────────────────────────────────────────────────────────

  void _drawVoteResults(Canvas canvas) {
    if (_completedVotes.isEmpty || _voteResult == null) return;
    if (_phase != 'VOTING' &&
        _phase != 'LEGISLATIVE_PRESIDENT' &&
        _phase != 'LEGISLATIVE_CHANCELLOR') {
      return;
    }

    final isPass = _voteResult == 'PASSED';
    final resultColor = isPass ? _kLiberalBlue : _kFascistRed;
    final resultText = isPass ? '가결' : '부결';

    // Result badge
    final painter = TextPainter(
      text: TextSpan(
        text: '투표 $resultText',
        style: TextStyle(
          color: resultColor,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.x / 2, size.y - 24),
        width: painter.width + 22,
        height: painter.height + 10,
      ),
      const Radius.circular(6),
    );
    canvas.drawRRect(
        bgRect, Paint()..color = resultColor.withValues(alpha: 0.15));
    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = resultColor.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    painter.paint(
      canvas,
      Offset((size.x - painter.width) / 2, size.y - 24 - painter.height / 2),
    );
  }

  // ── Winner Overlay ────────────────────────────────────────────────────────

  void _drawWinnerOverlay(Canvas canvas) {
    if (_winner == null) return;

    final isLiberal = _winner == 'LIBERAL';
    final color = isLiberal ? _kLiberalBlue : _kFascistRed;
    final teamLabel = isLiberal ? '자유주의 승리!' : '파시스트 승리!';

    // Dim overlay
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.x, size.y),
        const Radius.circular(20),
      ),
      Paint()..color = const Color(0xCC000000),
    );

    // Winner text
    final winPainter = TextPainter(
      text: TextSpan(
        text: teamLabel,
        style: TextStyle(
          color: color,
          fontSize: 36,
          fontWeight: FontWeight.w900,
          letterSpacing: 4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    winPainter.paint(
      canvas,
      Offset(
          (size.x - winPainter.width) / 2, (size.y - winPainter.height) / 2),
    );

    // Glow effect
    final glowPainter = TextPainter(
      text: TextSpan(
        text: teamLabel,
        style: TextStyle(
          color: color.withValues(alpha: 0.3),
          fontSize: 36,
          fontWeight: FontWeight.w900,
          letterSpacing: 4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    glowPainter.paint(
      canvas,
      Offset((size.x - glowPainter.width) / 2 - 1,
          (size.y - glowPainter.height) / 2 - 1),
    );
  }
}
