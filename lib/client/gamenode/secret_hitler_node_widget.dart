import 'package:flutter/material.dart';

import '../../shared/game_pack/views/player_view.dart';
import '../../shared/game_pack/views/allowed_action.dart';
import '../shared/app_theme.dart';
import 'player_action_widget.dart';

class SecretHitlerNodeWidget extends StatelessWidget {
  final PlayerView playerView;
  final Function(String actionType, Map<String, dynamic> data) onAction;

  const SecretHitlerNodeWidget({
    super.key,
    required this.playerView,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final data = playerView.data;
    final myRole = data['myRole'] as String? ?? 'UNKNOWN';
    final phase = data['phase'] as String? ?? 'UNKNOWN';
    final hitlerId = data['hitlerId'] as String?;
    final allies = List<String>.from(data['fascistAllies'] ?? []);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
             Text(
              'SECRET HITLER',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppTheme.primary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            _buildRoleCard(context, myRole, hitlerId, allies),
            const SizedBox(height: 24),
            Expanded(
              child: _buildActionArea(context, phase),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleCard(BuildContext context, String role, String? hitlerId, List<String> allies) {
    Color cardColor = AppTheme.surfaceContainerHigh;
    if (role == 'FASCIST' || role == 'HITLER') {
      cardColor = AppTheme.errorContainer;
    } else if (role == 'LIBERAL') {
      cardColor = AppTheme.primaryContainer;
    }

    return Card(
      color: cardColor,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Text('당신의 역할', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              role,
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: role == 'LIBERAL' ? AppTheme.primary : AppTheme.error,
              ),
            ),
            if (role == 'FASCIST') ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              if (hitlerId != null) Text('히틀러: $hitlerId'),
              if (allies.isNotEmpty) Text('파시스트 동지: ${allies.join(', ')}'),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildActionArea(BuildContext context, String phase) {
    if (playerView.allowedActions.isEmpty) {
      return const Center(
        child: Text(
          '현재 차례가 아닙니다.\n보드를 확인하세요.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, color: AppTheme.onSurfaceMuted),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '행동 선택 ($phase)',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 16),
        ...playerView.allowedActions.map((action) => Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: PlayerActionWidget(
             action: action,
             onAction: (a, d) => onAction(a, d),
          ),
        )).toList(),
      ],
    );
  }
}
