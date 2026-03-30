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

const Color _kFascistRed = Color(0xFFE53935);
const Color _kFascistLight = Color(0xFFEF5350);

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
// SecretHitlerNodeWidget — Player phone UI
// ─────────────────────────────────────────────────────────────────────────────

/// Full-featured player node UI for the Secret Hitler game pack.
///
/// Renders phase-specific interaction panels:
/// - ROLE_REVEAL: Role card with party affiliation
/// - CHANCELLOR_NOMINATION: Target selection for president
/// - VOTING: Ja/Nein vote cards
/// - LEGISLATIVE_PRESIDENT: Policy discard selection
/// - LEGISLATIVE_CHANCELLOR: Policy enact selection + veto
/// - VETO_RESPONSE: Approve/reject veto
/// - EXECUTIVE_ACTION: Target selection for executive powers
/// - Waiting state for non-active players
class SecretHitlerNodeWidget extends StatelessWidget {
  final PlayerView playerView;
  final void Function(String type, Map<String, dynamic> params) onAction;

  const SecretHitlerNodeWidget({
    super.key,
    required this.playerView,
    required this.onAction,
  });

  Map<String, dynamic> get _data => playerView.data;
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

  @override
  Widget build(BuildContext context) {
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
            // Status bar
            _buildStatusBar(),
            // Main content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    _buildPhaseContent(),
                    const SizedBox(height: 16),
                    // Role summary footer
                    _buildRoleSummary(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Status Bar ────────────────────────────────────────────────────────────

  Widget _buildStatusBar() {
    final phaseLabel = _phaseLabels[_phase] ?? _phase;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _kBgDark.withValues(alpha: 0.8),
        border: Border(
          bottom: BorderSide(
            color: _kGold.withValues(alpha: 0.15),
          ),
        ),
      ),
      child: Row(
        children: [
          // Policy counters
          _buildPolicyBadge(_liberalPolicies, 5, _kLiberalBlue),
          const SizedBox(width: 8),
          _buildPolicyBadge(_fascistPolicies, 6, _kFascistRed),
          const Spacer(),
          // Phase chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _kGold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: _kGold.withValues(alpha: 0.3)),
            ),
            child: Text(
              phaseLabel,
              style: const TextStyle(
                color: _kGold,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPolicyBadge(int current, int total, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$current / $total',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ── Phase Content Router ──────────────────────────────────────────────────

  Widget _buildPhaseContent() {
    if (_winner != null) return _buildGameOver();
    if (_deadPlayers.contains(playerView.playerId)) return _buildDead();

    switch (_phase) {
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
        // Fascist allies info
        if (_myRole == 'FASCIST' || (_myRole == 'HITLER' && totalPlayers <= 6))
          _buildAlliesInfo(),
        const SizedBox(height: 16),
        // Ready status
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            onTap: () => onAction('READY', {}),
          ),
      ],
    );
  }

  Widget _buildAlliesInfo() {
    final allies =
        List<String>.from(_data['fascistAllies'] ?? []);
    final hitlerId = _data['hitlerId'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kFascistRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _kFascistRed.withValues(alpha: 0.3),
        ),
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
    if (_presidentId != playerView.playerId) {
      final presidentName = _nick(_presidentId ?? '');
      return _buildWaiting('대통령 $presidentName이(가)\n수상 후보를 지명하고 있습니다...');
    }

    // President UI: select chancellor
    final targets = <_TargetOption>[];
    for (final action in playerView.allowedActions) {
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
          onTap: () => onAction(target.actionType, target.params),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: _kCardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _kGold.withValues(alpha: 0.2),
              ),
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

    // Vote result display
    final voteResult = _data['voteResult'] as String?;
    if (voteResult != null) {
      final isPassed = voteResult == 'PASSED';
      return _buildVoteResult(isPassed, presidentName, candidateName);
    }

    return Column(
      children: [
        _buildSectionTitle('투표'),
        const SizedBox(height: 8),
        // Candidate info card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _kCardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _kGold.withValues(alpha: 0.2),
            ),
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
                  style: const TextStyle(
                    color: _kTextMuted,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          // Vote progress
          Text(
            '투표 진행: $currentCount / $totalVoters',
            style: const TextStyle(color: _kTextMuted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          // Vote buttons
          Row(
            children: [
              Expanded(
                child: _buildVoteCard(
                  label: 'Ja!',
                  subtitle: '찬성',
                  color: _kLiberalBlue,
                  icon: Icons.thumb_up_outlined,
                  onTap: () => onAction('VOTE_JA', {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildVoteCard(
                  label: 'Nein!',
                  subtitle: '반대',
                  color: _kFascistRed,
                  icon: Icons.thumb_down_outlined,
                  onTap: () => onAction('VOTE_NEIN', {}),
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
            border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
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

    // Completed votes display
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
        // Individual vote display
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
    if (_presidentId != playerView.playerId) {
      return _buildWaiting('대통령이 정책 카드를 검토하고 있습니다...');
    }

    final policies =
        List<String>.from(_data['drawnPolicies'] ?? []);

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
                    onAction('DISCARD_POLICY', {'discardIndex': i}),
              ),
          ],
        ),
      ],
    );
  }

  // ── LEGISLATIVE_CHANCELLOR ────────────────────────────────────────────────

  Widget _buildLegislativeChancellor() {
    if (_chancellorId != playerView.playerId) {
      return _buildWaiting('수상이 정책을 제정하고 있습니다...');
    }

    final policies =
        List<String>.from(_data['drawnPolicies'] ?? []);

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
                    onAction('ENACT_POLICY', {'enactIndex': i}),
              ),
          ],
        ),
        if (_vetoUnlocked) ...[
          const SizedBox(height: 20),
          _buildActionButton(
            label: '거부권 요청 (VETO)',
            color: _kFascistRed,
            icon: Icons.block,
            onTap: () => onAction('REQUEST_VETO', {}),
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
    final lightColor = isLiberal ? _kLiberalLight : _kFascistLight;
    final policyName = isLiberal ? '자유주의' : '파시스트';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 100,
          height: 150,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.3),
                color.withValues(alpha: 0.15),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color, width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.2),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isLiberal ? Icons.star : Icons.warning_amber,
                color: lightColor,
                size: 36,
              ),
              const SizedBox(height: 8),
              Text(
                policyName,
                style: TextStyle(
                  color: lightColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: lightColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── VETO_RESPONSE ─────────────────────────────────────────────────────────

  Widget _buildVetoResponse() {
    if (_presidentId != playerView.playerId) {
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
            border: Border.all(
              color: _kFascistRed.withValues(alpha: 0.3),
            ),
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
                onTap: () => onAction('VETO_APPROVE', {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                label: '거부권 반대',
                color: _kLiberalBlue,
                icon: Icons.close,
                onTap: () => onAction('VETO_REJECT', {}),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── EXECUTIVE_ACTION ──────────────────────────────────────────────────────

  Widget _buildExecutiveAction() {
    if (_presidentId != playerView.playerId) {
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
    for (final action in playerView.allowedActions) {
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
        // Show investigation results if any
        if (execType == 'INVESTIGATE') _buildInvestigationResults(),
      ],
    );
  }

  Widget _buildInvestigationResults() {
    final results = Map<String, dynamic>.from(
        _data['investigationResults'] ?? {});
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
          onTap: () => onAction('EXEC_FINISH_PEEK', {}),
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

    final allRoles =
        Map<String, String>.from(_data['allRoles'] ?? {});

    return Column(
      children: [
        const SizedBox(height: 16),
        Icon(
          myTeamWon ? Icons.celebration : Icons.sentiment_very_dissatisfied,
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
        // All roles reveal
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
                final roleColor = e.value == 'LIBERAL'
                    ? _kLiberalBlue
                    : _kFascistRed;
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
          style: TextStyle(color: _kTextMuted, fontSize: 14, height: 1.5),
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
            border: Border.all(
              color: _kGold.withValues(alpha: 0.1),
            ),
          ),
          child: Column(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor:
                      AlwaysStoppedAnimation(_kGold.withValues(alpha: 0.5)),
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

  // ── Role Summary (footer) ─────────────────────────────────────────────────

  Widget _buildRoleSummary() {
    if (_phase == 'ROLE_REVEAL') return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _kCardBg.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            _myRole == 'HITLER'
                ? Icons.sentiment_very_dissatisfied
                : _myParty == 'LIBERAL'
                    ? Icons.star
                    : Icons.warning_amber,
            color: _myParty == 'LIBERAL' ? _kLiberalBlue : _kFascistRed,
            size: 20,
          ),
          const SizedBox(width: 10),
          Text(
            _myRole == 'LIBERAL'
                ? '자유주의자'
                : _myRole == 'HITLER'
                    ? '히틀러'
                    : '파시스트',
            style: TextStyle(
              color:
                  _myParty == 'LIBERAL' ? _kLiberalLight : _kFascistLight,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          if (_presidentId == playerView.playerId)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _kGold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '대통령',
                style: TextStyle(
                  color: _kGold,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else if (_chancellorId == playerView.playerId)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _kLiberalBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '수상',
                style: TextStyle(
                  color: _kLiberalBlue,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
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
