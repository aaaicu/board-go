import 'package:flutter/material.dart';

import '../../shared/game_pack/views/player_view.dart';
import '../shared/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Color palette — consistent with board renderer
// ─────────────────────────────────────────────────────────────────────────────

const Color _kBgDark = Color(0xFF1A1A2E);
const Color _kBgMid = Color(0xFF16213E);
const Color _kCardBg = Color(0xFF1E2A45);

const Color _kLiberalBlue = Color(0xFF2196F3);
const Color _kLiberalLight = Color(0xFF64B5F6);
const Color _kLiberalDeep = Color(0xFF1B3A6B);

const Color _kFascistRed = Color(0xFFE53935);
const Color _kFascistLight = Color(0xFFEF5350);
const Color _kFascistDeep = Color(0xFF6B1F1F);

const Color _kGold = Color(0xFFFFD54F);

const Color _kTextLight = Color(0xFFF5F5F5);
const Color _kTextMuted = Color(0xFFBDBDBD);

// Phase labels
const _phaseLabels = {
  'ROLE_REVEAL': '역할 확인',
  'CHANCELLOR_NOMINATION': '수상 지명',
  'VOTING': '투표 진행 중',
  'LEGISLATIVE_PRESIDENT': '대통령 입법',
  'LEGISLATIVE_CHANCELLOR': '수상 입법',
  'VETO_RESPONSE': '거부권 응답',
  'EXECUTIVE_ACTION': '행정 권한',
};

// ─────────────────────────────────────────────────────────────────────────────
// Message model — represents an actionable game notification
// ─────────────────────────────────────────────────────────────────────────────

class _GameMessage {
  final String id;
  final String text;
  final bool isActionable;
  final String? actionPhase;

  const _GameMessage({
    required this.id,
    required this.text,
    required this.isActionable,
    this.actionPhase,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SecretHitlerNodeWidget — Player phone UI
// ─────────────────────────────────────────────────────────────────────────────

/// Full-featured player node UI for the Secret Hitler game pack.
///
/// Layout:
/// - Fixed top bar: message button, policy counters, role/party card buttons
/// - Center content area: empty by default, shows card overlays or action UIs
///
/// Action flow: Messages drive actions. Tapping a message opens the relevant
/// action UI (nomination, voting, policy selection, etc.) inline.
class SecretHitlerNodeWidget extends StatefulWidget {
  final PlayerView playerView;
  final void Function(String type, Map<String, dynamic> params) onAction;

  const SecretHitlerNodeWidget({
    super.key,
    required this.playerView,
    required this.onAction,
  });

  @override
  State<SecretHitlerNodeWidget> createState() => _SecretHitlerNodeWidgetState();
}

class _SecretHitlerNodeWidgetState extends State<SecretHitlerNodeWidget> {
  bool _showingRole = false;
  bool _showingParty = false;
  bool _showingMessages = false;
  // When a message is tapped, we store the phase it should render as the
  // active action UI. null means the default idle center is shown.
  String? _activeMessageAction;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void didUpdateWidget(SecretHitlerNodeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPhase = oldWidget.playerView.data['phase'] as String? ?? '';
    final newPhase = widget.playerView.data['phase'] as String? ?? '';
    if (oldPhase != newPhase) {
      // Phase changed — the active action panel belongs to the old phase.
      // Clear it so the UI auto-updates to the new phase's message/action.
      _activeMessageAction = null;
    }
  }

  // ── Data accessors ────────────────────────────────────────────────────────

  Map<String, dynamic> get _data => widget.playerView.data;
  String get _phase => _data['phase'] as String? ?? '';
  String get _myRole => _data['myRole'] as String? ?? '';
  String get _myParty => _data['myParty'] as String? ?? '';
  String? get _presidentId => _data['presidentId'] as String?;
  String? get _chancellorId => _data['chancellorId'] as String?;
  String? get _chancellorCandidateId =>
      _data['chancellorCandidateId'] as String?;
  int get _liberalPolicies => _data['liberalPolicies'] as int? ?? 0;
  int get _fascistPolicies => _data['fascistPolicies'] as int? ?? 0;
  bool get _vetoUnlocked => _data['vetoUnlocked'] as bool? ?? false;
  String? get _winner => _data['winner'] as String?;
  List<String> get _deadPlayers =>
      List<String>.from(_data['deadPlayers'] ?? []);
  Map<String, dynamic> get _playerInfo =>
      Map<String, dynamic>.from(_data['playerInfo'] ?? {});

  String _nick(String pid) {
    final info = _playerInfo[pid] as Map<String, dynamic>?;
    return info?['nickname'] as String? ?? pid;
  }

  // ── Message generation ────────────────────────────────────────────────────

  /// Derives the current message list from the game phase and player state.
  /// The most recent actionable message is surfaced first.
  List<_GameMessage> get _messages {
    final msgs = <_GameMessage>[];

    if (_winner != null) {
      final isLiberal = _winner == 'LIBERAL';
      msgs.add(_GameMessage(
        id: 'game_over',
        text: isLiberal ? '자유주의 팀이 승리했습니다!' : '파시스트 팀이 승리했습니다!',
        isActionable: false,
      ));
      return msgs;
    }

    if (_deadPlayers.contains(widget.playerView.playerId)) {
      msgs.add(const _GameMessage(
        id: 'dead',
        text: '처형되었습니다. 관전 모드로 게임을 지켜보세요.',
        isActionable: false,
      ));
      return msgs;
    }

    // Phase-specific actionable messages
    switch (_phase) {
      case 'ROLE_REVEAL':
        final isReady = _data['isReady'] as bool? ?? false;
        msgs.add(_GameMessage(
          id: 'role_reveal',
          text: isReady
              ? '역할 확인이 완료되었습니다. 다른 플레이어를 기다리는 중...'
              : '당신의 역할을 확인하고 "역할 확인 완료"를 눌러주세요.',
          isActionable: !isReady,
          actionPhase: 'ROLE_REVEAL',
        ));

      case 'CHANCELLOR_NOMINATION':
        if (_presidentId == widget.playerView.playerId) {
          msgs.add(const _GameMessage(
            id: 'nomination',
            text: '당신이 대통령이 되었습니다. 수상 후보를 지명해주세요.',
            isActionable: true,
            actionPhase: 'CHANCELLOR_NOMINATION',
          ));
        } else {
          final presName = _nick(_presidentId ?? '');
          msgs.add(_GameMessage(
            id: 'nomination_wait',
            text: '대통령 $presName이(가) 수상 후보를 지명하고 있습니다.',
            isActionable: false,
          ));
        }

      case 'VOTING':
        final hasVoted = _data['hasVoted'] as bool? ?? false;
        final voteResult = _data['voteResult'] as String?;
        if (voteResult != null) {
          final passed = voteResult == 'PASSED';
          final candidateName = _nick(_chancellorCandidateId ?? '');
          msgs.add(_GameMessage(
            id: 'vote_result',
            text: passed
                ? '투표 가결 — $candidateName이(가) 수상으로 선출되었습니다.'
                : '투표 부결 — 선거가 실패했습니다.',
            isActionable: true,
            actionPhase: 'VOTING',
          ));
        } else if (hasVoted) {
          msgs.add(const _GameMessage(
            id: 'vote_wait',
            text: '투표가 완료되었습니다. 다른 플레이어를 기다리는 중...',
            isActionable: false,
          ));
        } else {
          final candidateName = _nick(_chancellorCandidateId ?? '');
          final presName = _nick(_presidentId ?? '');
          msgs.add(_GameMessage(
            id: 'vote',
            text: '투표해주세요: $presName 대통령이 $candidateName을(를) 수상으로 지명했습니다.',
            isActionable: true,
            actionPhase: 'VOTING',
          ));
        }

      case 'LEGISLATIVE_PRESIDENT':
        if (_presidentId == widget.playerView.playerId) {
          msgs.add(const _GameMessage(
            id: 'leg_president',
            text: '정책 카드 3장 중 1장을 버리세요. 나머지 2장이 수상에게 전달됩니다.',
            isActionable: true,
            actionPhase: 'LEGISLATIVE_PRESIDENT',
          ));
        } else {
          msgs.add(const _GameMessage(
            id: 'leg_president_wait',
            text: '대통령이 정책 카드를 검토하고 있습니다.',
            isActionable: false,
          ));
        }

      case 'LEGISLATIVE_CHANCELLOR':
        if (_chancellorId == widget.playerView.playerId) {
          msgs.add(_GameMessage(
            id: 'leg_chancellor',
            text: _vetoUnlocked
                ? '정책 카드 2장 중 1장을 제정하거나 거부권을 요청하세요.'
                : '정책 카드 2장 중 1장을 선택하세요.',
            isActionable: true,
            actionPhase: 'LEGISLATIVE_CHANCELLOR',
          ));
        } else {
          msgs.add(const _GameMessage(
            id: 'leg_chancellor_wait',
            text: '수상이 정책을 제정하고 있습니다.',
            isActionable: false,
          ));
        }

      case 'VETO_RESPONSE':
        if (_presidentId == widget.playerView.playerId) {
          msgs.add(const _GameMessage(
            id: 'veto',
            text: '수상이 거부권을 요청했습니다. 찬성 또는 반대를 선택해주세요.',
            isActionable: true,
            actionPhase: 'VETO_RESPONSE',
          ));
        } else {
          msgs.add(const _GameMessage(
            id: 'veto_wait',
            text: '대통령이 거부권 요청을 검토하고 있습니다.',
            isActionable: false,
          ));
        }

      case 'EXECUTIVE_ACTION':
        if (_presidentId == widget.playerView.playerId) {
          final execType = _data['executiveActionType'] as String? ?? '';
          final label = _execActionLabel(execType);
          msgs.add(_GameMessage(
            id: 'exec',
            text: '행정 권한을 행사하세요: $label',
            isActionable: true,
            actionPhase: 'EXECUTIVE_ACTION',
          ));
        } else {
          msgs.add(const _GameMessage(
            id: 'exec_wait',
            text: '대통령이 행정 권한을 행사하고 있습니다.',
            isActionable: false,
          ));
        }
    }

    return msgs;
  }

  String _execActionLabel(String execType) {
    switch (execType) {
      case 'POLICY_PEEK':
        return '정책 엿보기';
      case 'INVESTIGATE':
        return '플레이어 조사';
      case 'SPECIAL_ELECTION':
        return '특별 선거';
      case 'EXECUTION':
        return '처형';
      default:
        return execType;
    }
  }

  int get _unreadCount =>
      _messages.where((m) => m.isActionable).length;

  // ── State transitions ─────────────────────────────────────────────────────

  void _onRoleButtonTap() {
    setState(() {
      _showingRole = !_showingRole;
      _showingParty = false;
      _showingMessages = false;
      _activeMessageAction = null;
    });
  }

  void _onPartyButtonTap() {
    setState(() {
      _showingParty = !_showingParty;
      _showingRole = false;
      _showingMessages = false;
      _activeMessageAction = null;
    });
  }

  void _onMessageButtonTap() {
    setState(() {
      _showingMessages = !_showingMessages;
      _showingRole = false;
      _showingParty = false;
      if (!_showingMessages) _activeMessageAction = null;
    });
  }

  void _onMessageTap(_GameMessage message) {
    if (!message.isActionable || message.actionPhase == null) return;
    setState(() {
      _activeMessageAction = message.actionPhase;
      _showingMessages = false;
    });
  }

  void _dismissActionPanel() {
    setState(() {
      _activeMessageAction = null;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // ROLE_REVEAL: auto-open the action panel so the player can confirm role.
    final effectiveAction = _activeMessageAction ??
        (_phase == 'ROLE_REVEAL' &&
                !(_data['isReady'] as bool? ?? false) &&
                !_showingRole &&
                !_showingParty
            ? 'ROLE_REVEAL'
            : null);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_kBgDark, _kBgMid],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: Stack(
                children: [
                  // Base content layer
                  _buildCenterContent(effectiveAction),
                  // Message panel overlay
                  if (_showingMessages) _buildMessagePanel(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top Bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kBgDark.withValues(alpha: 0.95),
        border: Border(
          bottom: BorderSide(color: _kGold.withValues(alpha: 0.15)),
        ),
      ),
      child: Row(
        children: [
          // Left: message button with badge
          _buildMessageButton(),
          const SizedBox(width: 12),
          // Center: policy counters
          Expanded(child: _buildPolicyCounters()),
          const SizedBox(width: 12),
          // Right: role + party card buttons
          _buildCardButtons(),
        ],
      ),
    );
  }

  Widget _buildMessageButton() {
    final count = _unreadCount;
    return GestureDetector(
      onTap: _onMessageButtonTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: _showingMessages
              ? _kGold.withValues(alpha: 0.2)
              : _kCardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _showingMessages
                ? _kGold.withValues(alpha: 0.6)
                : _kGold.withValues(alpha: 0.15),
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Center(
              child: Icon(Icons.mail_outline, color: _kGold, size: 22),
            ),
            if (count > 0)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: _kFascistRed,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        color: _kTextLight,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPolicyCounters() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildPolicyCounter(
          label: '리버럴',
          current: _liberalPolicies,
          total: 5,
          color: _kLiberalBlue,
        ),
        const SizedBox(width: 8),
        _buildPolicyCounter(
          label: '파시스트',
          current: _fascistPolicies,
          total: 6,
          color: _kFascistRed,
        ),
      ],
    );
  }

  Widget _buildPolicyCounter({
    required String label,
    required int current,
    required int total,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            '$label $current/$total',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardButtons() {
    // 버튼 색상은 당적과 무관하게 중립 색상 사용 — 타인이 화면을 봐도 소속을 알 수 없도록
    const neutralColor = _kGold;
    return Row(
      children: [
        _buildTopBarCardButton(
          label: '역할',
          isActive: _showingRole,
          color: neutralColor,
          onTap: _onRoleButtonTap,
        ),
        const SizedBox(width: 6),
        _buildTopBarCardButton(
          label: '당적',
          isActive: _showingParty,
          color: neutralColor,
          onTap: _onPartyButtonTap,
        ),
      ],
    );
  }

  Widget _buildTopBarCardButton({
    required String label,
    required bool isActive,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.2) : _kCardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive
                ? color.withValues(alpha: 0.6)
                : color.withValues(alpha: 0.2),
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? color : color.withValues(alpha: 0.7),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // ── Center Content ────────────────────────────────────────────────────────

  Widget _buildCenterContent(String? activeAction) {
    if (_showingRole) return _buildRoleCardOverlay();
    if (_showingParty) return _buildPartyCardOverlay();

    if (activeAction != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            const SizedBox(height: 16),
            _buildActionContent(activeAction),
            const SizedBox(height: 24),
          ],
        ),
      );
    }

    // Idle state
    return _buildIdleCenter();
  }

  Widget _buildIdleCenter() {
    final phaseLabel = _phaseLabels[_phase] ?? _phase;
    final myRole = _myRole;
    final isPresident = _presidentId == widget.playerView.playerId;
    final isChancellor = _chancellorId == widget.playerView.playerId;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Phase chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
              color: _kGold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kGold.withValues(alpha: 0.25)),
            ),
            child: Text(
              phaseLabel,
              style: const TextStyle(
                color: _kGold,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 20),
          // 역할/당적은 버튼을 눌러야만 확인 가능 — 메인 화면에서 노출하지 않음
          // Government position badge
          if (isPresident || isChancellor)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _kGold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kGold.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.account_balance, color: _kGold, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    isPresident ? '현재 대통령' : '현재 수상',
                    style: const TextStyle(
                      color: _kGold,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 28),
          // Hint to open messages
          if (_unreadCount > 0)
            GestureDetector(
              onTap: _onMessageButtonTap,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: _kFascistRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: _kFascistRed.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.mail, color: _kFascistRed, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      '행동이 필요합니다 ($_unreadCount)',
                      style: const TextStyle(
                        color: _kFascistRed,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            const Text(
              '다른 플레이어를 기다리는 중...',
              style: TextStyle(
                color: _kTextMuted,
                fontSize: 14,
              ),
            ),
        ],
      ),
    );
  }

  // ── Card Overlays ─────────────────────────────────────────────────────────

  Widget _buildPartyCardOverlay() {
    final isLiberal = _myParty == 'LIBERAL';
    return GestureDetector(
      onTap: _onPartyButtonTap,
      child: Container(
        color: Colors.black.withValues(alpha: 0.4),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildCanvasCard(isLiberal: isLiberal, isRole: false),
              const SizedBox(height: 16),
              Text(
                '탭하여 닫기',
                style: TextStyle(
                  color: _kTextMuted.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCardOverlay() {
    final isLiberal = _myParty == 'LIBERAL';
    return GestureDetector(
      onTap: _onRoleButtonTap,
      child: Container(
        color: Colors.black.withValues(alpha: 0.4),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildCanvasCard(isLiberal: isLiberal, isRole: true),
              const SizedBox(height: 8),
              if (_myRole == 'FASCIST' ||
                  (_myRole == 'HITLER' &&
                      (_data['totalPlayers'] as int? ?? 0) <= 6))
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: _buildAlliesInfo(),
                ),
              const SizedBox(height: 12),
              Text(
                '탭하여 닫기',
                style: TextStyle(
                  color: _kTextMuted.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Renders the physical-card-style party/role card using Canvas.
  Widget _buildCanvasCard({required bool isLiberal, required bool isRole}) {
    String title;
    String subtitle;
    Color bgColor;
    Color accentColor;

    if (isRole) {
      switch (_myRole) {
        case 'LIBERAL':
          title = '리버럴';
          subtitle = '역할 카드';
          bgColor = _kLiberalDeep;
          accentColor = _kLiberalLight;
        case 'FASCIST':
          title = '파시스트';
          subtitle = '역할 카드';
          bgColor = _kFascistDeep;
          accentColor = _kFascistLight;
        case 'HITLER':
          title = '히틀러';
          subtitle = '역할 카드';
          bgColor = const Color(0xFF1A0000);
          accentColor = _kFascistLight;
        default:
          title = '???';
          subtitle = '역할 카드';
          bgColor = _kCardBg;
          accentColor = _kTextMuted;
      }
    } else {
      // Party card
      title = isLiberal ? '리버럴' : '파시스트';
      subtitle = '정당 카드';
      bgColor = isLiberal ? _kLiberalDeep : _kFascistDeep;
      accentColor = isLiberal ? _kLiberalLight : _kFascistLight;
    }

    // Card proportions: 2:3 ratio
    const double cardWidth = 200;
    const double cardHeight = 300;

    return SizedBox(
      width: cardWidth,
      height: cardHeight,
      child: CustomPaint(
        painter: _CardPainter(
          bgColor: bgColor,
          accentColor: accentColor,
          title: title,
          subtitle: subtitle,
          isLiberal: isRole ? _myRole == 'LIBERAL' : isLiberal,
        ),
      ),
    );
  }

  // ── Message Panel ─────────────────────────────────────────────────────────

  Widget _buildMessagePanel() {
    final msgs = _messages;
    return Positioned.fill(
      child: GestureDetector(
        onTap: () {
          // Tapping the backdrop (not the panel) closes it
        },
        child: Stack(
          children: [
            // Semi-transparent backdrop
            Container(color: Colors.black.withValues(alpha: 0.5)),
            // Slide-up panel from bottom
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                constraints: const BoxConstraints(maxHeight: 480),
                decoration: BoxDecoration(
                  color: _kBgDark,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border.all(
                    color: _kGold.withValues(alpha: 0.15),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle + header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                      child: Column(
                        children: [
                          Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: _kTextMuted.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.mail_outline,
                                  color: _kGold, size: 18),
                              const SizedBox(width: 8),
                              const Text(
                                '메시지',
                                style: TextStyle(
                                  color: _kGold,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: _onMessageButtonTap,
                                child: const Icon(Icons.close,
                                    color: _kTextMuted, size: 20),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Divider(
                              color: _kGold.withValues(alpha: 0.1), height: 1),
                        ],
                      ),
                    ),
                    // Message list
                    Flexible(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        shrinkWrap: true,
                        itemCount: msgs.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (_, i) =>
                            _buildMessageTile(msgs[i]),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageTile(_GameMessage msg) {
    final color = msg.isActionable ? _kGold : _kTextMuted;
    return GestureDetector(
      onTap: () => _onMessageTap(msg),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: msg.isActionable
              ? _kGold.withValues(alpha: 0.07)
              : _kCardBg.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: msg.isActionable
                ? _kGold.withValues(alpha: 0.3)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              msg.isActionable ? Icons.touch_app : Icons.info_outline,
              color: color,
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                msg.text,
                style: TextStyle(
                  color: msg.isActionable ? _kTextLight : _kTextMuted,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ),
            if (msg.isActionable)
              const Icon(Icons.arrow_forward_ios,
                  color: _kGold, size: 13),
          ],
        ),
      ),
    );
  }

  // ── Action Content Router ─────────────────────────────────────────────────

  Widget _buildActionContent(String phase) {
    // Dismiss button strip at top
    return Column(
      children: [
        // "Back" strip
        GestureDetector(
          onTap: _dismissActionPanel,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _kCardBg.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.arrow_back_ios,
                    color: _kTextMuted, size: 13),
                const SizedBox(width: 4),
                Text(
                  '메시지로 돌아가기',
                  style: TextStyle(
                    color: _kTextMuted.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _buildPhaseActionWidget(phase),
      ],
    );
  }

  Widget _buildPhaseActionWidget(String phase) {
    if (_winner != null) return _buildGameOver();
    if (_deadPlayers.contains(widget.playerView.playerId)) {
      return _buildDead();
    }

    switch (phase) {
      case 'ROLE_REVEAL':
        return _buildRoleReveal();
      case 'CHANCELLOR_NOMINATION':
        return _buildNomination();
      case 'VOTING':
        return _buildVoting();
      case 'LEGISLATIVE_PRESIDENT':
        return _buildLegislativePresident();
      case 'LEGISLATIVE_CHANCELLOR':
        return _buildLegislativeChancellor();
      case 'VETO_RESPONSE':
        return _buildVetoResponse();
      case 'EXECUTIVE_ACTION':
        return _buildExecutiveAction();
      default:
        return _buildWaiting('게임 진행 중...');
    }
  }

  // ── ROLE_REVEAL ───────────────────────────────────────────────────────────

  Widget _buildRoleReveal() {
    final isReady = _data['isReady'] as bool? ?? false;
    final readyCount = _data['readyCount'] as int? ?? 0;
    final totalPlayers = _data['totalPlayers'] as int? ?? 0;

    return Column(
      children: [
        _buildSectionTitle('당신의 역할'),
        const SizedBox(height: 12),
        _buildRoleCard(expanded: true),
        const SizedBox(height: 12),
        if (_myRole == 'FASCIST' ||
            (_myRole == 'HITLER' && totalPlayers <= 6))
          _buildAlliesInfo(),
        const SizedBox(height: 16),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _kCardBg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(
                isReady ? Icons.check_circle : Icons.hourglass_empty,
                color: isReady ? AppTheme.secondary : _kTextMuted,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                '$readyCount / $totalPlayers 확인 완료',
                style: const TextStyle(
                  color: _kTextMuted,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (!isReady)
          _buildActionButton(
            label: '역할 확인 완료',
            color: _kGold,
            icon: Icons.check,
            onTap: () => widget.onAction('READY', {}),
          ),
      ],
    );
  }

  Widget _buildAlliesInfo() {
    final allies = List<String>.from(_data['fascistAllies'] ?? []);
    final hitlerId = _data['hitlerId'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kFascistRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kFascistRed.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.visibility, color: _kFascistLight, size: 16),
              SizedBox(width: 8),
              Text(
                '파시스트 비밀 정보',
                style: TextStyle(
                  color: _kFascistLight,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (hitlerId.isNotEmpty)
            _buildInfoRow('히틀러', _nick(hitlerId), _kFascistRed),
          if (allies.isNotEmpty)
            _buildInfoRow(
              '파시스트 동료',
              allies.map((a) => _nick(a)).join(', '),
              _kFascistLight,
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              color: color.withValues(alpha: 0.7),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ── CHANCELLOR_NOMINATION ─────────────────────────────────────────────────

  Widget _buildNomination() {
    if (_presidentId != widget.playerView.playerId) {
      final presidentName = _nick(_presidentId ?? '');
      return _buildWaiting(
          '대통령 $presidentName이(가)\n수상 후보를 지명하고 있습니다...');
    }

    final targets = <_TargetOption>[];
    for (final action in widget.playerView.allowedActions) {
      if (action.actionType == 'NOMINATE') {
        final targetId = action.params['targetId'] as String;
        targets.add(_TargetOption(
          playerId: targetId,
          name: _nick(targetId),
          actionType: 'NOMINATE',
          params: {'targetId': targetId},
        ));
      }
    }

    return Column(
      children: [
        _buildSectionTitle('수상 후보 지명'),
        const SizedBox(height: 8),
        const Text(
          '함께 입법할 수상 후보를 선택하세요',
          style: TextStyle(color: _kTextMuted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        ...targets.map((t) => _buildPlayerSelectCard(t)),
      ],
    );
  }

  Widget _buildPlayerSelectCard(_TargetOption target) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => widget.onAction(target.actionType, target.params),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: _kCardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _kGold.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kGold.withValues(alpha: 0.12),
                    border: Border.all(
                      color: _kGold.withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      target.name[0].toUpperCase(),
                      style: const TextStyle(
                        color: _kGold,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    target.name,
                    style: const TextStyle(
                      color: _kTextLight,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(Icons.arrow_forward_ios,
                    color: _kGold, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── VOTING ────────────────────────────────────────────────────────────────

  Widget _buildVoting() {
    final hasVoted = _data['hasVoted'] as bool? ?? false;
    final currentCount = _data['currentVoteCount'] as int? ?? 0;
    final totalVoters = _data['totalVoters'] as int? ?? 0;
    final candidateId = _chancellorCandidateId ?? '';
    final candidateName = _nick(candidateId);
    final presidentName = _nick(_presidentId ?? '');

    final voteResult = _data['voteResult'] as String?;
    if (voteResult != null) {
      final isPassed = voteResult == 'PASSED';
      return _buildVoteResult(isPassed, presidentName, candidateName);
    }

    return Column(
      children: [
        _buildSectionTitle('투표'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _kCardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kGold.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Text(
                '대통령 $presidentName',
                style: const TextStyle(
                  color: _kGold,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$candidateName을(를) 수상으로 지명',
                style: const TextStyle(
                  color: _kTextLight,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (hasVoted) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kGold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                const Icon(Icons.check_circle, color: _kGold, size: 32),
                const SizedBox(height: 8),
                const Text(
                  '투표 완료',
                  style: TextStyle(
                    color: _kGold,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '다른 플레이어 대기 중... ($currentCount/$totalVoters)',
                  style:
                      const TextStyle(color: _kTextMuted, fontSize: 13),
                ),
              ],
            ),
          ),
        ] else ...[
          Text(
            '투표 진행: $currentCount / $totalVoters',
            style: const TextStyle(color: _kTextMuted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildVoteCard(
                  label: 'Ja!',
                  subtitle: '찬성',
                  color: _kLiberalBlue,
                  icon: Icons.thumb_up_outlined,
                  onTap: () => widget.onAction('VOTE_JA', {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildVoteCard(
                  label: 'Nein!',
                  subtitle: '반대',
                  color: _kFascistRed,
                  icon: Icons.thumb_down_outlined,
                  onTap: () => widget.onAction('VOTE_NEIN', {}),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildVoteCard({
    required String label,
    required String subtitle,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: color.withValues(alpha: 0.5), width: 2),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  color: color.withValues(alpha: 0.7),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVoteResult(
      bool isPassed, String presidentName, String candidateName) {
    final color = isPassed ? _kLiberalBlue : _kFascistRed;
    final text = isPassed ? '가결 — 수상 선출!' : '부결 — 선거 실패';
    final completedVotes =
        Map<String, String>.from(_data['completedVotes'] ?? {});

    return Column(
      children: [
        _buildSectionTitle('투표 결과'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Column(
            children: [
              Icon(
                isPassed ? Icons.celebration : Icons.close,
                color: color,
                size: 40,
              ),
              const SizedBox(height: 8),
              Text(
                text,
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (completedVotes.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kCardBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '개별 투표 결과:',
                  style: TextStyle(
                    color: _kTextMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: completedVotes.entries.map((e) {
                    final isJa = e.value == 'JA';
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isJa
                            ? _kLiberalBlue.withValues(alpha: 0.15)
                            : _kFascistRed.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_nick(e.key)} ${isJa ? "Ja" : "Nein"}',
                        style: TextStyle(
                          color: isJa ? _kLiberalBlue : _kFascistRed,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── LEGISLATIVE_PRESIDENT ─────────────────────────────────────────────────

  Widget _buildLegislativePresident() {
    if (_presidentId != widget.playerView.playerId) {
      return _buildWaiting('대통령이 정책 카드를 검토하고 있습니다...');
    }

    final policies = List<String>.from(_data['drawnPolicies'] ?? []);

    return Column(
      children: [
        _buildSectionTitle('대통령 입법'),
        const SizedBox(height: 8),
        const Text(
          '3장의 정책 중 1장을 버리세요.\n나머지 2장이 수상에게 전달됩니다.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _kTextMuted, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (int i = 0; i < policies.length; i++)
              _buildPolicyCard(
                policy: policies[i],
                label: '버리기',
                onTap: () =>
                    widget.onAction('DISCARD_POLICY', {'discardIndex': i}),
              ),
          ],
        ),
      ],
    );
  }

  // ── LEGISLATIVE_CHANCELLOR ────────────────────────────────────────────────

  Widget _buildLegislativeChancellor() {
    if (_chancellorId != widget.playerView.playerId) {
      return _buildWaiting('수상이 정책을 제정하고 있습니다...');
    }

    final policies = List<String>.from(_data['drawnPolicies'] ?? []);

    return Column(
      children: [
        _buildSectionTitle('수상 입법'),
        const SizedBox(height: 8),
        const Text(
          '2장의 정책 중 1장을 제정하세요.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _kTextMuted, fontSize: 13),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (int i = 0; i < policies.length; i++)
              _buildPolicyCard(
                policy: policies[i],
                label: '제정',
                onTap: () =>
                    widget.onAction('ENACT_POLICY', {'enactIndex': i}),
              ),
          ],
        ),
        if (_vetoUnlocked) ...[
          const SizedBox(height: 20),
          _buildActionButton(
            label: '거부권 요청 (VETO)',
            color: _kFascistRed,
            icon: Icons.block,
            onTap: () => widget.onAction('REQUEST_VETO', {}),
          ),
        ],
      ],
    );
  }

  Widget _buildPolicyCard({
    required String policy,
    required String label,
    required VoidCallback onTap,
  }) {
    final isLiberal = policy == 'LIBERAL';
    final color = isLiberal ? _kLiberalBlue : _kFascistRed;
    const cream = Color(0xFFF5E6C8);
    const creamDark = Color(0xFFE8D5B0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: 105,
          height: 155,
          decoration: BoxDecoration(
            color: cream,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: creamDark, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Container(
            margin: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color, width: 2.5),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 6),
                Icon(
                  isLiberal ? Icons.flutter_dash : Icons.dangerous,
                  color: color,
                  size: 32,
                ),
                const SizedBox(height: 6),
                Text(
                  isLiberal ? 'LIBERAL' : 'FASC1ST',
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                Text(
                  'ARTICLE',
                  style: TextStyle(
                    color: color.withValues(alpha: 0.7),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 6),
                ...List.generate(
                  3,
                  (i) => Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 2),
                    child: Container(
                        height: 1,
                        color: color.withValues(alpha: 0.2)),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── VETO_RESPONSE ─────────────────────────────────────────────────────────

  Widget _buildVetoResponse() {
    if (_presidentId != widget.playerView.playerId) {
      return _buildWaiting('대통령이 거부권 요청을 검토하고 있습니다...');
    }

    return Column(
      children: [
        _buildSectionTitle('거부권 요청'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _kFascistRed.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: _kFascistRed.withValues(alpha: 0.3)),
          ),
          child: const Column(
            children: [
              Icon(Icons.block, color: _kFascistLight, size: 32),
              SizedBox(height: 8),
              Text(
                '수상이 거부권을 요청했습니다!',
                style: TextStyle(
                  color: _kFascistLight,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 4),
              Text(
                '동의하면 모든 정책 카드가 버려집니다.',
                style: TextStyle(color: _kTextMuted, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                label: '거부권 찬성',
                color: _kFascistRed,
                icon: Icons.check,
                onTap: () => widget.onAction('VETO_APPROVE', {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                label: '거부권 반대',
                color: _kLiberalBlue,
                icon: Icons.close,
                onTap: () => widget.onAction('VETO_REJECT', {}),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── EXECUTIVE_ACTION ──────────────────────────────────────────────────────

  Widget _buildExecutiveAction() {
    if (_presidentId != widget.playerView.playerId) {
      return _buildWaiting('대통령이 행정 권한을 행사하고 있습니다...');
    }

    final execType = _data['executiveActionType'] as String? ?? '';

    if (execType == 'POLICY_PEEK') {
      return _buildPolicyPeek();
    }

    String title;
    String description;
    switch (execType) {
      case 'INVESTIGATE':
        title = '조사';
        description = '한 플레이어의 당적을 조사합니다.';
      case 'SPECIAL_ELECTION':
        title = '특별 선거';
        description = '다음 대통령을 직접 지명합니다.';
      case 'EXECUTION':
        title = '처형';
        description = '한 플레이어를 처형합니다. 히틀러가 죽으면 자유주의 승리!';
      default:
        title = execType;
        description = '';
    }

    final targets = <_TargetOption>[];
    for (final action in widget.playerView.allowedActions) {
      if (action.params.containsKey('targetId')) {
        final targetId = action.params['targetId'] as String;
        targets.add(_TargetOption(
          playerId: targetId,
          name: _nick(targetId),
          actionType: action.actionType,
          params: {'targetId': targetId},
        ));
      }
    }

    return Column(
      children: [
        _buildSectionTitle(title),
        const SizedBox(height: 8),
        Text(
          description,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _kTextMuted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        ...targets.map((t) => _buildPlayerSelectCard(t)),
        if (execType == 'INVESTIGATE') _buildInvestigationResults(),
      ],
    );
  }

  Widget _buildInvestigationResults() {
    final results =
        Map<String, dynamic>.from(_data['investigationResults'] ?? {});
    if (results.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kGold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kGold.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '이전 조사 결과:',
            style: TextStyle(
              color: _kGold,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ...results.entries.map((e) {
            final isLib = e.value == 'LIBERAL';
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(
                    isLib ? Icons.verified : Icons.warning,
                    color: isLib ? _kLiberalBlue : _kFascistRed,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_nick(e.key)}: ${isLib ? "자유주의" : "파시스트"}',
                    style: TextStyle(
                      color: isLib ? _kLiberalLight : _kFascistLight,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPolicyPeek() {
    final policies = List<String>.from(_data['drawnPolicies'] ?? []);

    return Column(
      children: [
        _buildSectionTitle('정책 엿보기'),
        const SizedBox(height: 8),
        const Text(
          '덱의 맨 위 3장을 확인합니다.\n이 정보는 당신만 볼 수 있습니다.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _kTextMuted, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final policy in policies)
              Container(
                width: 80,
                height: 110,
                decoration: BoxDecoration(
                  color: policy == 'LIBERAL'
                      ? _kLiberalBlue.withValues(alpha: 0.2)
                      : _kFascistRed.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: policy == 'LIBERAL'
                        ? _kLiberalBlue
                        : _kFascistRed,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        policy == 'LIBERAL'
                            ? Icons.star
                            : Icons.warning_amber,
                        color: policy == 'LIBERAL'
                            ? _kLiberalLight
                            : _kFascistLight,
                        size: 28,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        policy == 'LIBERAL' ? '자유' : '파시',
                        style: TextStyle(
                          color: policy == 'LIBERAL'
                              ? _kLiberalLight
                              : _kFascistLight,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        _buildActionButton(
          label: '확인 완료',
          color: _kGold,
          icon: Icons.check,
          onTap: () => widget.onAction('EXEC_FINISH_PEEK', {}),
        ),
      ],
    );
  }

  // ── GAME OVER ─────────────────────────────────────────────────────────────

  Widget _buildGameOver() {
    final isLiberal = _winner == 'LIBERAL';
    final winColor = isLiberal ? _kLiberalBlue : _kFascistRed;
    final winTeam = isLiberal ? '자유주의 승리!' : '파시스트 승리!';
    final myTeamWon = (isLiberal && _myParty == 'LIBERAL') ||
        (!isLiberal && _myParty == 'FASCIST');

    final allRoles = Map<String, String>.from(_data['allRoles'] ?? {});

    return Column(
      children: [
        const SizedBox(height: 16),
        Icon(
          myTeamWon
              ? Icons.celebration
              : Icons.sentiment_very_dissatisfied,
          color: winColor,
          size: 48,
        ),
        const SizedBox(height: 12),
        Text(
          winTeam,
          style: TextStyle(
            color: winColor,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          myTeamWon ? '축하합니다! 당신의 팀이 이겼습니다!' : '아쉽게도 패배했습니다.',
          style: const TextStyle(color: _kTextMuted, fontSize: 14),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _kCardBg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '전체 역할 공개',
                style: TextStyle(
                  color: _kGold,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              ...allRoles.entries.map((e) {
                final roleColor =
                    e.value == 'LIBERAL' ? _kLiberalBlue : _kFascistRed;
                final roleLabel = e.value == 'LIBERAL'
                    ? '자유주의'
                    : e.value == 'HITLER'
                        ? '히틀러'
                        : '파시스트';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: roleColor,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _nick(e.key),
                          style: const TextStyle(
                            color: _kTextLight,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: roleColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          roleLabel,
                          style: TextStyle(
                            color: roleColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  // ── DEAD STATE ────────────────────────────────────────────────────────────

  Widget _buildDead() {
    return Column(
      children: [
        const SizedBox(height: 40),
        const Icon(Icons.sentiment_very_dissatisfied,
            color: _kFascistRed, size: 48),
        const SizedBox(height: 16),
        const Text(
          '처형되었습니다',
          style: TextStyle(
            color: _kFascistRed,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '더 이상 게임에 참여할 수 없습니다.\n관전 모드로 게임을 지켜보세요.',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: _kTextMuted, fontSize: 14, height: 1.5),
        ),
      ],
    );
  }

  // ── WAITING STATE ─────────────────────────────────────────────────────────

  Widget _buildWaiting(String message) {
    return Column(
      children: [
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: _kCardBg,
            borderRadius: BorderRadius.circular(20),
            border:
                Border.all(color: _kGold.withValues(alpha: 0.1)),
          ),
          child: Column(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation(
                      _kGold.withValues(alpha: 0.5)),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _kTextMuted,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Role Card ─────────────────────────────────────────────────────────────

  Widget _buildRoleCard({bool expanded = false}) {
    final isLiberal = _myParty == 'LIBERAL';
    final color = isLiberal ? _kLiberalBlue : _kFascistRed;
    final lightColor = isLiberal ? _kLiberalLight : _kFascistLight;
    final roleLabel = _myRole == 'LIBERAL'
        ? '자유주의자'
        : _myRole == 'HITLER'
            ? '히틀러'
            : '파시스트';
    final partyLabel = isLiberal ? 'LIBERAL' : 'FASCIST';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(expanded ? 24 : 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.25),
            color.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          if (expanded) ...[
            Text(
              partyLabel,
              style: TextStyle(
                color: lightColor.withValues(alpha: 0.5),
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Icon(
            _myRole == 'HITLER'
                ? Icons.sentiment_very_dissatisfied
                : isLiberal
                    ? Icons.star
                    : Icons.warning_amber,
            color: lightColor,
            size: expanded ? 56 : 28,
          ),
          SizedBox(height: expanded ? 12 : 6),
          Text(
            roleLabel,
            style: TextStyle(
              color: lightColor,
              fontSize: expanded ? 24 : 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 8),
            Text(
              _getRoleDescription(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: lightColor.withValues(alpha: 0.7),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getRoleDescription() {
    switch (_myRole) {
      case 'LIBERAL':
        return '파시스트와 히틀러를 찾아내세요.\n자유주의 정책 5장을 제정하면 승리합니다.';
      case 'FASCIST':
        return '히틀러를 보호하고 파시스트 정책을 제정하세요.\n히틀러가 수상이 되거나 파시스트 정책 6장이면 승리합니다.';
      case 'HITLER':
        return '당신이 히틀러입니다. 정체를 숨기세요.\n파시스트 정책 3장 이후 수상이 되면 승리합니다.';
      default:
        return '';
    }
  }

  // ── Shared Widgets ────────────────────────────────────────────────────────

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: _kGold,
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: 1,
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Canvas card painter — physical-card-style rendering
// ─────────────────────────────────────────────────────────────────────────────

class _CardPainter extends CustomPainter {
  final Color bgColor;
  final Color accentColor;
  final String title;
  final String subtitle;
  final bool isLiberal;

  const _CardPainter({
    required this.bgColor,
    required this.accentColor,
    required this.title,
    required this.subtitle,
    required this.isLiberal,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      const Radius.circular(16),
    );

    // Background
    final bgPaint = Paint()..color = bgColor;
    canvas.drawRRect(rrect, bgPaint);

    // Outer border
    final borderPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(rrect, borderPaint);

    // Inner decorative frame — inset by 10px on each side
    const inset = 10.0;
    final innerRect = Rect.fromLTWH(inset, inset, w - inset * 2, h - inset * 2);
    final innerRRect = RRect.fromRectAndRadius(
      innerRect,
      const Radius.circular(10),
    );
    final innerBorderPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(innerRRect, innerBorderPaint);

    // Corner decorative dots
    _drawCornerDot(canvas, inset + 6, inset + 6);
    _drawCornerDot(canvas, w - inset - 6, inset + 6);
    _drawCornerDot(canvas, inset + 6, h - inset - 6);
    _drawCornerDot(canvas, w - inset - 6, h - inset - 6);

    // Emblem area — centered vertically in upper 55% of card
    _drawEmblem(canvas, Offset(w / 2, h * 0.22));

    // Title text
    final titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        style: TextStyle(
          color: accentColor,
          fontSize: 26,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: w - inset * 4);
    titlePainter.paint(
      canvas,
      Offset((w - titlePainter.width) / 2, h * 0.5),
    );

    // Horizontal divider below title
    final dividerPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(w * 0.2, h * 0.63),
      Offset(w * 0.8, h * 0.63),
      dividerPaint,
    );

    // Subtitle text
    final subtitlePainter = TextPainter(
      text: TextSpan(
        text: subtitle,
        style: TextStyle(
          color: accentColor.withValues(alpha: 0.6),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 2,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: w - inset * 4);
    subtitlePainter.paint(
      canvas,
      Offset((w - subtitlePainter.width) / 2, h * 0.67),
    );

    // Decorative lines near bottom
    for (int i = 0; i < 3; i++) {
      final lineY = h * 0.78 + i * 7.0;
      canvas.drawLine(
        Offset(w * 0.25, lineY),
        Offset(w * 0.75, lineY),
        Paint()
          ..color = accentColor.withValues(alpha: 0.12)
          ..strokeWidth = 1,
      );
    }
  }

  void _drawCornerDot(Canvas canvas, double x, double y) {
    canvas.drawCircle(
      Offset(x, y),
      2.5,
      Paint()..color = accentColor.withValues(alpha: 0.4),
    );
  }

  void _drawEmblem(Canvas canvas, Offset center) {
    if (isLiberal) {
      _drawDoveEmblem(canvas, center);
    } else {
      _drawSkullEmblem(canvas, center);
    }
  }

  /// Dove emblem for liberal party — simplified geometric representation.
  void _drawDoveEmblem(Canvas canvas, Offset center) {
    final paint = Paint()
      ..color = accentColor.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;

    // Body ellipse
    canvas.drawOval(
      Rect.fromCenter(center: center, width: 28, height: 18),
      paint,
    );

    // Head circle
    canvas.drawCircle(
      Offset(center.dx + 16, center.dy - 6),
      7,
      paint,
    );

    // Wing — arc path
    final wingPath = Path()
      ..moveTo(center.dx - 14, center.dy - 2)
      ..quadraticBezierTo(
        center.dx,
        center.dy - 22,
        center.dx + 10,
        center.dy - 4,
      )
      ..close();
    canvas.drawPath(wingPath, paint);

    // Tail
    final tailPath = Path()
      ..moveTo(center.dx - 14, center.dy + 2)
      ..lineTo(center.dx - 26, center.dy + 8)
      ..lineTo(center.dx - 14, center.dy + 8)
      ..close();
    canvas.drawPath(tailPath, paint);

    // Eye dot (white)
    canvas.drawCircle(
      Offset(center.dx + 18, center.dy - 7),
      2,
      Paint()..color = bgColor,
    );
  }

  /// Skull emblem for fascist party — simplified geometric skull.
  void _drawSkullEmblem(Canvas canvas, Offset center) {
    final paint = Paint()
      ..color = accentColor.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;

    // Cranium — rounded square
    final craniumRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy - 4),
      width: 30,
      height: 26,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(craniumRect, const Radius.circular(8)),
      paint,
    );

    // Jaw — smaller rectangle
    final jawRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy + 12),
      width: 22,
      height: 10,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(jawRect, const Radius.circular(3)),
      paint,
    );

    // Eye sockets (cutouts using bg color)
    final eyePaint = Paint()..color = bgColor;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx - 7, center.dy - 5),
        width: 9,
        height: 9,
      ),
      eyePaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx + 7, center.dy - 5),
        width: 9,
        height: 9,
      ),
      eyePaint,
    );

    // Nose (small triangle cutout)
    final nosePath = Path()
      ..moveTo(center.dx, center.dy + 3)
      ..lineTo(center.dx - 3, center.dy + 8)
      ..lineTo(center.dx + 3, center.dy + 8)
      ..close();
    canvas.drawPath(nosePath, Paint()..color = bgColor);

    // Teeth lines on jaw
    final toothPaint = Paint()
      ..color = bgColor
      ..strokeWidth = 2;
    for (int i = 0; i < 3; i++) {
      final x = center.dx - 7 + i * 7.0;
      canvas.drawLine(
        Offset(x, center.dy + 8),
        Offset(x, center.dy + 15),
        toothPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_CardPainter oldDelegate) =>
      oldDelegate.bgColor != bgColor ||
      oldDelegate.accentColor != accentColor ||
      oldDelegate.title != title ||
      oldDelegate.subtitle != subtitle ||
      oldDelegate.isLiberal != isLiberal;
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper class
// ─────────────────────────────────────────────────────────────────────────────

class _TargetOption {
  final String playerId;
  final String name;
  final String actionType;
  final Map<String, dynamic> params;

  const _TargetOption({
    required this.playerId,
    required this.name,
    required this.actionType,
    required this.params,
  });
}
