import 'package:flutter/material.dart';

import 'client/gameboard/gameboard_screen.dart';
import 'client/gamenode/gamenode_screen.dart';

void main() {
  runApp(const BoardGoApp());
}

class BoardGoApp extends StatelessWidget {
  const BoardGoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'board-go',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4A6FA5)),
        useMaterial3: true,
      ),
      home: const RoleSelectScreen(),
    );
  }
}

/// 앱 첫 화면 — 이 기기의 역할(보드/플레이어)을 선택한다.
class RoleSelectScreen extends StatelessWidget {
  const RoleSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              // 로고/타이틀
              const Text(
                'board-go',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '이 기기의 역할을 선택해주세요',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const Spacer(),
              // GameBoard 버튼
              _RoleCard(
                icon: Icons.tv,
                title: '게임 보드',
                subtitle: '서버 역할 · 모든 플레이어가 볼 수 있는 화면\n(태블릿 권장)',
                color: const Color(0xFF4A6FA5),
                onTap: () => _go(context, const GameboardScreen()),
              ),
              const SizedBox(height: 16),
              // GameNode 버튼
              _RoleCard(
                icon: Icons.phone_android,
                title: '플레이어',
                subtitle: '개인 액션 화면 · 게임 보드에 접속\n(스마트폰)',
                color: const Color(0xFF2E8B57),
                onTap: () => _go(context, const GameNodeScreen()),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  void _go(BuildContext context, Widget screen) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Icon(icon, size: 48, color: Colors.white),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white70,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}
