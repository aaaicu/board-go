import 'package:flutter/material.dart';

/// A simple action button that lets the player send a named action to the
/// GameBoard server.
class PlayerActionWidget extends StatelessWidget {
  final String actionType;
  final Map<String, dynamic> actionData;
  final VoidCallback? onAction;
  final String? label;

  const PlayerActionWidget({
    super.key,
    required this.actionType,
    this.actionData = const {},
    this.onAction,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onAction,
      child: Text(label ?? actionType),
    );
  }
}
