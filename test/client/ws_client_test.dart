import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';

import '../../lib/client/shared/ws_client.dart';
import '../../lib/server/poc_server.dart';
import '../../lib/shared/messages/ws_message.dart';
import '../../lib/shared/messages/join_message.dart';

void main() {
  group('WsClient', () {
    late PocServer server;

    setUp(() async {
      server = PocServer();
      await server.start(host: 'localhost', port: 0);
    });

    tearDown(() async {
      await server.stop();
    });

    test('connects to server and reports connected state', () async {
      final client = WsClient(
        uri: Uri.parse('ws://localhost:${server.port}/ws'),
      );
      await client.connect();

      expect(client.isConnected, isTrue);

      await client.disconnect();
    });

    test('sends and receives messages', () async {
      final client = WsClient(
        uri: Uri.parse('ws://localhost:${server.port}/ws'),
      );
      await client.connect();

      final future = client.messages.first.timeout(const Duration(seconds: 5));
      client.sendRaw('ping');
      final response = await future;

      expect(response, equals('echo: ping'));

      await client.disconnect();
    });

    test('isConnected is false after disconnect', () async {
      final client = WsClient(
        uri: Uri.parse('ws://localhost:${server.port}/ws'),
      );
      await client.connect();
      await client.disconnect();

      expect(client.isConnected, isFalse);
    });

    test('onStateChange fires on connect and disconnect', () async {
      final states = <bool>[];
      final client = WsClient(
        uri: Uri.parse('ws://localhost:${server.port}/ws'),
        onConnectionStateChange: states.add,
      );

      await client.connect();
      await client.disconnect();

      expect(states, containsAllInOrder([true, false]));
    });
  });

  group('WsClient typed message helpers', () {
    late PocServer server;
    late WsClient client;

    setUp(() async {
      server = PocServer();
      await server.start(host: 'localhost', port: 0);
      client = WsClient(
        uri: Uri.parse('ws://localhost:${server.port}/ws'),
      );
      await client.connect();
    });

    tearDown(() async {
      await client.disconnect();
      await server.stop();
    });

    test('sendMessage encodes WsMessage as JSON', () async {
      // The PoC server just echoes raw strings; we verify the sent JSON is
      // well-formed by parsing the echo back.
      final msg = JoinMessage.join(
        playerId: 'p1',
        displayName: 'Alice',
      ).toEnvelope();

      final echoFuture = client.messages.first.timeout(const Duration(seconds: 5));
      client.sendMessage(msg);
      final echo = await echoFuture;

      // PocServer echoes as "echo: <raw>", so strip the prefix.
      final rawJson = (echo as String).replaceFirst('echo: ', '');
      final decoded = WsMessage.fromJson(
        jsonDecode(rawJson) as Map<String, dynamic>,
      );
      expect(decoded.type, equals(WsMessageType.join));
    });
  });
}
