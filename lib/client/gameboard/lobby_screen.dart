import 'package:flutter/material.dart';

import '../../shared/game_pack/game_pack_loader.dart';
import '../../shared/game_pack/game_pack_manifest.dart';
import '../../shared/messages/lobby_state_message.dart';
import '../shared/app_theme.dart';
import '../shared/widgets/board_card.dart';
import '../shared/widgets/primary_button.dart';
import '../shared/widgets/status_chip.dart';
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

  GamePackManifest? get _selectedPack =>
      _packs?.where((p) => p.id == _selectedPackId).firstOrNull;

  bool get _canStart {
    if (!widget.lobbyState.canStart) return false;
    final pack = _selectedPack;
    if (pack == null) return false;
    final count = widget.lobbyState.players.length;
    return count >= pack.minPlayers && count <= pack.maxPlayers;
  }

  String get _startButtonLabel {
    if (_selectedPackId == null) return '게임 팩을 선택하세요';
    final pack = _selectedPack;
    if (pack != null) {
      final count = widget.lobbyState.players.length;
      if (count < pack.minPlayers) {
        return '최소 ${pack.minPlayers}명 필요 (현재 $count명)';
      }
      if (count > pack.maxPlayers) {
        return '최대 ${pack.maxPlayers}명 초과 (현재 $count명)';
      }
    }
    if (!widget.lobbyState.canStart) return '모든 플레이어 준비 완료 후 시작 가능';
    return '게임 시작';
  }

  @override
  Widget build(BuildContext context) {
    // iPad layout: two-column side-by-side (pack + player | QR + start)
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 700;
        if (isWide) {
          return _buildWideLayout(context);
        }
        return _buildNarrowLayout(context);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Wide layout (iPad landscape / tablet)
  // ---------------------------------------------------------------------------

  Widget _buildWideLayout(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left column: pack selector + player list
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 12, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSectionHeader(context, '게임 팩 선택'),
                const SizedBox(height: 12),
                _buildPackSelectorContent(context),
                const SizedBox(height: 24),
                _buildSectionHeader(
                  context,
                  '플레이어 (${widget.lobbyState.players.length}명)',
                ),
                const SizedBox(height: 12),
                _buildPlayerList(context),
              ],
            ),
          ),
        ),
        // Right column: QR code + start button
        Expanded(
          flex: 2,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 24, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildQrSection(context),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: _startButtonLabel,
                  onPressed: _canStart
                      ? () => widget.onStartGame?.call(_selectedPackId!)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Narrow layout (phone-sized)
  // ---------------------------------------------------------------------------

  Widget _buildNarrowLayout(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader(context, '게임 팩 선택'),
          const SizedBox(height: 12),
          _buildPackSelectorContent(context),
          const SizedBox(height: 24),
          _buildSectionHeader(
            context,
            '플레이어 (${widget.lobbyState.players.length}명)',
          ),
          const SizedBox(height: 12),
          _buildPlayerList(context),
          const SizedBox(height: 24),
          _buildQrSection(context),
          const SizedBox(height: 24),
          PrimaryButton(
            label: _startButtonLabel,
            onPressed: _canStart
                ? () => widget.onStartGame?.call(_selectedPackId!)
                : null,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Section header — no border, just spacing + typography
  // ---------------------------------------------------------------------------

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: const TextStyle(
        fontFamily: 'Manrope',
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppTheme.onSurface,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Pack selector
  // ---------------------------------------------------------------------------

  Widget _buildPackSelectorContent(BuildContext context) {
    if (_loadError) {
      return _buildInfoCard(
        child: const Text(
          '게임 팩을 불러오는 데 실패했습니다.',
          style: TextStyle(color: AppTheme.error),
        ),
      );
    }

    final packs = _packs;
    if (packs == null) {
      return _buildInfoCard(
        child: const Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
      );
    }

    if (packs.isEmpty) {
      return _buildInfoCard(
        child: const Text(
          '사용 가능한 게임 팩이 없습니다.',
          style: TextStyle(color: AppTheme.onSurfaceMuted),
        ),
      );
    }

    return Column(
      children: packs
          .map(
            (pack) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PackCard(
                pack: pack,
                isSelected: _selectedPackId == pack.id,
                onTap: () => setState(() => _selectedPackId = pack.id),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildInfoCard({required Widget child}) {
    return BoardCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: child,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Player list
  // ---------------------------------------------------------------------------

  Widget _buildPlayerList(BuildContext context) {
    if (widget.lobbyState.players.isEmpty) {
      return BoardCard(
        child: const Text(
          '아직 접속한 플레이어가 없습니다.',
          style: TextStyle(color: AppTheme.onSurfaceMuted),
        ),
      );
    }

    return Column(
      children: widget.lobbyState.players
          .map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PlayerRow(info: p),
            ),
          )
          .toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // QR / connection info
  // ---------------------------------------------------------------------------

  Widget _buildQrSection(BuildContext context) {
    return BoardCard(
      child: Column(
        children: [
          const Text(
            'QR 코드로 접속하세요',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '스마트폰 카메라로 스캔하여 참여',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.onSurfaceMuted,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: QrCodeWidget(
                connectionData: widget.qrData,
                displayText: null,
                size: 180,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // IP address badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.primaryContainer,
              borderRadius: BorderRadius.circular(9999),
            ),
            child: Text(
              widget.serverAddress,
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppTheme.primary,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
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
    return BoardCard(
      onTap: onTap,
      isSelected: isSelected,
      backgroundColor: isSelected
          ? AppTheme.surfaceContainerHighest
          : AppTheme.surfaceContainerHigh,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Illustration placeholder — colored accent block
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.primaryContainer
                  : AppTheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.extension,
              color: isSelected ? AppTheme.primary : AppTheme.onSurfaceMuted,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pack.nameKo,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? AppTheme.primary
                        : AppTheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  pack.description,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.onSurfaceMuted,
                    height: 1.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                // Meta row: player count + estimated time
                Row(
                  children: [
                    const Icon(
                      Icons.people_outline,
                      size: 13,
                      color: AppTheme.onSurfaceMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${pack.minPlayers}–${pack.maxPlayers}명',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.onSurfaceMuted,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.timer_outlined,
                      size: 13,
                      color: AppTheme.onSurfaceMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '약 ${pack.estimatedMinutes}분',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isSelected) ...[
            const SizedBox(width: 8),
            const Icon(
              Icons.check_circle_rounded,
              color: AppTheme.primary,
              size: 22,
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Player row widget
// ---------------------------------------------------------------------------

class _PlayerRow extends StatelessWidget {
  final LobbyStatePlayerInfo info;

  const _PlayerRow({required this.info});

  @override
  Widget build(BuildContext context) {
    return BoardCard(
      backgroundColor: AppTheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      borderRadius: 16,
      child: Row(
        children: [
          // Avatar circle with initial letter
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primaryContainer,
            ),
            child: Center(
              child: Text(
                info.nickname.isNotEmpty
                    ? info.nickname[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Online dot + nickname
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  OnlineDot(isOnline: info.isConnected),
                  const SizedBox(width: 6),
                  Text(
                    info.nickname,
                    style: const TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                info.isConnected ? '온라인' : '오프라인',
                style: TextStyle(
                  fontSize: 12,
                  color: info.isConnected
                      ? AppTheme.onSurfaceMuted
                      : AppTheme.offlineDot,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Ready chip
          StatusChip(
            status: info.isReady ? ChipStatus.ready : ChipStatus.waiting,
          ),
        ],
      ),
    );
  }
}
