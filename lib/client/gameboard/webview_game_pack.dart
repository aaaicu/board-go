import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../shared/messages/ws_message.dart';
import '../../shared/messages/action_message.dart';

/// Hosts an HTML/JS game pack inside a [WebView].
///
/// The WebView communicates with the Flutter layer through a JavaScript
/// channel named `GameBridge`.  Game packs post messages in the same
/// [WsMessage] JSON format used by the WebSocket protocol.
///
/// **Usage**:
/// ```dart
/// WebViewGamePack(
///   htmlContent: '<html>...</html>',
///   onAction: (action) { /* forward to server */ },
/// )
/// ```
class WebViewGamePack extends StatefulWidget {
  /// The raw HTML source of the game pack.
  final String htmlContent;

  /// Called whenever the embedded game posts a player action.
  final void Function(ActionMessage action)? onAction;

  /// An optional initial game state JSON injected into the WebView on load.
  final Map<String, dynamic>? initialState;

  const WebViewGamePack({
    super.key,
    required this.htmlContent,
    this.onAction,
    this.initialState,
  });

  @override
  State<WebViewGamePack> createState() => _WebViewGamePackState();
}

class _WebViewGamePackState extends State<WebViewGamePack> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'GameBridge',
        onMessageReceived: _handleJsMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _injectInitialState(),
        ),
      )
      ..loadHtmlString(widget.htmlContent);
  }

  void _handleJsMessage(JavaScriptMessage jsMsg) {
    try {
      final envelope = WsMessage.fromJson(
        jsonDecode(jsMsg.message) as Map<String, dynamic>,
      );
      if (envelope.type == WsMessageType.action) {
        final action = ActionMessage.fromEnvelope(envelope);
        widget.onAction?.call(action);
      }
    } catch (_) {
      // Ignore malformed messages from the WebView.
    }
  }

  void _injectInitialState() {
    final state = widget.initialState;
    if (state == null) return;
    final json = jsonEncode(state);
    _controller.runJavaScript(
      'if (typeof window.onStateUpdate === "function") { window.onStateUpdate($json); }',
    );
  }

  /// Called externally to push a new game state into the WebView.
  void updateState(Map<String, dynamic> state) {
    final json = jsonEncode(state);
    _controller.runJavaScript(
      'if (typeof window.onStateUpdate === "function") { window.onStateUpdate($json); }',
    );
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
