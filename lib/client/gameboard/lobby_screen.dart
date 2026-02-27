import 'package:flutter/material.dart';

import '../../shared/game_pack/game_pack_loader.dart';
import '../../shared/game_pack/game_pack_manifest.dart';
import '../../shared/messages/lobby_state_message.dart';
import 'qr_code_widget.dart';

/// Callback invoked when the host taps "게임 시작".
///
/// [packId] is the stable identifier of the selected [GamePackManifest].
typedef OnStartGame = void Function(String packId);

/// GameBoard lobby screen displayed on the iPad while players join and
/// mark themselves as ready.
///
/// Shows:
///   - Game-pack selector (loaded asynchronously from the asset bundle).
///   - QR code + IP:Port for players to scan/enter.
///   - Per-player ready status list.
///   - "게임 시작" button — enabled only when [lobbyState.canStart] is true
///     AND a game pack has been selected.
class LobbyScreen extends StatefulWidget {
  final LobbyStateMessage lobbyState;
  final String serverAddress; // "192.168.x.x:8080"
  final String qrData; // "ws://192.168.x.x:8080/ws"

  /// Invoked when the host taps "게임 시작" with the selected pack ID.
  final OnStartGame? onStartGame;

  /// Override in tests to avoid hitting the real asset bundle.
  final GamePackLoader? packLoader;

  const LobbyScreen({
    super.key,
    required this.lobbyState,
    required this.serverAddress,
    required this.qrData,
    this.onStartGame,
    this.packLoader,
  });

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  List<GamePackManifest>? _packs;
  String? _selectedPackId;
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    _loadPacks();
  }

  Future<void> _loadPacks() async {
    try {
      final loader = widget.packLoader ?? GamePackLoader();
      final packs = await loader.listAvailablePacks();
      if (!mounted) return;
      setState(() {
        _packs = packs;
        // Auto-select the first pack when there is only one option.
        if (packs.length == 1) _selectedPackId = packs.first.id;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadError = true);
    }
  }

  bool get _canStart =>
      widget.lobbyState.canStart && _selectedPackId != null;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- Game-pack selector ---
          _buildPackSelector(context),
          const SizedBox(height: 16),

          // --- Player list ---
          _buildPlayerList(context),
          const SizedBox(height: 16),

          // --- Start game button ---
          ElevatedButton(
            onPressed: _canStart
                ? () => widget.onStartGame?.call(_selectedPackId!)
                : null,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(
              _startButtonLabel,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(height: 24),

          // --- QR / connection info ---
          Text(
            'QR 코드로 접속하세요',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Center(
            child: QrCodeWidget(
              connectionData: qrData,
              displayText: serverAddress,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Sub-builders
  // ---------------------------------------------------------------------------

  Widget _buildPackSelector(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '게임 팩 선택',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Divider(),
            _buildPackSelectorContent(context),
          ],
        ),
      ),
    );
  }

  Widget _buildPackSelectorContent(BuildContext context) {
    if (_loadError) {
      return const Text('게임 팩을 불러오는 데 실패했습니다.');
    }

    final packs = _packs;
    if (packs == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (packs.isEmpty) {
      return const Text('사용 가능한 게임 팩이 없습니다.');
    }

    return Column(
      children: packs.map((pack) => _PackCard(
        pack: pack,
        isSelected: _selectedPackId == pack.id,
        onTap: () => setState(() => _selectedPackId = pack.id),
      )).toList(),
    );
  }

  Widget _buildPlayerList(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '플레이어 (${widget.lobbyState.players.length}명)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Divider(),
            if (widget.lobbyState.players.isEmpty)
              const Text('아직 접속한 플레이어가 없습니다.')
            else
              ...widget.lobbyState.players.map(
                (p) => _PlayerRow(info: p),
              ),
          ],
        ),
      ),
    );
  }

  String get _startButtonLabel {
    if (_selectedPackId == null) return '게임 팩을 선택하세요';
    if (!widget.lobbyState.canStart) return '모든 플레이어가 준비 완료되면 시작 가능합니다';
    return '게임 시작';
  }

  // Expose for QrCodeWidget.
  String get qrData => widget.qrData;
  String get serverAddress => widget.serverAddress;
}

// ---------------------------------------------------------------------------
// Game-pack card widget
// ---------------------------------------------------------------------------

class _PackCard extends StatelessWidget {
  final GamePackManifest pack;
  final bool isSelected;
  final VoidCallback onTap;

  const _PackCard({
    required this.pack,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pack.nameKo,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    pack.description,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.people, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '${pack.minPlayers}–${pack.maxPlayers}명',
                        style: theme.textTheme.labelSmall,
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.timer, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '약 ${pack.estimatedMinutes}분',
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Player row widget
// ---------------------------------------------------------------------------

/// A single row in the player list showing nickname and ready indicator.
class _PlayerRow extends StatelessWidget {
  final LobbyStatePlayerInfo info;

  const _PlayerRow({required this.info});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            info.isConnected ? Icons.person : Icons.person_off,
            size: 20,
            color: info.isConnected ? Colors.blue : Colors.grey,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              info.nickname,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          Icon(
            info.isReady ? Icons.check_circle : Icons.radio_button_unchecked,
            color: info.isReady ? Colors.green : Colors.orange,
            size: 20,
          ),
          const SizedBox(width: 4),
          Text(
            info.isReady ? '준비 완료' : '대기 중',
            style: TextStyle(
              fontSize: 12,
              color: info.isReady ? Colors.green : Colors.orange,
            ),
          ),
        ],
      ),
    );
  }
}
