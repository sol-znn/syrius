import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_file.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

class _Wallet extends Fake implements Wallet {}

class _File extends WalletFile {
  _File() : super('synthetic-wallet.enc');

  final Wallet wallet = _Wallet();
  final Completer<void> releasing = Completer<void>();
  final Completer<void> released = Completer<void>();
  StateError? openError;
  int closes = 0;

  @override
  String get walletType => 'synthetic';

  @override
  bool get isHardwareWallet => false;

  @override
  bool get isOpen => closes == 0;

  @override
  Future<Wallet> open() async {
    final StateError? error = openError;
    if (error != null) throw error;
    return wallet;
  }

  @override
  Future<void> close() {
    closes++;
    releasing.complete();
    return released.future;
  }
}

void main() {
  test('access cannot settle before its original release completes', () async {
    final _File source = _File();
    final Object value = Object();
    bool settled = false;
    final Future<Object> operation = source.access<Object>((
      Wallet wallet,
    ) async {
      expect(wallet, same(source.wallet));
      return value;
    });
    unawaited(operation.then<void>((_) => settled = true));
    await source.releasing.future;
    expect(source.closes, 1);
    expect(settled, isFalse);
    source.released.complete();
    expect(await operation, same(value));
    expect(source.closes, 1);
  });

  test(
    'original access error waits for release and keeps its identity',
    () async {
      final _File source = _File();
      final StateError error = StateError('Synthetic operation refused');
      bool settled = false;
      final Future<Object> operation = source.access<Object>(
        (_) async => throw error,
      );
      final Future<void> observed = operation.then<void>(
        (_) {
          fail('The original operation failed.');
        },
        onError: (Object failure, StackTrace _) {
          expect(failure, same(error));
          settled = true;
        },
      );
      await source.releasing.future;
      expect(settled, isFalse);
      source.released.complete();
      await observed;
      expect(settled, isTrue);
      expect(source.closes, 1);
    },
  );

  test('failed acquisition does not release an unowned file', () async {
    final StateError error = StateError('Synthetic acquisition refused');
    final _File source = _File()..openError = error;
    await expectLater(
      source.access<Object>((_) async => Object()),
      throwsA(same(error)),
    );
    expect(source.closes, 0);
  });
}
