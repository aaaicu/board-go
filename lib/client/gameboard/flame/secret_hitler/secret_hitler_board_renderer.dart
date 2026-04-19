import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import '../../../../shared/game_pack/game_board_renderer.dart';
import '../../../../shared/game_pack/views/board_view.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Authentic Secret Hitler color palette
// ─────────────────────────────────────────────────────────────────────────────

// Liberal (Blue) board — navy/royal blue tones from the physical board
const Color _kLibBg       = Color(0xFF1A3560);
const Color _kLibBgLight  = Color(0xFF1F3F72);
const Color _kLibBgDark   = Color(0xFF102545);
const Color _kLibAccent   = Color(0xFF4E7EC4);
const Color _kLibBorder   = Color(0xFF6B9DD4);
const Color _kLibColumn   = Color(0xFF8AB5E0);
const Color _kLibCard     = Color(0xFF2A5A9E);   // filled liberal card face

// Fascist (Red) board — dark crimson tones
const Color _kFasBg       = Color(0xFF5C1515);
const Color _kFasBgLight  = Color(0xFF6E1F1F);
const Color _kFasBgDark   = Color(0xFF3D0D0D);
const Color _kFasAccent   = Color(0xFFC04040);
const Color _kFasBorder   = Color(0xFF9A3030);
const Color _kFasChain    = Color(0xFF8B4513);
const Color _kFasCard     = Color(0xFF9B2020);   // filled fascist card face
const Color _kFasChainHi  = Color(0xFFB8651A);   // chain highlight

// Shared neutrals
const Color _kCream       = Color(0xFFF4E2B8);
const Color _kCreamDark   = Color(0xFFDCC890);
const Color _kParchment   = Color(0xFFF8F0DC);

// Wood (President / Chancellor placards)
const Color _kWoodLight   = Color(0xFFD9AC50);
const Color _kWoodMid     = Color(0xFFC49535);
const Color _kWoodDark    = Color(0xFFAA8025);
const Color _kWoodGrain   = Color(0xFF9A7020);

const Color _kGold        = Color(0xFFFFD54F);
const Color _kDead        = Color(0xFF616161);
const Color _kTextDark    = Color(0xFF1A1A1A);
const Color _kTextLight   = Color(0xFFF0F0F0);

// ─────────────────────────────────────────────────────────────────────────────
// Layout constants
// ─────────────────────────────────────────────────────────────────────────────

const double _kBoardW = 960.0;
const double _kBoardH = 760.0;

const double _kTrackX  = 24.0;
const double _kTrackW  = 912.0;

// Liberal track — taller to fit election tracker strip inside
const double _kLibTrackY = 12.0;
const double _kLibTrackH = 285.0;

// Fascist track
const double _kFasTrackY = 308.0;
const double _kFasTrackH = 255.0;

// Policy slot dimensions — slightly wider cards
const double _kSlotW = 94.0;
const double _kSlotH = 130.0;
const double _kSlotGap = 10.0;

// Y position of the policy card row inside a track
// (offset from track top, leaving room for header banner + side labels)
const double _kLibSlotsOffY = 50.0;
const double _kFasSlotsOffY = 46.0;

// Player seats
const double _kSeatsY = 578.0;
const double _kSeatsH = 168.0;

// ─────────────────────────────────────────────────────────────────────────────
// Phase labels
// ─────────────────────────────────────────────────────────────────────────────

const Map<String, String> _kPhaseLabels = {
  'ROLE_REVEAL':             '역할 확인',
  'CHANCELLOR_NOMINATION':   '수상 지명',
  'VOTING':                  '투표 진행',
  'LEGISLATIVE_PRESIDENT':   '대통령 입법',
  'LEGISLATIVE_CHANCELLOR':  '수상 입법',
  'VETO_RESPONSE':           '거부권 응답',
  'EXECUTIVE_ACTION':        '대통령 행정 권한',
};

// ─────────────────────────────────────────────────────────────────────────────
// Executive actions per player count
// ─────────────────────────────────────────────────────────────────────────────

// Action codes rendered as icons + caption
// '' = no action, 'peek' = peek deck, 'investigate' = investigate player,
// 'special_election' = special election, 'kill' = execution, 'veto_kill' = kill+veto
const List<String> _kExec56  = ['', '', 'peek', 'kill', 'veto_kill', 'hitler_win'];
const List<String> _kExec78  = ['', 'investigate', 'special_election', 'kill', 'veto_kill', 'hitler_win'];
const List<String> _kExec910 = ['investigate', 'investigate', 'special_election', 'kill', 'veto_kill', 'hitler_win'];

// ─────────────────────────────────────────────────────────────────────────────
// SecretHitlerBoardRenderer — public interface (unchanged)
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
// _SHBoardComponent — all canvas rendering lives here
// ─────────────────────────────────────────────────────────────────────────────

class _SHBoardComponent extends PositionComponent {
  final Map<String, String> playerNames;

  // Game state (set via updateData)
  int _liberalPolicies  = 0;
  int _fascistPolicies  = 0;
  int _electionTracker  = 0;
  String  _phase              = 'ROLE_REVEAL';
  String? _presidentId;
  String? _chancellorId;
  String? _chancellorCandidateId;
  String? _winner;
  String? _winReason;
  int  _deckCount    = 0;
  int  _discardCount = 0;
  List<String>            _playerOrder    = [];
  Map<String, dynamic>    _playerInfo     = {};
  Map<String, String>     _completedVotes = {};
  String? _voteResult;

  // ── Image assets ──────────────────────────────────────────────────────────
  ui.Image? _imgTableBg;
  ui.Image? _imgLiberalBg;
  ui.Image? _imgFascistBg;
  ui.Image? _imgCardLiberalBg;
  ui.Image? _imgCardFascistBg;
  ui.Image? _imgEmblemDove;
  ui.Image? _imgEmblemSkull;

  _SHBoardComponent({required this.playerNames}) {
    anchor   = Anchor.center;
    position = Vector2.zero();
    size     = Vector2(_kBoardW, _kBoardH);
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    const base = 'assets/gamepacks/secret_hitler/images/';
    try {
      final results = await Future.wait([
        _loadUiImage('${base}board_table_bg.jpg'),
        _loadUiImage('${base}board_liberal_bg.jpg'),
        _loadUiImage('${base}board_fascist_bg.jpg'),
        _loadUiImage('${base}card_liberal_bg.jpg'),
        _loadUiImage('${base}card_fascist_bg.jpg'),
        _loadUiImage('${base}emblem_dove.jpg'),
        _loadUiImage('${base}emblem_skull.jpg'),
      ]);
      _imgTableBg       = results[0];
      _imgLiberalBg     = results[1];
      _imgFascistBg     = results[2];
      _imgCardLiberalBg = results[3];
      _imgCardFascistBg = results[4];
      _imgEmblemDove    = results[5];
      _imgEmblemSkull   = results[6];
    } catch (e) {
      // Images failed to load — canvas fallback stays active.
      // ignore: avoid_print
      print('[SH Board] Image load failed: $e');
    }
  }

  // updateData is kept unchanged — callers depend on this exact signature
  void updateData(Map<String, dynamic> data) {
    _liberalPolicies  = data['liberalPolicies']  as int? ?? 0;
    _fascistPolicies  = data['fascistPolicies']  as int? ?? 0;
    _electionTracker  = data['electionTracker']  as int? ?? 0;
    _phase            = data['phase']            as String? ?? 'ROLE_REVEAL';
    _presidentId      = data['presidentId']      as String?;
    _chancellorId     = data['chancellorId']     as String?;
    _chancellorCandidateId = data['chancellorCandidateId'] as String?;
    _winner           = data['winner']           as String?;
    _winReason        = data['winReason']        as String?;
    _deckCount        = data['deckCount']        as int? ?? 0;
    _discardCount     = data['discardCount']     as int? ?? 0;
    _playerOrder      = List<String>.from(data['playerOrder'] as List? ?? []);
    _playerInfo       = Map<String, dynamic>.from(data['playerInfo'] as Map? ?? {});
    _voteResult       = data['voteResult'] as String?;
    if (data['completedVotes'] != null) {
      _completedVotes = Map<String, String>.from(data['completedVotes'] as Map);
    } else {
      _completedVotes = {};
    }
  }

  // ── helpers ──────────────────────────────────────────────────────────────

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
    if (n >= 9) return _kExec910;
    if (n >= 7) return _kExec78;
    return _kExec56;
  }

  // ── render entry point ────────────────────────────────────────────────────

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    _drawBoardBackground(canvas);
    _drawLiberalTrack(canvas);
    _drawFascistTrack(canvas);
    _drawPlayerSeats(canvas);
    _drawPhaseIndicator(canvas);
    _drawVoteResults(canvas);
    _drawWinnerOverlay(canvas);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BOARD BACKGROUND
  // ═══════════════════════════════════════════════════════════════════════════

  void _drawBoardBackground(Canvas canvas) {
    final boardRect = Rect.fromLTWH(0, 0, size.x, size.y);
    final rrect = RRect.fromRectAndRadius(boardRect, const Radius.circular(16));
    if (_imgTableBg != null) {
      canvas.save();
      canvas.clipRRect(rrect);
      _drawScaledImage(canvas, _imgTableBg!, boardRect);
      canvas.restore();
    } else {
      canvas.drawRRect(rrect, Paint()..color = const Color(0xFF0A0C14));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LIBERAL TRACK
  // ═══════════════════════════════════════════════════════════════════════════

  void _drawLiberalTrack(Canvas canvas) {
    final tx = _kTrackX;
    final ty = _kLibTrackY;
    final tw = _kTrackW;
    final th = _kLibTrackH;
    final trackRect = Rect.fromLTWH(tx, ty, tw, th);

    // — Background
    if (_imgLiberalBg != null) {
      canvas.save();
      canvas.clipRRect(
          RRect.fromRectAndRadius(trackRect, const Radius.circular(10)));
      _drawScaledImage(canvas, _imgLiberalBg!, trackRect);
      // Light overlay — let the texture breathe
      canvas.drawRRect(
        RRect.fromRectAndRadius(trackRect, const Radius.circular(10)),
        Paint()..color = const Color(0x401A3560),
      );
      canvas.restore();
    } else {
      _paintRect(canvas, trackRect, radius: 10,
          shader: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_kLibBgLight, _kLibBg, _kLibBgDark],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(trackRect));
    }

    // — Single outer border (subtle glow over texture)
    _strokeRRect(canvas, trackRect, 10, _kLibBorder.withValues(alpha: 0.5), 1.8);

    // — Header banner (LIBERAL) — carved parchment ribbon
    _drawLiberalHeaderBanner(canvas, tx, ty, tw);

    // — DRAW PILE label (left side)
    final drawX = tx + 28.0;
    final drawY = ty + _kLibSlotsOffY + 6;
    _drawPileLabel(canvas, 'DRAW\nPILE', drawX, drawY, _kLibAccent,
        count: _deckCount, arrowRight: true);

    // — DISCARD PILE label (right side)
    final discardX = tx + tw - 70.0;
    final discardY = ty + _kLibSlotsOffY + 6;
    _drawPileLabel(canvas, 'DISCARD\nPILE', discardX, discardY, _kLibAccent,
        count: _discardCount, arrowLeft: true);

    // — 5 liberal policy slots
    final slotsStartX = _calcSlotsStartX(tx, tw, 5);
    final slotsY = ty + _kLibSlotsOffY;
    for (int i = 0; i < 5; i++) {
      final x = slotsStartX + i * (_kSlotW + _kSlotGap);
      _drawPolicySlot(canvas, x, slotsY, _kSlotW, _kSlotH,
          isLiberal: true, isFilled: i < _liberalPolicies);
    }

    // — Dove + laurel wreath emblem (lower-right area of track)
    _drawDoveLaurelEmblem(canvas,
        tx + tw - 58, ty + th - 72, 52);

    // — Election tracker strip (bottom band of liberal track)
    _drawElectionTracker(canvas, tx, ty, tw, th);
  }

  // ── Liberal header banner ─────────────────────────────────────────────────

  void _drawLiberalHeaderBanner(
      Canvas canvas, double tx, double ty, double tw) {
    const bannerH = 30.0;
    final bannerRect = Rect.fromLTWH(tx + 80, ty + 4, tw - 160, bannerH);

    // Semi-transparent dark banner over texture
    canvas.drawRRect(
      RRect.fromRectAndRadius(bannerRect, const Radius.circular(4)),
      Paint()..color = _kLibBgDark.withValues(alpha: 0.65),
    );
    _strokeRRect(canvas, bannerRect, 4,
        _kLibBorder.withValues(alpha: 0.4), 1.0);

    // "LIBERAL" title
    _drawText(canvas, 'LIBERAL', tx + tw / 2, ty + 9, 16,
        color: _kCream.withValues(alpha: 0.9),
        center: true, bold: true, letterSpacing: 10);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FASCIST TRACK
  // ═══════════════════════════════════════════════════════════════════════════

  void _drawFascistTrack(Canvas canvas) {
    final tx = _kTrackX;
    final ty = _kFasTrackY;
    final tw = _kTrackW;
    final th = _kFasTrackH;
    final trackRect = Rect.fromLTWH(tx, ty, tw, th);

    // — Background
    if (_imgFascistBg != null) {
      canvas.save();
      canvas.clipRRect(
          RRect.fromRectAndRadius(trackRect, const Radius.circular(10)));
      _drawScaledImage(canvas, _imgFascistBg!, trackRect);
      // Light overlay — let the texture breathe
      canvas.drawRRect(
        RRect.fromRectAndRadius(trackRect, const Radius.circular(10)),
        Paint()..color = const Color(0x405C1515),
      );
      canvas.restore();
    } else {
      _paintRect(canvas, trackRect, radius: 10,
          shader: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_kFasBgLight, _kFasBg, _kFasBgDark],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(trackRect));
    }

    // — Single outer border (subtle glow over texture)
    _strokeRRect(canvas, trackRect, 10, _kFasBorder.withValues(alpha: 0.5), 1.8);

    // — Header banner (FASC1ST)
    _drawFascistHeaderBanner(canvas, tx, ty, tw);

    // — 6 fascist policy slots + exec action icons
    final slotsStartX = _calcSlotsStartX(tx, tw, 6);
    final slotsY = ty + _kFasSlotsOffY;
    final actions = _execActions;
    for (int i = 0; i < 6; i++) {
      final x = slotsStartX + i * (_kSlotW + _kSlotGap);
      _drawPolicySlot(canvas, x, slotsY, _kSlotW, _kSlotH,
          isLiberal: false, isFilled: i < _fascistPolicies);

      // Executive action icon + caption below the slot
      final action = i < actions.length ? actions[i] : '';
      if (action.isNotEmpty) {
        _drawExecAction(canvas, action, x, slotsY + _kSlotH + 6, _kSlotW);
      }
    }

    // — "IF HITLER IS ELECTED CHANCELLOR" warning banner near slot 6
    final lastSlotX = slotsStartX + 5 * (_kSlotW + _kSlotGap);
    _drawHitlerWarning(canvas, lastSlotX - 4, slotsY - 18, _kSlotW + 8);

    // — Skull emblem (far right)
    _drawLargeSkull(canvas, tx + tw - 52, ty + th / 2 + 4, 38);

    // — Player count note at very bottom
    final noteText = _playerOrder.length <= 6
        ? '5 OR 6 플레이어: 파시스트 1명 그리고 히틀러를 사용합니다.  |  히틀러는 파시스트가 누군지 알고 시작합니다.'
        : _playerOrder.length <= 8
            ? '7 OR 8 플레이어: 파시스트 2명 그리고 히틀러를 사용합니다.  |  히틀러는 파시스트를 모릅니다.'
            : '9 OR 10 플레이어: 파시스트 3명 그리고 히틀러를 사용합니다.  |  히틀러는 파시스트를 모릅니다.';
    _drawText(canvas, noteText,
        tx + tw / 2, ty + th - 14, 8.5,
        color: _kCream.withValues(alpha: 0.45), center: true);
  }

  // ── Fascist header banner ─────────────────────────────────────────────────

  void _drawFascistHeaderBanner(
      Canvas canvas, double tx, double ty, double tw) {
    const bannerH = 30.0;
    final bannerRect = Rect.fromLTWH(tx + 80, ty + 4, tw - 160, bannerH);

    // Semi-transparent dark banner over texture
    canvas.drawRRect(
      RRect.fromRectAndRadius(bannerRect, const Radius.circular(4)),
      Paint()..color = _kFasBgDark.withValues(alpha: 0.65),
    );
    _strokeRRect(canvas, bannerRect, 4,
        _kFasBorder.withValues(alpha: 0.4), 1.0);

    // "FASC1ST" title
    _drawText(canvas, 'FASC1ST', tx + tw / 2, ty + 9, 16,
        color: _kCream.withValues(alpha: 0.9),
        center: true, bold: true, letterSpacing: 10);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ELECTION TRACKER (rendered as a strip inside the liberal track)
  // ═══════════════════════════════════════════════════════════════════════════

  void _drawElectionTracker(
      Canvas canvas, double tx, double ty, double tw, double th) {
    // The tracker strip occupies the bottom section of the liberal track
    const stripH = 44.0;
    const stripYOffset = 8.0;   // distance from bottom of track
    final stripY  = ty + th - stripH - stripYOffset;
    final stripX  = tx + 8;
    final stripW  = tw - 16;

    // Strip background — semi-transparent dark band over texture
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(stripX, stripY, stripW, stripH),
        const Radius.circular(6),
      ),
      Paint()..color = const Color(0xFF0A0A0A).withValues(alpha: 0.4),
    );
    _strokeRRect(canvas, Rect.fromLTWH(stripX, stripY, stripW, stripH), 6,
        _kLibBorder.withValues(alpha: 0.2), 0.8);

    // "선거 트래커" label on the left
    _drawText(canvas, '선거 트래커',
        stripX + 12, stripY + 8, 9,
        color: _kCream.withValues(alpha: 0.65));

    // 3 election tracker circles with "실패 →" separators
    // Centre the tracker group in the strip
    const circleR     = 12.0;
    const sepW        = 52.0;  // width occupied by "실패 →" text
    const groupW      = 3 * (circleR * 2) + 2 * sepW + 20;
    final groupStartX = stripX + (stripW - groupW) / 2;
    final circleCY    = stripY + stripH / 2;

    for (int i = 0; i < 3; i++) {
      final cx = groupStartX + i * (circleR * 2 + sepW + 10) + circleR;
      final isFilled = i < _electionTracker;

      // Filled: gold disc; empty: stroked circle
      canvas.drawCircle(
        Offset(cx, circleCY),
        circleR,
        Paint()
          ..color = isFilled
              ? _kGold
              : _kLibAccent.withValues(alpha: 0.25)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        Offset(cx, circleCY),
        circleR,
        Paint()
          ..color = isFilled
              ? _kWoodMid
              : _kLibBorder.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );

      // "실패" above each circle
      _drawText(canvas, '실패',
          cx, circleCY - circleR - 12, 7.5,
          color: _kCream.withValues(alpha: 0.5), center: true);

      // "→" separator between circles (not after the last one)
      if (i < 2) {
        _drawText(canvas, '→',
            cx + circleR + 4, circleCY - 7, 11,
            color: _kCream.withValues(alpha: 0.45));
        // "실패" label for separator arrow
        _drawText(canvas, '실패',
            cx + circleR + 18, circleCY - circleR - 12, 7.5,
            color: _kCream.withValues(alpha: 0.35), center: true);
      }
    }

    // Terminal action text after the 3rd circle
    final lastCX = groupStartX + 2 * (circleR * 2 + sepW + 10) + circleR;
    final termX  = lastCX + circleR + 8;
    _drawText(canvas, '→  정치팩 행위의 정책을',
        termX, circleCY - 10, 8,
        color: _kCream.withValues(alpha: 0.55));
    _drawText(canvas, '      법으로 제정합니다',
        termX, circleCY + 2, 8,
        color: _kCream.withValues(alpha: 0.55));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // POLICY SLOTS
  // ═══════════════════════════════════════════════════════════════════════════

  double _calcSlotsStartX(double tx, double tw, int count) {
    final totalW = count * _kSlotW + (count - 1) * _kSlotGap;
    return tx + (tw - totalW) / 2;
  }

  void _drawPolicySlot(
      Canvas canvas, double x, double y, double w, double h,
      {required bool isLiberal, required bool isFilled}) {
    if (isFilled) {
      _drawFilledPolicyCard(canvas, x, y, w, h, isLiberal: isLiberal);
    } else {
      _drawEmptyPolicySlot(canvas, x, y, w, h, isLiberal: isLiberal);
    }
  }

  // ── Empty slot — stippled dotted fill + dashed border ────────────────────

  void _drawEmptyPolicySlot(
      Canvas canvas, double x, double y, double w, double h,
      {required bool isLiberal}) {
    final accentColor = isLiberal ? _kLibAccent : _kFasAccent;
    final slotRect    = Rect.fromLTWH(x, y, w, h);

    // Dark inset — looks like a recessed slot in the board
    canvas.drawRRect(
      RRect.fromRectAndRadius(slotRect, const Radius.circular(7)),
      Paint()..color = const Color(0xFF0A0A0A).withValues(alpha: 0.45),
    );

    // Subtle solid border
    _strokeRRect(canvas, slotRect, 7,
        accentColor.withValues(alpha: 0.3), 1.2);
  }

  // ── Filled policy card — authentic LIBERAL/FASCIST ARTICLE card ──────────

  void _drawFilledPolicyCard(
      Canvas canvas, double x, double y, double w, double h,
      {required bool isLiberal}) {
    final cardRect  = Rect.fromLTWH(x, y, w, h);
    final borderHi  = isLiberal ? _kLibBorder : _kFasBorder;
    final cardImg   = isLiberal ? _imgCardLiberalBg : _imgCardFascistBg;
    final emblemImg = isLiberal ? _imgEmblemDove : _imgEmblemSkull;

    // — Card background
    if (cardImg != null) {
      canvas.save();
      canvas.clipRRect(
          RRect.fromRectAndRadius(cardRect, const Radius.circular(7)));
      _drawScaledImage(canvas, cardImg, cardRect);
      canvas.restore();
    } else {
      final cardColor = isLiberal ? _kLibCard : _kFasCard;
      _paintRect(canvas, cardRect, radius: 7,
          shader: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cardColor.withValues(alpha: 0.9),
              cardColor,
              (isLiberal ? _kLibBgDark : _kFasBgDark),
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(cardRect));
    }

    // — Outer glowing border (always drawn on top)
    _strokeRRect(canvas, cardRect, 7, borderHi, 2.2);

    // — Emblem in upper half
    final iconCX = x + w / 2;
    final iconCY = y + 42;
    if (emblemImg != null) {
      final emblemSize = w * 0.58;
      _drawScaledImage(
        canvas,
        emblemImg,
        Rect.fromCenter(
          center: Offset(iconCX, iconCY),
          width: emblemSize,
          height: emblemSize,
        ),
      );
    } else {
      if (isLiberal) {
        _drawDoveFull(canvas, iconCX, iconCY, 26, _kCream);
      } else {
        _drawSkullFull(canvas, iconCX, iconCY, 22, _kCream);
      }
    }

    // — Title text
    final titleLabel = isLiberal ? 'LIBERAL' : 'FASC1ST';
    _drawText(canvas, titleLabel, iconCX, y + 76, 10.5,
        color: _kCream, center: true, bold: true, letterSpacing: 2);

    // — "ARTICLE" subtitle
    _drawText(canvas, 'ARTICLE', iconCX, y + 90, 8,
        color: _kCream.withValues(alpha: 0.65), center: true, letterSpacing: 1);

    // — Horizontal document lines
    final linePaint = Paint()
      ..color = _kCream.withValues(alpha: 0.15)
      ..strokeWidth = 0.8;
    for (int i = 0; i < 3; i++) {
      final lY = y + 104 + i * 8.0;
      if (lY + 2 < y + h - 6) {
        canvas.drawLine(Offset(x + 12, lY), Offset(x + w - 12, lY), linePaint);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXECUTIVE ACTION ICONS + CAPTIONS (below fascist slots)
  // ═══════════════════════════════════════════════════════════════════════════

  void _drawExecAction(
      Canvas canvas, String action, double x, double y, double w) {
    final cx  = x + w / 2;
    final iconY = y + 4;
    const iconSize = 13.0;
    final iconColor = _kCream.withValues(alpha: 0.65);

    String caption;
    switch (action) {
      case 'peek':
        _drawIconPeekDeck(canvas, cx, iconY + iconSize, iconSize, iconColor);
        caption = '정책 엿보기';
      case 'investigate':
        _drawIconEye(canvas, cx, iconY + iconSize, iconSize, iconColor);
        caption = '플레이어 조사';
      case 'special_election':
        _drawIconLightning(canvas, cx, iconY + iconSize, iconSize, iconColor);
        caption = '특별 선거';
      case 'kill':
        _drawIconKnife(canvas, cx, iconY + iconSize, iconSize, iconColor);
        caption = '처형';
      case 'veto_kill':
        _drawIconKnife(canvas, cx, iconY + iconSize, iconSize, iconColor);
        caption = '처형\n거부권 가능';
      case 'hitler_win':
        // The "hitler_win" slot has its own warning banner; just caption
        caption = '';
      default:
        caption = '';
    }

    if (caption.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: caption,
          style: TextStyle(
            color: _kCream.withValues(alpha: 0.6),
            fontSize: 7.5,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: w - 4);
      tp.paint(canvas, Offset(cx - tp.width / 2, y + 22));
    }
  }

  // ── "IF HITLER IS ELECTED CHANCELLOR" warning on slot 6 ──────────────────

  void _drawHitlerWarning(
      Canvas canvas, double x, double y, double w) {
    final rect = Rect.fromLTWH(x, y, w, 16);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()..color = _kFasAccent.withValues(alpha: 0.35),
    );
    _drawText(canvas, '히틀러가 수상 당선 시 파시스트 승리',
        x + w / 2, y + 2, 6.5,
        color: _kCream.withValues(alpha: 0.75), center: true, bold: true);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DRAW / DISCARD PILE LABELS
  // ═══════════════════════════════════════════════════════════════════════════

  void _drawPileLabel(
      Canvas canvas, String label, double x, double y, Color color,
      {int count = 0, bool arrowRight = false, bool arrowLeft = false}) {
    // Stack of cards icon
    final iconPaint = Paint()
      ..color = color.withValues(alpha: 0.38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (int i = 2; i >= 0; i--) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 4 - i * 1.5, y + 16 - i * 2.5, 28, 36),
          const Radius.circular(3),
        ),
        iconPaint,
      );
    }

    // Label text
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color.withValues(alpha: 0.52),
          fontSize: 7.5,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: 52);
    tp.paint(canvas, Offset(x + 18 - tp.width / 2, y + 56));

    // Count badge
    if (count > 0) {
      _drawText(canvas, '$count', x + 18, y + 72, 11,
          color: color.withValues(alpha: 0.65), center: true, bold: true);
    }

    // Directional arrow pointing toward the slot area
    final arrowPaint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 1.2;
    if (arrowRight) {
      canvas.drawLine(
          Offset(x + 36, y + 34), Offset(x + 46, y + 34), arrowPaint);
      canvas.drawLine(
          Offset(x + 42, y + 30), Offset(x + 46, y + 34), arrowPaint);
      canvas.drawLine(
          Offset(x + 42, y + 38), Offset(x + 46, y + 34), arrowPaint);
    } else if (arrowLeft) {
      canvas.drawLine(
          Offset(x - 10, y + 34), Offset(x, y + 34), arrowPaint);
      canvas.drawLine(
          Offset(x - 6, y + 30), Offset(x - 10, y + 34), arrowPaint);
      canvas.drawLine(
          Offset(x - 6, y + 38), Offset(x - 10, y + 34), arrowPaint);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PLAYER SEATS — wooden President/Chancellor placards (unchanged)
  // ═══════════════════════════════════════════════════════════════════════════

  void _drawPlayerSeats(Canvas canvas) {
    if (_playerOrder.isEmpty) return;

    final n       = _playerOrder.length;
    final seatW   = math.min(110.0, (_kTrackW - 20) / n - 6);
    final totalW  = n * seatW + (n - 1) * 6;
    final startX  = _kTrackX + (_kTrackW - totalW) / 2;

    for (int i = 0; i < n; i++) {
      final pid         = _playerOrder[i];
      final x           = startX + i * (seatW + 6);
      final isDead      = _isDead(pid);
      final isPresident = pid == _presidentId;
      final isChancellor    = pid == _chancellorId;
      final isCandidate     = pid == _chancellorCandidateId;

      // — Seat card background (semi-transparent glass over table texture)
      final seatRect = Rect.fromLTWH(x, _kSeatsY, seatW, _kSeatsH);
      final cardColor = isDead
          ? _kDead.withValues(alpha: 0.25)
          : isPresident
              ? _kWoodLight.withValues(alpha: 0.12)
              : isChancellor
                  ? _kLibAccent.withValues(alpha: 0.10)
                  : const Color(0xFF0A0A0A).withValues(alpha: 0.45);

      canvas.drawRRect(
        RRect.fromRectAndRadius(seatRect, const Radius.circular(8)),
        Paint()..color = cardColor,
      );
      // Subtle border
      _strokeRRect(canvas, seatRect, 8,
          (isPresident ? _kWoodLight : isChancellor ? _kLibAccent : _kTextLight)
              .withValues(alpha: 0.15),
          0.8);

      // — Wooden placard for President / Chancellor
      if (isPresident && !isDead) {
        _drawWoodenPlacard(canvas, 'PRESIDENT',
            x + 4, _kSeatsY + 4, seatW - 8, 28);
      } else if ((isChancellor || isCandidate) && !isDead) {
        _drawWoodenPlacard(canvas, 'CHANCELLOR',
            x + 4, _kSeatsY + 4, seatW - 8, 28);
      }

      // — Avatar circle
      final avatarY = _kSeatsY +
          (isPresident || isChancellor || isCandidate ? 52 : 30);
      const avatarR = 22.0;
      final avatarColor = isDead
          ? _kDead
          : isPresident
              ? _kWoodLight
              : isChancellor || isCandidate
                  ? _kLibAccent
                  : const Color(0xFF5C6B8A);

      canvas.drawCircle(
        Offset(x + seatW / 2, avatarY), avatarR,
        Paint()..color = avatarColor.withValues(alpha: 0.2),
      );
      canvas.drawCircle(
        Offset(x + seatW / 2, avatarY), avatarR,
        Paint()
          ..color = avatarColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );

      // Initial letter
      final name = _nick(pid);
      _drawText(canvas,
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          x + seatW / 2, avatarY - 7, 16,
          color: avatarColor, center: true, bold: true);

      // Player name
      _drawText(canvas, name,
          x + seatW / 2, avatarY + avatarR + 6, 11,
          color: isDead ? _kDead : _kTextLight,
          center: true, maxWidth: seatW - 8);

      // Vote badge
      if (_completedVotes.containsKey(pid)) {
        final vote      = _completedVotes[pid]!;
        final voteColor = vote == 'JA' ? const Color(0xFF4CAF50) : _kFasAccent;
        final voteText  = vote == 'JA' ? 'Ja!' : 'Nein!';
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
                x + seatW - 34, _kSeatsY + _kSeatsH - 24, 30, 18),
            const Radius.circular(4),
          ),
          Paint()..color = voteColor.withValues(alpha: 0.8),
        );
        _drawText(canvas, voteText,
            x + seatW - 19, _kSeatsY + _kSeatsH - 22, 9,
            color: _kCream, center: true, bold: true);
      }

      // Dead X overlay
      if (isDead) {
        final dp = Paint()
          ..color = _kFasAccent.withValues(alpha: 0.6)
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke;
        canvas.drawLine(Offset(x + 10, _kSeatsY + 10),
            Offset(x + seatW - 10, _kSeatsY + _kSeatsH - 10), dp);
        canvas.drawLine(Offset(x + seatW - 10, _kSeatsY + 10),
            Offset(x + 10, _kSeatsY + _kSeatsH - 10), dp);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE INDICATOR
  // ═══════════════════════════════════════════════════════════════════════════

  void _drawPhaseIndicator(Canvas canvas) {
    if (_playerOrder.isNotEmpty) return; // seats section occupies this area
    final label = _kPhaseLabels[_phase] ?? _phase;
    final y     = _kFasTrackY + _kFasTrackH + 10;

    final tp = TextPainter(
      text: TextSpan(
        text: '  $label  ',
        style: const TextStyle(
          color: _kGold, fontSize: 12, fontWeight: FontWeight.w700),
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
        _phase != 'LEGISLATIVE_CHANCELLOR' &&
        _phase != 'CHANCELLOR_NOMINATION') {
      return;
    }

    final isPass = _voteResult == 'PASSED';
    final color  = isPass ? const Color(0xFF4CAF50) : _kFasAccent;
    final text   = isPass ? '가결' : '부결';

    final bx = _kTrackX + _kTrackW / 2;
    final by = _kFasTrackY + _kFasTrackH + 36;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(bx - 40, by, 80, 24), const Radius.circular(12)),
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

    final isLiberal  = _winner == 'LIBERAL';
    final color      = isLiberal ? _kLibAccent : _kFasAccent;
    final teamLabel  = isLiberal ? '자유주의 승리!' : '파시스트 승리!';
    final reasonText = _winReasonText(_winReason);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.x, size.y), const Radius.circular(16)),
      Paint()..color = const Color(0xCC000000),
    );

    final tp = TextPainter(
      text: TextSpan(
        text: teamLabel,
        style: TextStyle(
          color: color, fontSize: 38,
          fontWeight: FontWeight.w900, letterSpacing: 4),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final teamY = (size.y - tp.height) / 2 - (reasonText == null ? 0 : 24);
    tp.paint(canvas, Offset((size.x - tp.width) / 2, teamY));

    if (reasonText != null) {
      final rp = TextPainter(
        text: TextSpan(
          text: reasonText,
          style: const TextStyle(
            color: _kCream, fontSize: 18,
            fontWeight: FontWeight.w600, letterSpacing: 1),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.x - 40);
      rp.paint(canvas,
          Offset((size.x - rp.width) / 2, teamY + tp.height + 16));
    }
  }

  String? _winReasonText(String? reason) {
    switch (reason) {
      case 'LIBERAL_POLICIES':
        return '자유주의 정책 5장 제정';
      case 'FASCIST_POLICIES':
        return '파시스트 정책 6장 제정';
      case 'HITLER_CHANCELLOR':
        return '히틀러가 총리로 선출됨';
      case 'HITLER_EXECUTED':
        return '히틀러가 처형됨';
      default:
        return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DRAWING HELPERS — decorative elements
  // ═══════════════════════════════════════════════════════════════════════════

  // ── Roman column ─────────────────────────────────────────────────────────

  void _drawColumn(
      Canvas canvas, double x, double y, double w, double h, Color color) {
    final paint = Paint()..color = color.withValues(alpha: 0.38);

    // Capital (top)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 5, y, w + 10, 10), const Radius.circular(3)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 2, y + 8, w + 4, 5), const Radius.circular(2)),
      paint,
    );

    // Shaft
    canvas.drawRect(Rect.fromLTWH(x, y + 13, w, h - 26), paint);
    // Fluting (vertical grooves)
    final flutePaint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..strokeWidth = 0.8;
    final flutes = (w / 6).floor().clamp(2, 5);
    for (int i = 0; i < flutes; i++) {
      final fx = x + 3 + i * (w - 6) / math.max(flutes - 1, 1);
      canvas.drawLine(
          Offset(fx, y + 16), Offset(fx, y + h - 14), flutePaint);
    }

    // Base
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 2, y + h - 12, w + 4, 5), const Radius.circular(2)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 5, y + h - 8, w + 10, 8), const Radius.circular(3)),
      paint,
    );
  }

  // ── Chain border (fascist) ────────────────────────────────────────────────

  void _drawChainBorder(Canvas canvas, double x, double y, double width) {
    const linkW  = 14.0;
    const linkH  = 7.0;
    final count  = (width / linkW).floor();

    // Alternating horizontal / vertical ovals to simulate a real chain
    for (int i = 0; i < count; i++) {
      final lx      = x + i * linkW;
      final isHoriz = i.isEven;
      final p       = Paint()
        ..color = i.isEven
            ? _kFasChain.withValues(alpha: 0.5)
            : _kFasChainHi.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;
      if (isHoriz) {
        canvas.drawOval(
            Rect.fromLTWH(lx + 1, y, linkW - 2, linkH), p);
      } else {
        canvas.drawOval(
            Rect.fromLTWH(lx + 2, y - 1, linkW - 4, linkH + 2), p);
      }
    }
  }

  // ── Dashed rounded-rect border ───────────────────────────────────────────

  void _drawDashedRRect(Canvas canvas, Rect rect, double radius,
      Color color, double strokeWidth) {
    const dashLen  = 5.0;
    const gapLen   = 4.0;
    final paint    = Paint()
      ..color      = color
      ..strokeWidth = strokeWidth
      ..style      = PaintingStyle.stroke;

    // We approximate the rounded rect perimeter with its axis-aligned edges
    // (corners are left as gaps — acceptable approximation for slots)
    final r = radius;
    void drawDashedH(double x1, double x2, double lineY) {
      double cx = x1 + r;
      while (cx < x2 - r) {
        final end = math.min(cx + dashLen, x2 - r);
        canvas.drawLine(Offset(cx, lineY), Offset(end, lineY), paint);
        cx = end + gapLen;
      }
    }
    void drawDashedV(double y1, double y2, double lineX) {
      double cy = y1 + r;
      while (cy < y2 - r) {
        final end = math.min(cy + dashLen, y2 - r);
        canvas.drawLine(Offset(lineX, cy), Offset(lineX, end), paint);
        cy = end + gapLen;
      }
    }

    drawDashedH(rect.left, rect.right, rect.top);
    drawDashedH(rect.left, rect.right, rect.bottom);
    drawDashedV(rect.top, rect.bottom, rect.left);
    drawDashedV(rect.top, rect.bottom, rect.right);
  }

  // ── Small diamond ornament ────────────────────────────────────────────────

  void _drawDiamond(
      Canvas canvas, double cx, double cy, double r, Color color) {
    final path = Path()
      ..moveTo(cx, cy - r)
      ..lineTo(cx + r, cy)
      ..lineTo(cx, cy + r)
      ..lineTo(cx - r, cy)
      ..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.5));
  }

  // ── Dove + laurel wreath emblem (liberal board, right side) ───────────────

  void _drawDoveLaurelEmblem(
      Canvas canvas, double cx, double cy, double size) {
    if (_imgEmblemDove != null) {
      _drawScaledImage(
        canvas,
        _imgEmblemDove!,
        Rect.fromCenter(
          center: Offset(cx, cy),
          width: size * 1.5,
          height: size * 1.5,
        ),
        opacity: 0.35,
      );
      return;
    }
    final laurelPaint = Paint()
      ..color = _kLibAccent.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    // Outer laurel arcs (left branch)
    for (int i = 0; i < 5; i++) {
      final angle = math.pi * 0.55 + i * 0.14;
      final bx    = cx - size * 0.38 * math.cos(angle);
      final by    = cy + size * 0.38 * math.sin(angle) - size * 0.15;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(bx, by),
          width: size * 0.18, height: size * 0.10),
        laurelPaint,
      );
    }
    // Right branch (mirrored)
    for (int i = 0; i < 5; i++) {
      final angle = math.pi * 0.55 + i * 0.14;
      final bx    = cx + size * 0.38 * math.cos(angle);
      final by    = cy + size * 0.38 * math.sin(angle) - size * 0.15;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(bx, by),
          width: size * 0.18, height: size * 0.10),
        laurelPaint,
      );
    }

    // Dove body
    _drawDoveFull(canvas, cx, cy - size * 0.08, size * 0.55,
        _kLibAccent.withValues(alpha: 0.32));
  }

  // ── Full dove icon ────────────────────────────────────────────────────────

  void _drawDoveFull(
      Canvas canvas, double cx, double cy, double s, Color color) {
    final p = Paint()..color = color;

    // Body (horizontal oval)
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, cy),
          width: s * 0.68, height: s * 0.34),
      p,
    );

    // Wings (spread upward from body)
    final lWing = Path()
      ..moveTo(cx - s * 0.08, cy - s * 0.06)
      ..quadraticBezierTo(
          cx - s * 0.50, cy - s * 0.55, cx - s * 0.28, cy + s * 0.08)
      ..close();
    canvas.drawPath(lWing, p);

    final rWing = Path()
      ..moveTo(cx + s * 0.08, cy - s * 0.06)
      ..quadraticBezierTo(
          cx + s * 0.50, cy - s * 0.55, cx + s * 0.28, cy + s * 0.08)
      ..close();
    canvas.drawPath(rWing, p);

    // Head
    canvas.drawCircle(
        Offset(cx + s * 0.28, cy - s * 0.14), s * 0.12, p);

    // Beak (tiny triangle)
    final beak = Path()
      ..moveTo(cx + s * 0.38, cy - s * 0.12)
      ..lineTo(cx + s * 0.46, cy - s * 0.08)
      ..lineTo(cx + s * 0.38, cy - s * 0.06)
      ..close();
    canvas.drawPath(beak, p);

    // Tail feathers
    final tail = Path()
      ..moveTo(cx - s * 0.30, cy + s * 0.02)
      ..lineTo(cx - s * 0.50, cy - s * 0.10)
      ..lineTo(cx - s * 0.42, cy + s * 0.10)
      ..lineTo(cx - s * 0.52, cy + s * 0.05)
      ..lineTo(cx - s * 0.40, cy + s * 0.16)
      ..close();
    canvas.drawPath(tail, p);
  }

  // ── Full skull icon (fascist card / emblem) ────────────────────────────────

  void _drawSkullFull(
      Canvas canvas, double cx, double cy, double s, Color color) {
    final p = Paint()..color = color;

    // Cranium
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, cy - s * 0.08),
          width: s * 0.9, height: s * 0.82),
      p,
    );

    // Jaw / mandible
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
            cx - s * 0.32, cy + s * 0.22, s * 0.64, s * 0.28),
        const Radius.circular(4)),
      p,
    );

    // Eye sockets — dark holes
    final eyeP = Paint()..color = _kFasCard;
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx - s * 0.18, cy - s * 0.12),
          width: s * 0.26, height: s * 0.24),
      eyeP,
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx + s * 0.18, cy - s * 0.12),
          width: s * 0.26, height: s * 0.24),
      eyeP,
    );

    // Nasal cavity
    final nose = Path()
      ..moveTo(cx, cy + s * 0.02)
      ..lineTo(cx - s * 0.07, cy + s * 0.14)
      ..lineTo(cx + s * 0.07, cy + s * 0.14)
      ..close();
    canvas.drawPath(nose, eyeP);

    // Teeth (gap lines in jaw)
    final toothPaint = Paint()
      ..color = _kFasCard
      ..strokeWidth = s * 0.08;
    for (int i = 0; i < 4; i++) {
      final tx = cx - s * 0.24 + i * s * 0.16;
      canvas.drawLine(
        Offset(tx, cy + s * 0.24),
        Offset(tx, cy + s * 0.44),
        toothPaint,
      );
    }
  }

  // ── Large decorative skull (fascist track right emblem) ───────────────────

  void _drawLargeSkull(
      Canvas canvas, double cx, double cy, double size) {
    if (_imgEmblemSkull != null) {
      _drawScaledImage(
        canvas,
        _imgEmblemSkull!,
        Rect.fromCenter(
          center: Offset(cx, cy),
          width: size * 1.8,
          height: size * 1.8,
        ),
        opacity: 0.38,
      );
      return;
    }
    _drawSkullFull(canvas, cx, cy, size,
        _kFasAccent.withValues(alpha: 0.30));
  }

  // ── Small skull (inline icon) ─────────────────────────────────────────────

  void _drawSmallSkull(
      Canvas canvas, double cx, double cy, double s, Color color) {
    _drawSkullFull(canvas, cx, cy, s, color);
  }

  // ── Executive action icon: peek deck ─────────────────────────────────────

  void _drawIconPeekDeck(
      Canvas canvas, double cx, double cy, double s, Color color) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    // Three overlapping card outlines (top view)
    for (int i = 2; i >= 0; i--) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
              cx - s * 0.4 + i * s * 0.1,
              cy - s * 0.55 - i * s * 0.15,
              s * 0.7, s * 0.9),
          const Radius.circular(2)),
        p,
      );
    }
  }

  // ── Executive action icon: eye (investigate) ─────────────────────────────

  void _drawIconEye(
      Canvas canvas, double cx, double cy, double s, Color color) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    // Eye outline (two arcs)
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx, cy), width: s * 1.6, height: s),
      0.4, math.pi - 0.8, false, p);
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx, cy), width: s * 1.6, height: s),
      math.pi + 0.4, math.pi - 0.8, false, p);
    // Pupil
    canvas.drawCircle(Offset(cx, cy), s * 0.22,
        Paint()..color = color);
  }

  // ── Executive action icon: lightning bolt (special election) ──────────────

  void _drawIconLightning(
      Canvas canvas, double cx, double cy, double s, Color color) {
    final path = Path()
      ..moveTo(cx + s * 0.1,  cy - s * 0.7)
      ..lineTo(cx - s * 0.25, cy - s * 0.05)
      ..lineTo(cx + s * 0.05, cy - s * 0.05)
      ..lineTo(cx - s * 0.1,  cy + s * 0.7)
      ..lineTo(cx + s * 0.25, cy + s * 0.05)
      ..lineTo(cx - s * 0.05, cy + s * 0.05)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  // ── Executive action icon: knife (execution) ─────────────────────────────

  void _drawIconKnife(
      Canvas canvas, double cx, double cy, double s, Color color) {
    final p = Paint()..color = color;

    // Blade (long thin triangle)
    final blade = Path()
      ..moveTo(cx, cy - s * 0.7)
      ..lineTo(cx + s * 0.18, cy + s * 0.3)
      ..lineTo(cx - s * 0.05, cy + s * 0.3)
      ..close();
    canvas.drawPath(blade, p);

    // Handle
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - s * 0.22, cy + s * 0.3, s * 0.44, s * 0.4),
        const Radius.circular(3)),
      p,
    );
    // Guard line
    canvas.drawLine(
      Offset(cx - s * 0.28, cy + s * 0.3),
      Offset(cx + s * 0.28, cy + s * 0.3),
      Paint()
        ..color = color
        ..strokeWidth = s * 0.12
        ..strokeCap = StrokeCap.round,
    );
  }

  // ── Wooden placard (President / Chancellor) ───────────────────────────────

  void _drawWoodenPlacard(
      Canvas canvas, String text, double x, double y, double w, double h) {
    final placardRect = Rect.fromLTWH(x, y, w, h);

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

    final grainPaint = Paint()
      ..color = _kWoodGrain.withValues(alpha: 0.22)
      ..strokeWidth = 0.5;
    for (int i = 0; i < 5; i++) {
      final gy = y + 4 + i * (h / 5);
      canvas.drawLine(Offset(x + 3, gy), Offset(x + w - 3, gy), grainPaint);
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(placardRect, const Radius.circular(3)),
      Paint()
        ..color = const Color(0xFF4A3520)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    _drawText(canvas, text, x + w / 2, y + (h - 12) / 2, 10,
        color: _kTextDark, center: true, bold: true, letterSpacing: 3);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PAINT UTILITIES
  // ═══════════════════════════════════════════════════════════════════════════

  // ── Image helpers ─────────────────────────────────────────────────────────

  /// Draws [img] scaled to fill [dst]. Optional [opacity] (0–1).
  void _drawScaledImage(Canvas canvas, ui.Image img, Rect dst,
      {double opacity = 1.0}) {
    final src =
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final paint = Paint()..filterQuality = FilterQuality.medium;
    if (opacity < 1.0) {
      final alpha = (opacity * 255).round();
      canvas.saveLayer(
          dst, Paint()..color = Color.fromARGB(alpha, 255, 255, 255));
      canvas.drawImageRect(img, src, dst, paint);
      canvas.restore();
    } else {
      canvas.drawImageRect(img, src, dst, paint);
    }
  }

  void _paintRect(Canvas canvas, Rect rect,
      {double radius = 0, Shader? shader, Color? color}) {
    final paint = Paint();
    if (shader != null) paint.shader = shader;
    if (color != null) paint.color = color;
    if (radius > 0) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(radius)), paint);
    } else {
      canvas.drawRect(rect, paint);
    }
  }

  void _strokeRRect(Canvas canvas, Rect rect, double radius,
      Color color, double strokeWidth) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TEXT UTILITY
  // ═══════════════════════════════════════════════════════════════════════════

  void _drawText(Canvas canvas, String text, double x, double y,
      double fontSize,
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
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? 500);
    if (center) {
      tp.paint(canvas, Offset(x - tp.width / 2, y));
    } else {
      tp.paint(canvas, Offset(x, y));
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Asset loader — loads a Flutter asset as a dart:ui Image for Canvas drawing.
// ─────────────────────────────────────────────────────────────────────────────

Future<ui.Image> _loadUiImage(String assetPath) async {
  final data = await rootBundle.load(assetPath);
  final codec =
      await ui.instantiateImageCodec(data.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  return frame.image;
}
