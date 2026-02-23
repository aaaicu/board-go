import 'dart:async';

import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../lib/server/poc_server.dart';

void main() {
  group('PoC WebSocket Server', () {
    late PocServer server;

    setUp(() async {
      server = PocServer();
      await server.start(host: 'localhost', port: 0);
    });

    tearDown(() async {
      await server.stop();
    });

    test('server starts and reports its port', () {
      expect(server.port, isNotNull);
      expect(server.port, greaterThan(0));
    });

    test('client can connect and receive echo response', () async {
      final uri = Uri.parse('ws://localhost:${server.port}/ws');
      final channel = WebSocketChannel.connect(uri);
      await channel.ready;

      const message = 'hello-board-go';
      channel.sink.add(message);

      final response = await channel.stream.first.timeout(
        const Duration(seconds: 5),
      );

      expect(response, equals('echo: $message'));
      await channel.sink.close();
    });

    test('multiple clients can connect simultaneously', () async {
      final uri = Uri.parse('ws://localhost:${server.port}/ws');

      final ch1 = WebSocketChannel.connect(uri);
      final ch2 = WebSocketChannel.connect(uri);
      await Future.wait([ch1.ready, ch2.ready]);

      ch1.sink.add('from-client-1');
      ch2.sink.add('from-client-2');

      final resp1 = await ch1.stream.first.timeout(const Duration(seconds: 5));
      final resp2 = await ch2.stream.first.timeout(const Duration(seconds: 5));

      expect(resp1, equals('echo: from-client-1'));
      expect(resp2, equals('echo: from-client-2'));

      await Future.wait([ch1.sink.close(), ch2.sink.close()]);
    });

    test('server handles client disconnect gracefully', () async {
      final uri = Uri.parse('ws://localhost:${server.port}/ws');
      final channel = WebSocketChannel.connect(uri);
      await channel.ready;

      // Close immediately without sending any message
      await channel.sink.close();

      // Server should still be running and accept new connections
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final channel2 = WebSocketChannel.connect(uri);
      await channel2.ready;
      channel2.sink.add('still-works');

      final response = await channel2.stream.first.timeout(
        const Duration(seconds: 5),
      );
      expect(response, equals('echo: still-works'));
      await channel2.sink.close();
    });
  });

  group('IsolateRunner', () {
    test('spawns server isolate and receives started status', () async {
      final handle = await IsolateRunner.start(port: 0);

      try {
        expect(handle.port, greaterThan(0));
        expect(handle.isRunning, isTrue);
      } finally {
        await handle.stop();
      }
    });

    test('isolate server responds to WebSocket connections', () async {
      final handle = await IsolateRunner.start(port: 0);

      try {
        final uri = Uri.parse('ws://localhost:${handle.port}/ws');
        final channel = WebSocketChannel.connect(uri);
        await channel.ready;

        channel.sink.add('isolate-echo-test');
        final response = await channel.stream.first.timeout(
          const Duration(seconds: 5),
        );

        expect(response, equals('echo: isolate-echo-test'));
        await channel.sink.close();
      } finally {
        await handle.stop();
      }
    });
  });
}
