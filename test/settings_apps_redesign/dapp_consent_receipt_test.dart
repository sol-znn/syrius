import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/server/dapp_bridge_consent.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/server/dapp_bridge_error.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/server/dapp_bridge_service.dart';

import '../dapp_bridge/support.dart' show FakeWallet, kA;

class _Write {
  _Write(this.key, this.value);
  final String key;
  final Object? value;
  final Completer<void> reply = Completer<void>();
}

class _Box {
  final Map<String, Object?> entries = <String, Object?>{};
  final List<_Write> writes = <_Write>[];
  bool deferred = false;
  Future<void> put(String key, Object? value) {
    final _Write write = _Write(key, value);
    writes.add(write);
    if (!deferred) finish(write);
    return write.reply.future;
  }

  void finish(_Write write) {
    entries[write.key] = write.value;
    write.reply.complete();
  }
}

class _Owner implements DappBridgeCapturedStore {
  _Box box = _Box();
  int revision = 0;
  @override
  Object get identity => box;
  @override
  bool get isCurrent => true;
  @override
  Object? read(String key) => box.entries[key];
  @override
  Future<void> write(String key, Object? value) => capture().write(key, value);
  @override
  DappBridgeStore capture() => _Captured(this, box, revision);
}

class _Captured implements DappBridgeCapturedStore {
  _Captured(this.owner, this.box, this.revision);
  final _Owner owner;
  final _Box box;
  final int revision;
  bool revoked = false;
  @override
  Object get identity => box;
  @override
  bool get isCurrent =>
      !revoked &&
      !(revoked = !identical(box, owner.box) || revision != owner.revision);
  @override
  DappBridgeStore capture() => this;
  @override
  Object? read(String key) => box.entries[key];
  @override
  Future<void> write(String key, Object? value) {
    if (!isCurrent) throw StateError('Original box unavailable');
    return box.put(key, value);
  }
}

Future<void> _turns() async {
  for (int turn = 0; turn < 8; turn++) {
    await Future<void>.value();
  }
}

void main() {
  late _Owner owner;
  late DappBridgeConsentStore consent;
  setUp(() {
    owner = _Owner();
    consent = DappBridgeConsentStore(owner);
  });
  tearDown(() => consent.close());

  test('a retained row cannot revoke a new same-requester grant', () async {
    await consent.grant('https://example.invalid', 'fixture-account');
    final DappBridgeSite original = consent.sites.single;
    final DappBridgeConsentReceipt receipt = consent.captureSite(original);
    await consent.revoke(original.requester);
    await consent.grant(original.requester, 'fixture-account');
    expect(consent.sites.single.addresses, original.addresses);
    expect(consent.sites.single.incarnation, isNot(original.incarnation));
    expect(receipt.isCurrent, isFalse);
    await expectLater(receipt.revoke(), throwsStateError);
    expect(() => consent.captureSite(original), throwsStateError);
    expect(consent.has(original.requester, 'fixture-account'), isTrue);
  });

  test(
    'a revoke tombstone refuses an approval captured before any grant',
    () async {
      final DappBridgeConsentReceipt proposal = consent.captureConsent(
        'https://example.invalid',
      );
      await consent.revoke('https://example.invalid');
      expect(consent.sites, isEmpty);
      expect(proposal.isCurrent, isFalse);
      await expectLater(proposal.grant('fixture-account'), throwsStateError);
      expect(consent.sites, isEmpty);
    },
  );

  test('a queued action never writes to a replacement box', () async {
    final _Box original = owner.box..deferred = true;
    final Future<void> first = consent.grant(
      'https://first.invalid',
      'first-account',
    );
    final Future<void> queued = consent.grant(
      'https://second.invalid',
      'second-account',
    );
    final Future<void> refused = expectLater(queued, throwsStateError);
    await _turns();
    expect(original.writes, hasLength(1));
    owner.box = _Box();
    original.finish(original.writes.single);
    await first;
    await refused;
    expect(original.writes, hasLength(1));
    expect(owner.box.writes, isEmpty);
    expect(owner.box.entries, isEmpty);
    expect(original.entries, contains(kDappBridgeConsentKey));
    expect(consent.sites, isEmpty);
  });

  test(
    'queued withdrawal checks original view authority before its write',
    () async {
      await consent.grant('https://example.invalid', 'fixture-account');
      final DappBridgeConsentReceipt receipt = consent.captureSite(
        consent.sites.single,
      );
      bool visible = true;
      final Future<void> pending = receipt.revoke(isCurrent: () => visible);
      final Future<void> refused = expectLater(pending, throwsStateError);
      visible = false;
      await refused;
      expect(consent.sites, hasLength(1));
      expect(owner.box.writes, hasLength(1));
    },
  );

  test(
    'legacy grants survive an explicit mutation of another requester',
    () async {
      owner.box.entries[kDappBridgeConsentKey] = jsonEncode(<String, Object>{
        'https://first.invalid': <String>['first-account'],
        'https://second.invalid': <String>['second-account'],
      });
      await consent.grant('https://third.invalid', 'third-account');
      expect(consent.has('https://first.invalid', 'first-account'), isTrue);
      expect(consent.has('https://second.invalid', 'second-account'), isTrue);
      expect(consent.has('https://third.invalid', 'third-account'), isTrue);
      expect(consent.sites, hasLength(3));
    },
  );

  test(
    'the identical original write failure is observable by its caller',
    () async {
      owner.box.deferred = true;
      final Object error = StateError('fixture write refused');
      final Future<void> pending = consent.grant(
        'https://example.invalid',
        'fixture-account',
      );
      final Future<void> observed = expectLater(pending, throwsA(same(error)));
      await _turns();
      owner.box.writes.single.reply.completeError(error, StackTrace.current);
      await observed;
      expect(consent.sites, isEmpty);
    },
  );

  test(
    'an original result cannot emit into a newer requester incarnation',
    () async {
      await consent.grant('https://example.invalid', 'fixture-account');
      final DappBridgeConsentReceipt original = consent.captureSite(
        consent.sites.single,
      );
      await original.revoke();
      expect(original.outcomeIsCurrent, isTrue);
      await consent.grant('https://example.invalid', 'fixture-account');
      expect(original.outcomeIsCurrent, isFalse);
    },
  );

  test(
    'a sign approval cannot inherit a revoked and regranted incarnation',
    () async {
      const String origin = 'https://example.invalid';
      await consent.grant(origin, kA);
      final FakeWallet wallet = FakeWallet()..hold = Completer<bool>();
      final DappBridgeService service = DappBridgeService(
        wallet: wallet,
        consent: consent,
      );
      final Future<Object?> pending = service.handle(
        origin,
        'znn_sign',
        'Fixture message',
      );
      final Future<void> refused = expectLater(
        pending,
        throwsA(
          isA<DappBridgeError>().having(
            (DappBridgeError error) => error.code,
            'code',
            4100,
          ),
        ),
      );
      await _turns();
      expect(wallet.prompts, hasLength(1));
      await consent.revoke(origin);
      await consent.grant(origin, kA);
      wallet.hold!.complete(true);
      await refused;
      expect(wallet.signed, isEmpty);
      expect(consent.has(origin, kA), isTrue);
    },
  );

  test(
    'disconnect during a pending connect cannot be overwritten by its '
    'old approval',
    () async {
      const String origin = 'https://example.invalid';
      final FakeWallet wallet = FakeWallet()..hold = Completer<bool>();
      final DappBridgeService service = DappBridgeService(
        wallet: wallet,
        consent: consent,
      );
      final Future<Object?> pending = service.handle(
        origin,
        'znn_connect',
        null,
      );
      final Future<void> refused = expectLater(
        pending,
        throwsA(
          isA<DappBridgeError>().having(
            (DappBridgeError error) => error.code,
            'code',
            4900,
          ),
        ),
      );
      await _turns();
      expect(wallet.prompts, hasLength(1));
      await consent.revoke(origin);
      wallet.hold!.complete(true);
      await refused;
      expect(consent.sites, isEmpty);
    },
  );
}
