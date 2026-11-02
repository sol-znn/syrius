import 'dart:async';
import 'dart:convert';

import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/utils/init_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_file.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_initialization.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Observes once-only Ledger-reference creation under the captured owner.
class LedgerWalletFileBloc extends BaseBloc<LedgerWalletFile?> {
  Completer<void>? _delivery;
  WalletInitializationRun? _original;
  Object? _admissionError;
  StackTrace? _admissionStackTrace;

  /// Whether the original admission failure and trace are retained privately.
  bool get hasRetainedAdmissionFailure =>
      _admissionError != null && _admissionStackTrace != null;

  /// The exact initialization run, retained independently of stream delivery.
  WalletInitializationRun? get original => _original;

  /// Reserves the original device intent before its factory or observers run.
  /// Repeated callers receive the same delivery without creating another file.
  Future<void> getLedgerWalletPath(
    String walletId,
    String password,
    String? walletName, {
    required bool Function() sourceIsCurrent,
    WalletInitializationBinding? binding,
  }) {
    if (_delivery != null) return _delivery!.future;
    final Completer<void> delivery = Completer<void>();
    _delivery = delivery;
    unawaited(
      _create(
        walletId,
        password,
        walletName,
        sourceIsCurrent,
        binding,
        delivery,
      ),
    );
    return delivery.future;
  }

  Future<void> _create(
    String walletId,
    String password,
    String? walletName,
    bool Function() sourceIsCurrent,
    WalletInitializationBinding? injected,
    Completer<void> delivery,
  ) async {
    bool current() {
      try {
        return !disposed && sourceIsCurrent();
      } on Object {
        return false;
      }
    }

    try {
      if (!current()) throw const WalletInitializationRefused('route');
      final WalletInitializationBinding? captured =
          injected ?? InitUtils.captureWalletCreation(sourceIsCurrent: current);
      if (captured == null) {
        throw const WalletInitializationRefused('capability');
      }
      final WalletInitializationRun run = captured.start(
        create: () =>
            LedgerWalletFile.create(walletId, password, walletName: walletName),
        cipherKey: Crypto.digest(utf8.encode(password)),
      );
      _original = run;
      final WalletInitializationOutcome outcome = await run.completion;
      if (!current()) return;
      final Object? file = outcome.file;
      if (!outcome.published ||
          !outcome.initialized ||
          outcome.error != null ||
          file is! LedgerWalletFile) {
        throw const WalletInitializationRefused('initialization');
      }
      if (!captured.isCurrent) return;
      addEvent(file);
    } on Object catch (error, trace) {
      _admissionError = error;
      _admissionStackTrace = trace;
      if (current()) {
        await addError(const WalletInitializationRefused(), StackTrace.empty);
      }
    } finally {
      delivery.complete();
    }
  }
}
