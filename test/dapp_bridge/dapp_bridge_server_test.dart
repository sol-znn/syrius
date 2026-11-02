import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/server/dapp_bridge_error.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/server/dapp_bridge_server.dart';

const String _origin = 'https://bridge.zenon.foo';

// An upgrade and its binary greeting can share one TCP chunk. Decode only
// the HTTP head, even when the delimiter itself crosses chunk boundaries.
Future<String> _responseHead(Stream<List<int>> source) async {
  final List<int> head = <int>[];
  await for (final List<int> chunk in source) {
    for (final int byte in chunk) {
      head.add(byte);
      if (head.length > 4096) {
        throw StateError('HTTP response head exceeds the test limit');
      }
      final int n = head.length;
      if (n >= 4 &&
          head[n - 4] == 13 &&
          head[n - 3] == 10 &&
          head[n - 2] == 13 &&
          head[n - 1] == 10) {
        return ascii.decode(head);
      }
    }
  }
  throw StateError('Incomplete HTTP response head');
}

void main() {
  late DappBridgeServer server;
  late int port;
  final List<List<Object?>> calls = <List<Object?>>[];
  Completer<void>? gate;

  setUp(() async {
    calls.clear();
    gate = null;
    server = DappBridgeServer(
      // Port 0: the OS picks, so the suite never meets a running wallet.
      ports: const <int>[0],
      hello: () => <String, Object?>{'wallet': 'test'},
      handler: (String origin, String method, Object? params) async {
        calls.add(<Object?>[origin, method, params]);
        switch (method) {
          case 'echo':
            return params;
          case 'decline':
            throw const DappBridgeError.declined();
          case 'crash':
            throw StateError('secret detail');
          case 'slow':
            await gate!.future;
            return 'done';
          default:
            throw const DappBridgeError.unknownMethod();
        }
      },
    );
    port = (await server.start())!;
  });

  tearDown(() => server.stop());

  Future<WebSocket> connect({String? origin = _origin, String? host}) {
    return WebSocket.connect(
      'ws://127.0.0.1:$port',
      headers: <String, dynamic>{'Origin': ?origin, 'Host': ?host},
    );
  }

  Future<(WebSocket, StreamIterator<dynamic>)> open() async {
    final WebSocket socket = await connect();
    final StreamIterator<dynamic> frames = StreamIterator<dynamic>(socket);
    await frames.moveNext();
    return (socket, frames);
  }

  Future<Map<String, dynamic>> next(StreamIterator<dynamic> frames) async {
    expect(await frames.moveNext(), isTrue);
    return jsonDecode(frames.current as String) as Map<String, dynamic>;
  }

  int code(Map<String, dynamic> reply) =>
      (reply['error'] as Map<String, dynamic>)['code'] as int;

  test('greets, then answers a request with its origin', () async {
    final WebSocket socket = await connect();
    final StreamIterator<dynamic> frames = StreamIterator<dynamic>(socket);
    expect(await next(frames), <String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'syrius_hello',
      'params': <String, dynamic>{'wallet': 'test'},
    });
    socket.add('{"jsonrpc":"2.0","id":7,"method":"echo","params":{"a":1}}');
    expect(await next(frames), <String, dynamic>{
      'jsonrpc': '2.0',
      'id': 7,
      'result': <String, dynamic>{'a': 1},
    });
    expect(calls.single, <Object?>[
      _origin,
      'echo',
      <String, dynamic>{'a': 1},
    ]);
    await socket.close();
  });

  test('refuses an upgrade without a usable origin', () async {
    for (final String? origin in <String?>[
      null,
      'http://example.com',
      'file://',
      'null',
    ]) {
      await expectLater(
        connect(origin: origin),
        throwsA(isA<WebSocketException>()),
        reason: '$origin',
      );
    }
    expect(server.origins, isEmpty);
  });

  test('refuses a host header that is not loopback', () async {
    await expectLater(
      connect(host: 'rebind.example:$port'),
      throwsA(isA<WebSocketException>()),
    );
  });

  test('refuses a plain http request', () async {
    final HttpClient client = HttpClient();
    final HttpClientRequest request = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port/'),
    );
    request.headers.set('Origin', _origin);
    final HttpClientResponse response = await request.close();
    expect(response.statusCode, HttpStatus.forbidden);
    await response.drain<void>();
    client.close();
  });

  test('maps refusals and hides what failed inside', () async {
    final (WebSocket socket, StreamIterator<dynamic> frames) = await open();
    socket.add('{"id":"a","method":"decline"}');
    expect((await next(frames))['error'], <String, dynamic>{
      'code': 4001,
      'message': 'Declined in wallet',
    });
    socket.add('{"id":"b","method":"nope"}');
    expect(code(await next(frames)), 4200);
    socket.add('{"id":"c","method":"crash"}');
    final Map<String, dynamic> crashed = await next(frames);
    expect(crashed['id'], 'c');
    expect(crashed['error'], <String, dynamic>{
      'code': -32603,
      'message': 'Wallet error',
    });
    await socket.close();
  });

  test('answers malformed input without calling the handler', () async {
    final (WebSocket socket, StreamIterator<dynamic> frames) = await open();
    socket.add('not json');
    expect(code(await next(frames)), -32602);
    socket.add('[1,2]');
    expect(code(await next(frames)), -32602);
    socket.add('{"method":"echo"}');
    expect(code(await next(frames)), -32602);
    socket.add('{"id":{"x":1},"method":"echo"}');
    final Map<String, dynamic> reply = await next(frames);
    expect(reply['id'], isNull);
    expect(calls, isEmpty);
    await socket.close();
  });

  test('closes on an oversized message', () async {
    final (WebSocket socket, StreamIterator<dynamic> frames) = await open();
    final String big = 'x' * kDappBridgeMaxMessage;
    socket.add('{"id":1,"method":"echo","params":"$big"}');
    expect(await frames.moveNext(), isFalse);
    expect(socket.closeCode, WebSocketStatus.messageTooBig);
    expect(calls, isEmpty);
  });

  test('caps sockets per origin', () async {
    final List<WebSocket> sockets = <WebSocket>[
      for (int i = 0; i < kDappBridgeMaxPerOrigin; i++) await connect(),
    ];
    await expectLater(connect(), throwsA(isA<WebSocketException>()));
    final WebSocket other = await connect(origin: 'https://other.example');
    // The greeting is sent once the server has the socket on its books.
    final StreamIterator<dynamic> otherFrames = StreamIterator<dynamic>(other);
    await otherFrames.moveNext();
    expect(server.origins, <String>{_origin, 'https://other.example'});
    for (final WebSocket socket in <WebSocket>[...sockets, other]) {
      await socket.close();
    }
  });

  test('caps requests in flight on one socket', () async {
    gate = Completer<void>();
    final (WebSocket socket, StreamIterator<dynamic> frames) = await open();
    for (int i = 0; i < kDappBridgeMaxInFlight; i++) {
      socket.add('{"id":$i,"method":"slow"}');
    }
    socket.add('{"id":99,"method":"slow"}');
    final Map<String, dynamic> refused = await next(frames);
    expect(refused['id'], 99);
    expect(code(refused), -32005);
    gate!.complete();
    for (int i = 0; i < kDappBridgeMaxInFlight; i++) {
      expect((await next(frames))['result'], 'done');
    }
    await socket.close();
  });

  test('listens on loopback only', () async {
    expect(server.address!.isLoopback, isTrue);
    expect(server.address!.type, InternetAddressType.IPv4);
    // Every other address this machine has is refused at the TCP level.
    final List<NetworkInterface> interfaces = await NetworkInterface.list();
    final List<InternetAddress> others = <InternetAddress>[
      for (final NetworkInterface i in interfaces)
        for (final InternetAddress a in i.addresses)
          if (!a.isLoopback && a.type == InternetAddressType.IPv4) a,
    ];
    for (final InternetAddress other in others) {
      await expectLater(
        Socket.connect(other, port, timeout: const Duration(seconds: 2)),
        throwsA(isA<SocketException>()),
        reason: '$other',
      );
    }
  });

  test('a refusal carries no body and no CORS header', () async {
    final HttpClient client = HttpClient();
    final HttpClientRequest request = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port/'),
    );
    // What a sandboxed frame or a file:// page sends.
    request.headers
      ..set('Origin', 'null')
      ..set('Connection', 'Upgrade')
      ..set('Upgrade', 'websocket');
    final HttpClientResponse response = await request.close();
    expect(response.statusCode, HttpStatus.forbidden);
    expect(response.headers.value('access-control-allow-origin'), isNull);
    expect(
      await response.fold<int>(0, (int n, List<int> b) => n + b.length),
      0,
    );
    client.close();
    expect(calls, isEmpty);
  });

  test('refuses an Origin header sent twice, and keeps serving', () async {
    final Socket raw = await Socket.connect('127.0.0.1', port);
    raw.write(
      'GET / HTTP/1.1\r\n'
      'Host: 127.0.0.1:$port\r\n'
      'Origin: https://evil.example\r\n'
      'Origin: $_origin\r\n'
      'Connection: Upgrade\r\n'
      'Upgrade: websocket\r\n'
      'Sec-WebSocket-Version: 13\r\n'
      'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n'
      '\r\n',
    );
    final String head = await _responseHead(raw);
    expect(head, startsWith('HTTP/1.1 403'));
    await raw.close();
    final (WebSocket socket, _) = await open();
    expect(server.origins, <String>{_origin});
    await socket.close();
  });

  test(
    'refuses a method name past 64 characters, and an infinite id',
    () async {
      final (WebSocket socket, StreamIterator<dynamic> frames) = await open();
      socket.add('{"id":1,"method":"${'e' * 65}"}');
      expect(code(await next(frames)), -32602);
      socket.add('{"id":1e999,"method":"echo"}');
      final Map<String, dynamic> reply = await next(frames);
      expect(reply['id'], isNull);
      expect(code(reply), -32602);
      expect(calls, isEmpty);
      await socket.close();
    },
  );

  test('tells the owner when a page opens a socket', () async {
    final List<String> opened = <String>[];
    final DappBridgeServer watched = DappBridgeServer(
      ports: const <int>[0],
      handler: (_, _, _) async => null,
      onOpen: opened.add,
    );
    final int watchedPort = (await watched.start())!;
    final WebSocket socket = await WebSocket.connect(
      'ws://127.0.0.1:$watchedPort',
      headers: <String, dynamic>{'Origin': _origin},
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(opened, <String>[_origin]);
    await socket.close();
    await watched.stop();
  });

  test('accepts no compression, whatever the page offers', () async {
    final Socket raw = await Socket.connect('127.0.0.1', port);
    addTearDown(raw.destroy);
    raw.write(
      'GET / HTTP/1.1\r\n'
      'Host: 127.0.0.1:$port\r\n'
      'Origin: $_origin\r\n'
      'Connection: Upgrade\r\n'
      'Upgrade: websocket\r\n'
      'Sec-WebSocket-Version: 13\r\n'
      'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n'
      'Sec-WebSocket-Extensions: permessage-deflate; client_max_window_bits\r\n'
      '\r\n',
    );
    final String head = (await _responseHead(raw)).toLowerCase();
    expect(head, startsWith('http/1.1 101'));
    expect(head, isNot(contains('sec-websocket-extensions')));
    raw.destroy();
  });

  test(
    'reads fragmented upgrade heads without decoding binary frames',
    () async {
      const String head =
          'HTTP/1.1 101 Switching Protocols\r\n'
          'Upgrade: websocket\r\n\r\n';
      final List<int> bytes = <int>[
        ...ascii.encode(head),
        0x81,
        0x02,
        0xC3,
        0xFF,
      ];
      for (final int size in <int>[1, 2, 7, bytes.length]) {
        final List<List<int>> chunks = <List<int>>[
          for (int offset = 0; offset < bytes.length; offset += size)
            bytes.sublist(offset, (offset + size).clamp(0, bytes.length)),
        ];
        expect(
          await _responseHead(Stream<List<int>>.fromIterable(chunks)),
          head,
        );
      }
    },
  );

  test('refuses a truncated response head in the test reader', () async {
    await expectLater(
      _responseHead(Stream<List<int>>.value(ascii.encode('HTTP/1.1 101\r\n'))),
      throwsStateError,
    );
  });

  test('caps response head bytes in the test reader', () async {
    await expectLater(
      _responseHead(Stream<List<int>>.value(List<int>.filled(4097, 65))),
      throwsStateError,
    );
  });

  test('emits to one origin or to all', () async {
    final (WebSocket a, StreamIterator<dynamic> aFrames) = await open();
    final WebSocket b = await connect(origin: 'https://other.example');
    final StreamIterator<dynamic> bFrames = StreamIterator<dynamic>(b);
    await bFrames.moveNext();

    server
      ..emit('accountsChanged', <String>['z1'], origin: _origin)
      ..emit('chainChanged', 321);
    expect((await next(aFrames))['method'], 'accountsChanged');
    expect((await next(aFrames))['method'], 'chainChanged');
    expect((await next(bFrames))['method'], 'chainChanged');
    await a.close();
    await b.close();
  });
}
