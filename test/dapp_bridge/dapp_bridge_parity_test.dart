// Every page-facing method, event and error code of the Syrius extension's
// `window.zenon`, driven against the desktop channel over a real loopback
// WebSocket, with a fake wallet behind it. The table these tests back is in
// docs/webapp-integration.md.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/server/dapp_bridge_block.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/server/dapp_bridge_channel.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/server/dapp_bridge_consent.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/server/dapp_bridge_error.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/server/dapp_bridge_service.dart';

import 'support.dart';

const Map<String, Object?> _send = <String, Object?>{
  'to': kTo,
  'tokenStandard': kZnn,
  'amount': '150000000',
};

void main() {
  late FakeWallet wallet;
  late MemoryStore store;
  late FakeClock clock;
  late DappBridgeChannel channel;
  late Page page;

  setUp(() async {
    wallet = FakeWallet();
    store = MemoryStore();
    clock = FakeClock();
    channel = testChannel(wallet: wallet, store: store, clock: clock);
    await channel.start();
    page = await Page.open(channel.port!);
  });

  tearDown(() async {
    await page.close();
    await channel.close();
  });

  Future<void> connect() async {
    expect(await page.result('znn_connect'), <String>[kA]);
    wallet.prompts.clear();
    page.events.clear();
  }

  /// Locked, and nobody unlocks it in time.
  void lock() => wallet.locked = true;

  /// The wallet locks under the approval on screen, which goes unanswered.
  void lockDismisses() {
    lock();
    wallet
      ..dismiss = true
      ..hold!.complete(false);
  }

  /// Unlocked again, and approvals are answered as before.
  void unlockAgain() {
    wallet
      ..locked = false
      ..dismiss = false
      ..hold = null;
  }

  group('znn_accounts (getAccounts, isConnected)', () {
    test('connected: the selected address', () async {
      await connect();
      expect(await page.result('znn_accounts'), <String>[kA]);
    });

    test('not connected: empty, without a prompt', () async {
      expect(await page.result('znn_accounts'), <String>[]);
      expect(wallet.prompts, isEmpty);
      expect(wallet.raised, 0);
    });

    test('locked: empty, and the wallet is not raised', () async {
      await connect();
      lock();
      expect(await page.result('znn_accounts'), <String>[]);
      expect(wallet.raised, 1, reason: 'only the connect raised it');
    });

    test('never prompts, so there is nothing to decline', () async {
      wallet.approve = false;
      expect(await page.result('znn_accounts'), <String>[]);
      expect(wallet.prompts, isEmpty);
    });

    test('params are ignored, as in the extension', () async {
      await connect();
      expect(await page.result('znn_accounts', <Object?>[1, 'x']), <String>[
        kA,
      ]);
    });

    test('another address than the one connected: empty', () async {
      await connect();
      wallet.selected = kB;
      expect(await page.result('znn_accounts'), <String>[]);
    });
  });

  group('znn_chainId (getChainId)', () {
    test('connected: the chain', () async {
      await connect();
      expect(await page.result('znn_chainId'), 321);
    });

    test('not connected or locked: null', () async {
      expect(await page.result('znn_chainId'), isNull);
      await connect();
      lock();
      expect(await page.result('znn_chainId'), isNull);
    });

    test('never prompts; params are ignored', () async {
      await connect();
      expect(await page.result('znn_chainId', 'junk'), 321);
      expect(wallet.prompts, isEmpty);
    });
  });

  group('znn_nodeUrl (getNodeUrl)', () {
    test('connected: scheme, host and port, nothing private', () async {
      await connect();
      expect(await page.result('znn_nodeUrl'), 'wss://node.example:35998');
    });

    test('an embedded node has no public URL', () async {
      await connect();
      wallet.nodeUrl = 'Embedded Node';
      expect(await page.result('znn_nodeUrl'), isNull);
    });

    test('not connected or locked: null', () async {
      expect(await page.result('znn_nodeUrl'), isNull);
      await connect();
      lock();
      expect(await page.result('znn_nodeUrl'), isNull);
    });

    test('never prompts; params are ignored', () async {
      await connect();
      expect(
        await page.result('znn_nodeUrl', <String, Object?>{'x': 1}),
        'wss://node.example:35998',
      );
      expect(wallet.prompts, isEmpty);
    });
  });

  group('znn_connect (connect)', () {
    test('approved: the address, stored per origin and address', () async {
      // Listening first: the event can reach the page before the reply.
      final Future<List<Object?>> event = page.nextEvent();
      expect(await page.result('znn_connect'), <String>[kA]);
      expect(wallet.prompts, <String>['connect $kSite $kA']);
      expect(channel.sites, <DappBridgeSite>[
        DappBridgeSite(
          requester: kSite,
          addresses: const <String>[kA],
          incarnation: '1:${jsonEncode(<String>[kA])}',
        ),
      ]);
      expect(await event, <Object?>[
        'accountsChanged',
        <String>[kA],
      ]);
    });

    test('already connected: answered at once, no prompt', () async {
      await connect();
      expect(await page.result('znn_connect'), <String>[kA]);
      expect(wallet.prompts, isEmpty);
    });

    test('declined: 4001, nothing stored', () async {
      wallet.approve = false;
      expect(await page.code('znn_connect'), 4001);
      expect(channel.sites, isEmpty);
      expect(await page.result('znn_accounts'), <String>[]);
    });

    test('after a decline the origin waits 30 s, unraised', () async {
      wallet.approve = false;
      expect(await page.code('znn_connect'), 4001);
      expect(wallet.raised, 1);
      expect(await page.code('znn_connect'), -32005);
      expect(wallet.raised, 1, reason: 'a declined page cannot raise it');
      expect(wallet.prompts, hasLength(1));
      clock.advance(kDappBridgeDeclineCooldown);
      wallet.approve = true;
      expect(await page.result('znn_connect'), <String>[kA]);
    });

    test('dismissed by a lock: 4900, nothing stored, no cooldown', () async {
      wallet.hold = Completer<bool>();
      final Future<int> connecting = page.code('znn_connect');
      await settle();
      lockDismisses();
      expect(await connecting, 4900);
      expect(channel.sites, isEmpty);
      unlockAgain();
      expect(await page.result('znn_connect'), <String>[kA]);
      expect(wallet.prompts, hasLength(2));
    });

    test('locked: waits for the unlock, then asks', () async {
      lock();
      wallet.unlock = Completer<void>();
      final Future<Object?> connecting = page.result('znn_connect');
      await settle();
      expect(wallet.prompts, isEmpty);
      wallet
        ..locked = false
        ..unlock!.complete();
      expect(await connecting, <String>[kA]);
      expect(wallet.prompts, hasLength(1));
    });

    test('locked and never unlocked: 4900, nothing stored', () async {
      lock();
      expect(await page.code('znn_connect'), 4900);
      expect(channel.sites, isEmpty);
      expect(wallet.prompts, isEmpty);
    });

    test('params are ignored', () async {
      expect(await page.result('znn_connect', 'anything'), <String>[kA]);
    });

    test('a second approval while one is up: -32005', () async {
      wallet.hold = Completer<bool>();
      final Future<Object?> first = page.result('znn_connect');
      await settle();
      expect(await page.code('znn_connect'), -32005);
      wallet.hold!.complete(true);
      expect(await first, <String>[kA]);
    });

    test('expired: -32006, nothing stored, no cooldown', () async {
      wallet.failWith = const DappBridgeError.expired();
      expect(await page.code('znn_connect'), -32006);
      expect(channel.sites, isEmpty);
      wallet.failWith = null;
      expect(await page.result('znn_connect'), <String>[kA]);
    });

    test('selection changes during approval: 4900, nothing stored', () async {
      wallet.hold = Completer<bool>();
      final Future<int> connecting = page.code('znn_connect');
      await settle();
      expect(wallet.prompts, <String>['connect $kSite $kA']);
      wallet
        ..selected = kB
        ..hold!.complete(true);
      expect(await connecting, 4900);
      expect(channel.sites, isEmpty);
      expect(store.values[kDappBridgeConsentKey], isNull);
      expect(await page.result('znn_accounts'), <String>[]);
      wallet.selected = kA;
      expect(await page.result('znn_accounts'), <String>[]);
    });
  });

  group('znn_disconnect (disconnect)', () {
    test('connected: true, the page sees nothing after', () async {
      await connect();
      // Listening first: the event can reach the page before the reply.
      final Future<List<Object?>> event = page.nextEvent();
      expect(await page.result('znn_disconnect'), isTrue);
      expect(await event, <Object?>['accountsChanged', <String>[]]);
      expect(await page.result('znn_accounts'), <String>[]);
      expect(await page.code('znn_sign', 'hello'), 4100);
      expect(channel.sites, isEmpty);
    });

    test('not connected, or locked: still true', () async {
      expect(await page.result('znn_disconnect'), isTrue);
      await connect();
      lock();
      expect(await page.result('znn_disconnect'), isTrue);
      expect(channel.sites, isEmpty);
    });

    test('never prompts; params are ignored', () async {
      await connect();
      expect(await page.result('znn_disconnect', <int>[1]), isTrue);
      expect(wallet.prompts, isEmpty);
    });

    test(
      'a signature approved after the page disconnected is not made',
      () async {
        await connect();
        wallet.hold = Completer<bool>();
        final Future<int> signing = page.code('znn_sign', 'hello');
        await settle();
        expect(await page.result('znn_disconnect'), isTrue);
        wallet.hold!.complete(true);
        expect(await signing, 4100);
        expect(wallet.signed, isEmpty);
      },
    );

    test('a send approved after the page disconnected is not made', () async {
      await connect();
      wallet.hold = Completer<bool>();
      final Future<int> sending = page.code('znn_sendTransaction', _send);
      await settle();
      expect(await page.result('znn_disconnect'), isTrue);
      wallet.hold!.complete(true);
      expect(await sending, 4100);
      expect(wallet.sent, isEmpty);
    });
  });

  group('znn_sign (signMessage)', () {
    test('approved: message, address, public key and signature', () async {
      await connect();
      expect(
        await page.result('znn_sign', <String, Object?>{'message': 'hello'}),
        <String, Object?>{
          'message': 'hello',
          'address': kA,
          'publicKey': 'pk-$kA',
          'signature': 'sig-1',
        },
      );
      expect(wallet.prompts, <String>['sign $kSite $kA hello']);
    });

    test(
      'a bare string is taken as the message, as in the extension',
      () async {
        await connect();
        final Object? signed = await page.result('znn_sign', 'hello');
        expect((signed! as Map<String, dynamic>)['message'], 'hello');
      },
    );

    test('declined: 4001, nothing signed', () async {
      await connect();
      wallet.approve = false;
      expect(await page.code('znn_sign', 'hello'), 4001);
      expect(wallet.signed, isEmpty);
    });

    test('after a decline the origin waits 30 s', () async {
      await connect();
      wallet.approve = false;
      expect(await page.code('znn_sign', 'hello'), 4001);
      expect(await page.code('znn_sign', 'hello'), -32005);
      expect(wallet.prompts, hasLength(1));
      clock.advance(kDappBridgeDeclineCooldown);
      wallet.approve = true;
      await page.result('znn_sign', 'hello');
      expect(wallet.signed, hasLength(1));
    });

    test('dismissed by a lock: 4900, nothing signed, no cooldown', () async {
      await connect();
      wallet.hold = Completer<bool>();
      final Future<int> signing = page.code('znn_sign', 'hello');
      await settle();
      lockDismisses();
      expect(await signing, 4900);
      expect(wallet.signed, isEmpty);
      // Nobody declined, so the page asks again at once and is asked about.
      unlockAgain();
      await page.result('znn_sign', 'hello');
      expect(wallet.prompts, hasLength(2));
      expect(wallet.signed, hasLength(1));
    });

    test('locked: 4900, nothing signed', () async {
      await connect();
      lock();
      expect(await page.code('znn_sign', 'hello'), 4900);
      expect(wallet.signed, isEmpty);
      expect(wallet.prompts, isEmpty);
    });

    test('locked between the approval and the signature: 4900', () async {
      await connect();
      wallet.hold = Completer<bool>();
      final Future<int> signing = page.code('znn_sign', 'hello');
      await settle();
      lock();
      wallet.hold!.complete(true);
      expect(await signing, 4900);
      expect(wallet.signed, isEmpty);
    });

    test('another address selected while the approval was up: 4900, '
        'even one the origin is connected to', () async {
      await connect();
      wallet.selected = kB;
      expect(await page.result('znn_connect'), <String>[kB]);
      wallet.prompts.clear();
      wallet.hold = Completer<bool>();
      final Future<int> signing = page.code('znn_sign', 'hello');
      await settle();
      expect(wallet.prompts.single, 'sign $kSite $kB hello');
      wallet
        ..selected = kA
        ..hold!.complete(true);
      expect(await signing, 4900);
      expect(wallet.signed, isEmpty);
    });

    test('not connected: 4100, no prompt, wallet not raised', () async {
      expect(await page.code('znn_sign', 'hello'), 4100);
      expect(wallet.prompts, isEmpty);
      expect(wallet.raised, 0);
    });

    test('malformed: -32602 before anything else', () async {
      await connect();
      for (final Object? bad in <Object?>[
        null,
        <String, Object?>{},
        <String, Object?>{'message': 7},
        <String, Object?>{'message': ''},
        '',
        'x' * 32,
        '€' * 10 + 'xx',
        'x' * (kDappBridgeMaxSignMessage + 1),
        <Object?>['hello'],
      ]) {
        expect(await page.code('znn_sign', bad), -32602, reason: '$bad');
      }
      expect(wallet.prompts, isEmpty);
    });

    test('expired: -32006, nothing signed', () async {
      await connect();
      wallet.failWith = const DappBridgeError.expired();
      expect(await page.code('znn_sign', 'hello'), -32006);
      expect(wallet.signed, isEmpty);
    });
  });

  group('znn_sendTransaction (sendTransaction)', () {
    test('approved: the hash and the block', () async {
      await connect();
      final Map<String, dynamic> sent =
          (await page.result('znn_sendTransaction', _send))!
              as Map<String, dynamic>;
      expect(sent['hash'], 'h1');
      expect(sent['block'], isA<Map<String, dynamic>>());
      expect(wallet.sent.single.toAddress.toString(), kTo);
      expect(wallet.sent.single.amount, BigInt.from(150000000));
      expect(wallet.sent.single.tokenStandard.toString(), kZnn);
      expect(wallet.sent.single.data, isEmpty);
    });

    test('declined: 4001, nothing sent', () async {
      await connect();
      wallet.approve = false;
      expect(await page.code('znn_sendTransaction', _send), 4001);
      expect(wallet.sent, isEmpty);
    });

    test('after a decline the origin waits 30 s', () async {
      await connect();
      wallet.approve = false;
      expect(await page.code('znn_sendTransaction', _send), 4001);
      expect(await page.code('znn_sendTransaction', _send), -32005);
      expect(wallet.prompts, hasLength(1));
      clock.advance(kDappBridgeDeclineCooldown);
      wallet.approve = true;
      await page.result('znn_sendTransaction', _send);
      expect(wallet.sent, hasLength(1));
    });

    test('dismissed by a lock: 4900, nothing sent, no cooldown', () async {
      await connect();
      wallet.hold = Completer<bool>();
      final Future<int> sending = page.code('znn_sendTransaction', _send);
      await settle();
      lockDismisses();
      expect(await sending, 4900);
      expect(wallet.sent, isEmpty);
      // Nobody declined, so the page asks again at once and is asked about.
      unlockAgain();
      await page.result('znn_sendTransaction', _send);
      expect(wallet.prompts, hasLength(2));
      expect(wallet.sent, hasLength(1));
    });

    test('locked: 4900, nothing sent', () async {
      await connect();
      lock();
      expect(await page.code('znn_sendTransaction', _send), 4900);
      expect(wallet.sent, isEmpty);
    });

    test('locked between the approval and the send: 4900', () async {
      await connect();
      wallet.hold = Completer<bool>();
      final Future<int> sending = page.code('znn_sendTransaction', _send);
      await settle();
      lock();
      wallet.hold!.complete(true);
      expect(await sending, 4900);
      expect(wallet.sent, isEmpty);
    });

    test('another address selected while the approval was up: 4900, '
        'even one the origin is connected to', () async {
      await connect();
      wallet.selected = kB;
      expect(await page.result('znn_connect'), <String>[kB]);
      wallet.prompts.clear();
      wallet.hold = Completer<bool>();
      final Future<int> sending = page.code('znn_sendTransaction', _send);
      await settle();
      expect(wallet.prompts.single, 'send $kSite $kB $kTo');
      wallet
        ..selected = kA
        ..hold!.complete(true);
      expect(await sending, 4900);
      expect(wallet.sent, isEmpty);
    });

    test('not connected: 4100, no prompt, wallet not raised', () async {
      expect(await page.code('znn_sendTransaction', _send), 4100);
      expect(wallet.prompts, isEmpty);
      expect(wallet.raised, 0);
    });

    test('the amount as a string, a hex string or a whole number, as the '
        'extension takes it', () async {
      await connect();
      for (final (Object amount, BigInt expected) in <(Object, BigInt)>[
        ('150000000', BigInt.from(150000000)),
        ('0x10', BigInt.from(16)),
        (7, BigInt.from(7)),
        (0, BigInt.zero),
        (kDappBridgeMaxSafeInteger, BigInt.from(kDappBridgeMaxSafeInteger)),
        ('1' * 78, BigInt.parse('1' * 78)),
      ]) {
        await page.result('znn_sendTransaction', <String, Object?>{
          ..._send,
          'amount': amount,
        });
        expect(wallet.sent.last.amount, expected, reason: '$amount');
      }
    });

    test('expired: -32006, nothing sent', () async {
      await connect();
      wallet.failWith = const DappBridgeError.expired();
      expect(await page.code('znn_sendTransaction', _send), -32006);
      expect(wallet.sent, isEmpty);
    });

    test('malformed: -32602, no prompt', () async {
      await connect();
      for (final Map<String, Object?> bad in <Map<String, Object?>>[
        <String, Object?>{..._send, 'amount': -1},
        <String, Object?>{..._send, 'amount': 1.5},
        <String, Object?>{..._send, 'amount': kDappBridgeMaxSafeInteger + 1},
        <String, Object?>{..._send, 'amount': null},
        <String, Object?>{..._send, 'amount': true},
        <String, Object?>{..._send, 'amount': '1.5'},
        <String, Object?>{..._send, 'amount': '-1'},
        <String, Object?>{..._send, 'amount': ''},
        <String, Object?>{..._send, 'amount': ' 5'},
        <String, Object?>{..._send, 'amount': '0x'},
        <String, Object?>{..._send, 'amount': '0xzz'},
        <String, Object?>{..._send, 'amount': '1' * 79},
        <String, Object?>{..._send, 'tokenStandard': null},
        <String, Object?>{..._send, 'to': 'z1nope'},
        <String, Object?>{..._send, 'to': null},
        <String, Object?>{..._send, 'tokenStandard': 'zts1nope'},
      ]) {
        expect(
          await page.code('znn_sendTransaction', bad),
          -32602,
          reason: '$bad',
        );
      }
      expect(await page.code('znn_sendTransaction', 'nope'), -32602);
      expect(wallet.prompts, isEmpty);
    });
  });

  group('znn_signAndSendBlock (sendAccountBlock)', () {
    // An account block as the SDK writes one. The fields the wallet fills
    // in itself are there to show they are never used.
    final Map<String, Object?> block = <String, Object?>{
      'version': 1,
      'chainIdentifier': 999,
      'blockType': 2,
      'hash': 'f' * 64,
      'previousHash': '0' * 64,
      'height': 77,
      'address': kB,
      'toAddress': kTo,
      'amount': '5',
      'tokenStandard': kZnn,
      'data': 'AAEC',
      'signature': 'forged',
    };

    test(
      'approved: built from the four fields that say what it does',
      () async {
        await connect();
        final Map<String, dynamic> sent =
            (await page.result('znn_signAndSendBlock', block))!
                as Map<String, dynamic>;
        expect(sent['hash'], 'h1');
        expect(wallet.sent.single.toAddress.toString(), kTo);
        expect(wallet.sent.single.amount, BigInt.from(5));
        expect(wallet.sent.single.data, <int>[0, 1, 2]);
        // Signed from the connected address, not the block's own `address`.
        expect(wallet.prompts.single, 'send $kSite $kA $kTo');
      },
    );

    test('data as base64, as bytes, or as a Buffer', () async {
      await connect();
      for (final Object data in <Object>[
        'AAEC',
        <int>[0, 1, 2],
        <String, Object?>{
          'type': 'Buffer',
          'data': <int>[0, 1, 2],
        },
      ]) {
        await page.result('znn_signAndSendBlock', <String, Object?>{
          ...block,
          'data': data,
        });
        expect(wallet.sent.last.data, <int>[0, 1, 2], reason: '$data');
      }
    });

    test('declined: 4001, nothing sent', () async {
      await connect();
      wallet.approve = false;
      expect(await page.code('znn_signAndSendBlock', block), 4001);
      expect(wallet.sent, isEmpty);
    });

    test('after a decline the origin waits 30 s', () async {
      await connect();
      wallet.approve = false;
      expect(await page.code('znn_signAndSendBlock', block), 4001);
      expect(await page.code('znn_signAndSendBlock', block), -32005);
      expect(wallet.prompts, hasLength(1));
      clock.advance(kDappBridgeDeclineCooldown);
      wallet.approve = true;
      await page.result('znn_signAndSendBlock', block);
      expect(wallet.sent, hasLength(1));
    });

    test('dismissed by a lock: 4900, nothing sent, no cooldown', () async {
      await connect();
      wallet.hold = Completer<bool>();
      final Future<int> sending = page.code('znn_signAndSendBlock', block);
      await settle();
      lockDismisses();
      expect(await sending, 4900);
      expect(wallet.sent, isEmpty);
      // Nobody declined, so the page asks again at once and is asked about.
      unlockAgain();
      await page.result('znn_signAndSendBlock', block);
      expect(wallet.prompts, hasLength(2));
      expect(wallet.sent, hasLength(1));
    });

    test('locked: 4900, nothing sent', () async {
      await connect();
      lock();
      expect(await page.code('znn_signAndSendBlock', block), 4900);
      expect(wallet.sent, isEmpty);
    });

    test('locked between the approval and the send: 4900', () async {
      await connect();
      wallet.hold = Completer<bool>();
      final Future<int> sending = page.code('znn_signAndSendBlock', block);
      await settle();
      lock();
      wallet.hold!.complete(true);
      expect(await sending, 4900);
      expect(wallet.sent, isEmpty);
    });

    test('another address selected while the approval was up: 4900, '
        'even one the origin is connected to', () async {
      await connect();
      wallet.selected = kB;
      expect(await page.result('znn_connect'), <String>[kB]);
      wallet.prompts.clear();
      wallet.hold = Completer<bool>();
      final Future<int> sending = page.code('znn_signAndSendBlock', block);
      await settle();
      expect(wallet.prompts.single, 'send $kSite $kB $kTo');
      wallet
        ..selected = kA
        ..hold!.complete(true);
      expect(await sending, 4900);
      expect(wallet.sent, isEmpty);
    });

    test('not connected: 4100, no prompt, wallet not raised', () async {
      expect(await page.code('znn_signAndSendBlock', block), 4100);
      expect(wallet.prompts, isEmpty);
      expect(wallet.raised, 0);
    });

    test('malformed: -32602, no prompt', () async {
      await connect();
      for (final Object? bad in <Object?>[
        null,
        'nope',
        <Object?>[block],
        <String, Object?>{...block, 'toAddress': null},
        <String, Object?>{...block, 'toAddress': 'z1nope'},
        <String, Object?>{...block, 'amount': '-5'},
        <String, Object?>{...block, 'amount': 5.5},
        <String, Object?>{...block, 'data': '***'},
        <String, Object?>{
          ...block,
          'data': <int>[256],
        },
        <String, Object?>{
          ...block,
          'data': List<int>.filled(17 * 1024, 0),
        },
        <String, Object?>{...block, 'blockType': 3},
      ]) {
        expect(
          await page.code('znn_signAndSendBlock', bad),
          -32602,
          reason: '$bad'.substring(0, 40.clamp(0, '$bad'.length)),
        );
      }
      expect(wallet.prompts, isEmpty);
    });

    test(
      'a receive block (blockType 3) is published',
      () {},
      skip:
          'Gap: desktop publishes send blocks only and refuses blockType 3 '
          'with -32602. The extension builds any block the SDK can; '
          'AccountBlockTemplate.receive would carry it.',
    );
  });

  group('events', () {
    late Page other;

    setUp(() async {
      other = await Page.open(channel.port!, origin: kOther);
      await connect();
      await settle();
      other.events.clear();
    });

    tearDown(() => other.close());

    test('accountsChanged: another address, then back', () async {
      wallet.selected = kB;
      expect(await page.nextEvent(), <Object?>['accountsChanged', <String>[]]);
      wallet.selected = kA;
      expect(await page.nextEvent(), <Object?>[
        'accountsChanged',
        <String>[kA],
      ]);
    });

    test('accountsChanged: lock, then unlock', () async {
      lock();
      expect(await page.nextEvent(), <Object?>['accountsChanged', <String>[]]);
      wallet.locked = false;
      expect(await page.nextEvent(), <Object?>[
        'accountsChanged',
        <String>[kA],
      ]);
    });

    test(
      'chainChanged and nodeChanged, the node without its secrets',
      () async {
        wallet
          ..chainId = 1
          ..nodeUrl = 'wss://u:p@other.node/key';
        await settle();
        expect(page.eventLog, <String>[
          'chainChanged 1',
          'nodeChanged wss://other.node',
        ]);
      },
    );

    test('a page not connected hears nothing about the wallet', () async {
      wallet.selected = kB;
      await settle();
      wallet
        ..selected = kA
        ..chainId = 1
        ..nodeUrl = 'wss://other.node';
      await settle();
      lock();
      await settle();
      expect(other.events, isEmpty);
    });

    test('nothing is sent when nothing changed', () async {
      await settle();
      expect(page.events, isEmpty);
    });
  });

  group('errors', () {
    test(
      '4200: unknown method, including the 2023 postMessage names',
      () async {
        for (final String method in <String>[
          'eth_accounts',
          'znn.requestWalletAccess',
          'znn_getBalance',
          'toString',
          '__proto__',
        ]) {
          expect(await page.code(method), 4200, reason: method);
        }
      },
    );

    test('-32602: not a JSON-RPC request', () async {
      final WebSocket raw = await WebSocket.connect(
        'ws://127.0.0.1:${channel.port}',
        headers: <String, dynamic>{'Origin': kSite},
      );
      final StreamIterator<dynamic> frames = StreamIterator<dynamic>(raw);
      expect(await frames.moveNext(), isTrue, reason: 'the hello');
      for (final String frame in <String>[
        'not json',
        '[1]',
        '{"method":"znn_accounts"}',
        '{"id":{"x":1},"method":"znn_accounts"}',
        '{"id":1e999,"method":"znn_accounts"}',
        '{"id":1,"method":""}',
        '{"id":1,"method":"${'m' * 65}"}',
      ]) {
        raw.add(frame);
        expect(await frames.moveNext(), isTrue);
        final Map<String, dynamic> reply =
            jsonDecode(frames.current as String) as Map<String, dynamic>;
        expect(
          (reply['error'] as Map<String, dynamic>)['code'],
          -32602,
          reason: frame,
        );
      }
      expect(wallet.prompts, isEmpty);
      await raw.close();
    });

    test('-32005: one approval per origin, the rest refused at once', () async {
      await connect();
      wallet.hold = Completer<bool>();
      final Future<Map<String, dynamic>> first = page.call('znn_sign', 'one');
      await settle();
      expect(await page.code('znn_sign', 'two'), -32005);
      expect(await page.code('znn_sendTransaction', _send), -32005);
      wallet.hold!.complete(true);
      expect((await first)['result'], isNotNull);
      expect(wallet.prompts, hasLength(1));
    });

    test('-32603: a failure inside the wallet, with no detail', () async {
      await connect();
      wallet.signFailure = StateError('key file at C:/secret');
      final Map<String, dynamic> reply = await page.call('znn_sign', 'hello');
      expect(reply['error'], <String, dynamic>{
        'code': -32603,
        'message': 'Wallet error',
      });
    });

    test('-32006 and 4900 come through with their codes', () async {
      await connect();
      wallet.failWith = const DappBridgeError.expired();
      expect(await page.code('znn_sendTransaction', _send), -32006);
      wallet.failWith = null;
      lock();
      expect(await page.code('znn_sendTransaction', _send), 4900);
    });
  });
}
