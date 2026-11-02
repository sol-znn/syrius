import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/utils/functions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_file.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/tabs.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

class _Node extends Fake implements Zenon {}

class _Account extends Fake implements WalletAccount {
  final List<int> publicKey = List<int>.filled(32, 1);
  final List<int> signature = <int>[7, 8, 9];
  final Completer<void> keyStarted = Completer<void>();
  final Completer<void> signStarted = Completer<void>();
  Future<List<int>>? keyReply;
  Future<List<int>>? signReply;
  Object? keyFailure;
  StackTrace? keyTrace;
  Object? signFailure;
  StackTrace? signTrace;
  List<int>? signedMessage;
  int keyCalls = 0;
  int signCalls = 0;

  @override
  Future<List<int>> getPublicKey() {
    keyCalls++;
    keyStarted.complete();
    final Object? failure = keyFailure;
    if (failure != null) {
      return Future<List<int>>.error(failure, keyTrace);
    }
    return keyReply ?? Future<List<int>>.value(publicKey);
  }

  @override
  Future<List<int>> sign(List<int> message) {
    signCalls++;
    signedMessage = message;
    signStarted.complete();
    final Object? failure = signFailure;
    if (failure != null) {
      return Future<List<int>>.error(failure, signTrace);
    }
    return signReply ?? Future<List<int>>.value(signature);
  }
}

class _Wallet extends Fake implements Wallet {
  _Wallet(this.account);

  final _Account account;
  final Completer<void> accountStarted = Completer<void>();
  final List<int> indices = <int>[];
  Future<WalletAccount>? accountReply;
  Object? accountFailure;
  StackTrace? accountTrace;

  @override
  Future<WalletAccount> getAccount([int index = 0]) {
    indices.add(index);
    accountStarted.complete();
    final Object? failure = accountFailure;
    if (failure != null) {
      return Future<WalletAccount>.error(failure, accountTrace);
    }
    return accountReply ?? Future<WalletAccount>.value(account);
  }
}

class _File extends WalletFile {
  _File(this.wallet) : super('wallet-sign-fixture');

  final Wallet wallet;
  final Completer<void> openStarted = Completer<void>();
  final Completer<void> closeStarted = Completer<void>();
  Future<Wallet>? openReply;
  Future<void>? closeReply;
  Object? closeFailure;
  StackTrace? closeTrace;
  int opens = 0;
  int closes = 0;

  @override
  String get walletType => 'synthetic';

  @override
  bool get isHardwareWallet => false;

  @override
  bool get isOpen => throw StateError('Fixture mutex must not be inspected.');

  @override
  Future<Wallet> open() {
    opens++;
    openStarted.complete();
    return openReply ?? Future<Wallet>.value(wallet);
  }

  @override
  Future<void> close() {
    closes++;
    closeStarted.complete();
    final Object? failure = closeFailure;
    if (failure != null) return Future<void>.error(failure, closeTrace);
    return closeReply ?? Future<void>.value();
  }
}

class _Outcome {
  _Outcome(Future<Signature> original) {
    unawaited(
      original.then<void>(
        (Signature value) {
          result = value;
          _done.complete();
        },
        onError: (Object failure, StackTrace trace) {
          error = failure;
          stackTrace = trace;
          _done.complete();
        },
      ),
    );
  }

  final Completer<void> _done = Completer<void>();
  Signature? result;
  Object? error;
  StackTrace? stackTrace;

  Future<void> get done => _done.future;
  bool get settled => _done.isCompleted;
}

enum _Boundary { acquisition, account, publicKey, signature, release }

class _Hold {
  _Hold(this.started, this.complete);

  final Future<void> started;
  final void Function() complete;
}

class _Fixture {
  final _Account account = _Account();
  late final _Wallet wallet = _Wallet(account);
  late final _File file = _File(wallet);
  final _File replacement = _File(_Wallet(_Account()));
  late final String owner = Address.fromPublicKey(account.publicKey).toString();
  final String other = Address.fromPublicKey(
    List<int>.filled(32, 2),
  ).toString();

  void install() {
    app.zenon = _Node();
    kWalletFile = file;
    kWalletPath = file.walletPath;
    kDefaultAddressList = <String?>[other, owner];
    kSelectedAddress = owner;
    kWalletInitCompleted = true;
    kCurrentPage = Tabs.dashboard;
    kCurrentNode = 'wallet-sign-node';
    kNodeChainId = 321;
    setChainIdentifier(chainIdentifier: 321);
  }

  _Hold hold(_Boundary boundary) {
    switch (boundary) {
      case _Boundary.acquisition:
        final Completer<Wallet> acquiring = Completer<Wallet>();
        file.openReply = acquiring.future;
        return _Hold(
          file.openStarted.future,
          () => acquiring.complete(wallet),
        );
      case _Boundary.account:
        final Completer<WalletAccount> reading = Completer<WalletAccount>();
        wallet.accountReply = reading.future;
        return _Hold(
          wallet.accountStarted.future,
          () => reading.complete(account),
        );
      case _Boundary.publicKey:
        final Completer<List<int>> keyReading = Completer<List<int>>();
        account.keyReply = keyReading.future;
        return _Hold(
          account.keyStarted.future,
          () => keyReading.complete(account.publicKey),
        );
      case _Boundary.signature:
        final Completer<List<int>> signing = Completer<List<int>>();
        account.signReply = signing.future;
        return _Hold(
          account.signStarted.future,
          () => signing.complete(account.signature),
        );
      case _Boundary.release:
        final Completer<void> releasing = Completer<void>();
        file.closeReply = releasing.future;
        return _Hold(file.closeStarted.future, releasing.complete);
    }
  }
}

class _Globals {
  final Zenon? node = app.zenon;
  final WalletFile? file = kWalletFile;
  final String? path = kWalletPath;
  final String? selected = kSelectedAddress;
  final List<String?> addresses = kDefaultAddressList;
  final bool initialized = kWalletInitCompleted;
  final Tabs? page = kCurrentPage;
  final String? currentNode = kCurrentNode;
  final int? nodeChain = kNodeChainId;
  final int chain = getChainIdentifier();

  void restore() {
    app.zenon = node;
    kWalletFile = file;
    kWalletPath = path;
    kSelectedAddress = selected;
    kDefaultAddressList = addresses;
    kWalletInitCompleted = initialized;
    kCurrentPage = page;
    kCurrentNode = currentNode;
    kNodeChainId = nodeChain;
    setChainIdentifier(chainIdentifier: chain);
    WalletContextRevision.invalidate();
  }
}

void main() {
  group('original wallet signing', () {
    late _Globals globals;
    late _Fixture fixture;

    setUp(() {
      globals = _Globals();
      fixture = _Fixture()..install();
    });
    tearDown(() => globals.restore());

    final Map<String, void Function(_Fixture)> changes =
        <String, void Function(_Fixture)>{
          'selection changes': (_Fixture value) {
            kSelectedAddress = value.other;
          },
          'file is replaced': (_Fixture value) {
            kWalletFile = value.replacement;
          },
          'account list is replaced': (_Fixture _) {
            kDefaultAddressList = List<String?>.of(kDefaultAddressList);
          },
        };
    for (final _Boundary boundary in _Boundary.values) {
      final String boundaryName = boundary.name;
      for (final MapEntry<String, void Function(_Fixture)> change
          in changes.entries) {
        final String changeName = change.key;
        test('$changeName during $boundaryName refuses the result', () async {
          final _Hold hold = fixture.hold(boundary);
          final _Outcome outcome = _Outcome(walletSign(<int>[1, 2, 3]));
          await hold.started;
          expect(outcome.settled, isFalse);
          change.value(fixture);
          hold.complete();
          await outcome.done;
          expect(outcome.error, isA<WalletSignFailure>());
          expect(outcome.result, isNull);
          expect(fixture.file.opens, 1);
          expect(fixture.file.closes, 1);
          expect(fixture.replacement.opens, 0);
          expect(fixture.replacement.closes, 0);
          expect(
            fixture.account.signCalls,
            boundary == _Boundary.signature || boundary == _Boundary.release
                ? 1
                : 0,
          );
        });
      }
    }

    final Map<String, void Function(_Fixture)> invalid =
        <String, void Function(_Fixture)>{
          'missing wallet': (_) {
            kWalletFile = null;
          },
          'missing selection': (_) {
            kSelectedAddress = null;
          },
          'unknown account': (_Fixture value) {
            kDefaultAddressList = <String?>[value.other];
          },
          'ambiguous account': (_Fixture value) {
            kDefaultAddressList = <String?>[value.owner, value.owner];
          },
          'locked wallet': (_) {
            kCurrentPage = Tabs.lock;
          },
        };
    for (final MapEntry<String, void Function(_Fixture)> entry
        in invalid.entries) {
      final String name = entry.key;
      test('$name refuses before acquisition', () async {
        entry.value(fixture);
        final _Outcome outcome = _Outcome(walletSign(<int>[1, 2, 3]));
        await outcome.done;
        expect(outcome.error, isA<WalletSignFailure>());
        expect(fixture.file.opens, 0);
        expect(fixture.file.closes, 0);
        expect(fixture.account.signCalls, 0);
      });
    }

    test('one original account signs immutable captured bytes', () async {
      final _Hold acquiring = fixture.hold(_Boundary.acquisition);
      final Completer<List<int>> signing = Completer<List<int>>();
      fixture.account.signReply = signing.future;
      final List<int> message = <int>[1, 2, 3];
      final _Outcome outcome = _Outcome(walletSign(message));
      await acquiring.started;
      message
        ..[0] = 9
        ..add(4);
      acquiring.complete();
      await fixture.account.signStarted.future;
      expect(fixture.wallet.indices, <int>[1]);
      expect(fixture.account.signedMessage, <int>[1, 2, 3]);
      expect(
        () => fixture.account.signedMessage![0] = 7,
        throwsUnsupportedError,
      );
      fixture.account.publicKey[0] = 3;
      signing.complete(fixture.account.signature);
      await outcome.done;
      expect(outcome.error, isNull);
      expect(outcome.result!.signature, '070809');
      expect(outcome.result!.publicKey, List<String>.filled(32, '01').join());
      expect(fixture.account.keyCalls, 1);
      expect(fixture.account.signCalls, 1);
      expect(fixture.file.closes, 1);
    });

    test('successful signing waits for the original close', () async {
      final _Hold releasing = fixture.hold(_Boundary.release);
      final _Outcome outcome = _Outcome(walletSign(<int>[1, 2, 3]));
      await releasing.started;
      expect(outcome.settled, isFalse);
      expect(fixture.account.signCalls, 1);
      expect(fixture.file.closes, 1);
      releasing.complete();
      await outcome.done;
      expect(outcome.error, isNull);
      expect(outcome.result!.signature, '070809');
      expect(fixture.file.closes, 1);
    });

    test('context loss retains the settled result privately', () async {
      final _Hold signing = fixture.hold(_Boundary.signature);
      final _Hold releasing = fixture.hold(_Boundary.release);
      final String publicKey = BytesUtils.bytesToHex(fixture.account.publicKey);
      final _Outcome outcome = _Outcome(walletSign(<int>[1, 2, 3]));
      await signing.started;
      kSelectedAddress = fixture.other;
      signing.complete();
      await releasing.started;
      expect(outcome.settled, isFalse);
      fixture.account.signature[0] = 6;
      fixture.account.publicKey[0] = 3;
      releasing.complete();
      await outcome.done;
      final WalletSignFailure failure = outcome.error! as WalletSignFailure;
      expect(outcome.result, isNull);
      expect(
        failure.settledResult,
        (publicKey: publicKey, signature: '070809'),
      );
      expect(failure.primaryError, isA<StateError>());
      expect(failure.closeError, isNull);
      expect(failure.toString(), 'Wallet signing failed.');
      expect(failure.toString(), isNot(contains(publicKey)));
      expect(failure.toString(), isNot(contains('070809')));
      expect(fixture.account.signCalls, 1);
      expect(fixture.file.opens, 1);
      expect(fixture.file.closes, 1);
      expect(fixture.replacement.opens, 0);
      expect(fixture.replacement.closes, 0);
    });

    test('a mismatching original public key never signs', () async {
      final String captured = fixture.owner;
      expect(kSelectedAddress, captured);
      fixture.account.publicKey[0] = 3;
      final _Outcome outcome = _Outcome(walletSign(<int>[1, 2, 3]));
      await outcome.done;
      expect(outcome.error, isA<WalletSignFailure>());
      expect(fixture.account.signCalls, 0);
      expect(fixture.file.closes, 1);
    });

    test('in-place account list changes refuse before signing', () async {
      final _Hold reading = fixture.hold(_Boundary.publicKey);
      final _Outcome outcome = _Outcome(walletSign(<int>[1, 2, 3]));
      await reading.started;
      kDefaultAddressList[0] = fixture.owner;
      reading.complete();
      await outcome.done;
      expect(outcome.error, isA<WalletSignFailure>());
      expect(fixture.account.signCalls, 0);
      expect(fixture.file.closes, 1);
    });

    test('a restored selection cannot revive a revoked context', () async {
      final _Hold acquiring = fixture.hold(_Boundary.acquisition);
      final _Outcome outcome = _Outcome(walletSign(<int>[1, 2, 3]));
      await acquiring.started;
      kSelectedAddress = fixture.other;
      WalletContextRevision.invalidate();
      kSelectedAddress = fixture.owner;
      acquiring.complete();
      await outcome.done;
      expect(outcome.error, isA<WalletSignFailure>());
      expect(fixture.wallet.indices, isEmpty);
      expect(fixture.account.signCalls, 0);
      expect(fixture.file.closes, 1);
    });

    test('the existing client authority stays captured', () async {
      final _Hold reading = fixture.hold(_Boundary.publicKey);
      final _Outcome outcome = _Outcome(walletSign(<int>[1, 2, 3]));
      await reading.started;
      app.zenon = _Node();
      reading.complete();
      await outcome.done;
      expect(outcome.error, isA<WalletSignFailure>());
      expect(fixture.account.signCalls, 0);
      expect(fixture.file.closes, 1);
    });

    test('failed acquisition keeps its error without releasing', () async {
      final Completer<Wallet> opening = Completer<Wallet>();
      fixture.file.openReply = opening.future;
      final StateError original = StateError('Synthetic acquisition failed');
      final StackTrace trace = StackTrace.fromString('acquisition fixture');
      final _Outcome outcome = _Outcome(walletSign(<int>[1, 2, 3]));
      await fixture.file.openStarted.future;
      kWalletFile = fixture.replacement;
      opening.completeError(original, trace);
      await outcome.done;
      final WalletSignFailure failure = outcome.error! as WalletSignFailure;
      expect(failure.primaryError, same(original));
      expect(failure.primaryStackTrace.toString(), trace.toString());
      expect(failure.closeError, isNull);
      expect(fixture.file.closes, 0);
      expect(fixture.replacement.closes, 0);
      expect(fixture.wallet.indices, isEmpty);
    });

    for (final _Boundary boundary in <_Boundary>[
      _Boundary.account,
      _Boundary.publicKey,
      _Boundary.signature,
    ]) {
      final String name = boundary.name;
      test('$name error precedes the original close error', () async {
        final StateError primary = StateError('Synthetic operation failed');
        final StackTrace primaryTrace = StackTrace.fromString(
          'primary fixture',
        );
        final StateError closing = StateError('Synthetic release failed');
        final StackTrace closeTrace = StackTrace.fromString(
          'release fixture',
        );
        fixture.file
          ..closeFailure = closing
          ..closeTrace = closeTrace;
        switch (boundary) {
          case _Boundary.account:
            fixture.wallet
              ..accountFailure = primary
              ..accountTrace = primaryTrace;
          case _Boundary.publicKey:
            fixture.account
              ..keyFailure = primary
              ..keyTrace = primaryTrace;
          case _Boundary.signature:
            fixture.account
              ..signFailure = primary
              ..signTrace = primaryTrace;
          case _Boundary.acquisition:
          case _Boundary.release:
            fail('This fixture only fails an acquired operation.');
        }
        final _Outcome outcome = _Outcome(walletSign(<int>[1, 2, 3]));
        await outcome.done;
        final WalletSignFailure failure = outcome.error! as WalletSignFailure;
        expect(failure.primaryError, same(primary));
        expect(failure.primaryStackTrace.toString(), primaryTrace.toString());
        expect(failure.closeError, same(closing));
        expect(failure.closeStackTrace.toString(), closeTrace.toString());
        expect(outcome.stackTrace.toString(), primaryTrace.toString());
        expect(failure.toString(), 'Wallet signing failed.');
        expect(fixture.file.closes, 1);
        expect(
          fixture.account.signCalls,
          boundary == _Boundary.signature ? 1 : 0,
        );
      });
    }

    test('a primary error waits for delayed failing release', () async {
      final Completer<void> releasing = Completer<void>();
      fixture.file.closeReply = releasing.future;
      final UnsupportedError primary = UnsupportedError(
        'Synthetic unsupported',
      );
      final StackTrace primaryTrace = StackTrace.fromString('sign fixture');
      fixture.account
        ..signFailure = primary
        ..signTrace = primaryTrace;
      final _Outcome outcome = _Outcome(walletSign(<int>[1, 2, 3]));
      await fixture.file.closeStarted.future;
      expect(outcome.settled, isFalse);
      final StateError closing = StateError('Synthetic release failed');
      final StackTrace closeTrace = StackTrace.fromString('close fixture');
      releasing.completeError(closing, closeTrace);
      await outcome.done;
      final WalletSignFailure failure = outcome.error! as WalletSignFailure;
      expect(failure.primaryError, same(primary));
      expect(failure.closeError, same(closing));
      expect(failure.closeStackTrace.toString(), closeTrace.toString());
      expect(fixture.account.signCalls, 1);
      expect(fixture.file.closes, 1);
    });

    test('close failure retains the settled result privately', () async {
      final StateError closing = StateError('Synthetic release failed');
      final StackTrace trace = StackTrace.fromString('release fixture');
      fixture.file
        ..closeFailure = closing
        ..closeTrace = trace;
      final _Outcome outcome = _Outcome(walletSign(<int>[1, 2, 3]));
      await outcome.done;
      final WalletSignFailure failure = outcome.error! as WalletSignFailure;
      expect(outcome.result, isNull);
      expect(failure.primaryError, same(closing));
      expect(failure.primaryStackTrace.toString(), trace.toString());
      expect(failure.closeError, same(closing));
      expect(failure.closeStackTrace.toString(), trace.toString());
      expect(
        failure.settledResult,
        (
          publicKey: List<String>.filled(32, '01').join(),
          signature: '070809',
        ),
      );
      expect(failure.toString(), 'Wallet signing failed.');
      expect(failure.toString(), isNot(contains('070809')));
      expect(fixture.account.signCalls, 1);
      expect(fixture.file.opens, 1);
      expect(fixture.file.closes, 1);
    });

    test('sign failure survives successful release privately', () async {
      final StateError primary = StateError('Synthetic operation failed');
      final StackTrace trace = StackTrace.fromString('operation fixture');
      fixture.account
        ..signFailure = primary
        ..signTrace = trace;
      final _Outcome outcome = _Outcome(walletSign(<int>[1, 2, 3]));
      await outcome.done;
      final WalletSignFailure failure = outcome.error! as WalletSignFailure;
      expect(failure.primaryError, same(primary));
      expect(failure.primaryStackTrace.toString(), trace.toString());
      expect(failure.closeError, isNull);
      expect(failure.toString(), 'Wallet signing failed.');
      expect(failure.toString(), isNot(contains('Synthetic')));
      expect(fixture.account.signCalls, 1);
      expect(fixture.file.closes, 1);
    });
  });
}
