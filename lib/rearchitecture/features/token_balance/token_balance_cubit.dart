import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/refresh_bloc_mixin.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/all_tokens/token_read_context.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/token_balance/token_balance_snapshot.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Unknown, unavailable or complete balances for the current account read.
final class TokenBalanceState {
  /// A read without a complete successful account has no balance snapshot.
  const TokenBalanceState({this.snapshot, this.context, this.failed = false});

  /// Complete exact units. Retained SDK or hydrated balances are not used.
  final TokenBalanceSnapshot? snapshot;

  /// The original context of the complete read.
  final TokenReadContext? context;

  /// A failure is unavailable, with no inferred zero.
  final bool failed;

  /// A successful read remains usable only in its original context.
  TokenBalanceSnapshot? get current =>
      (context?.isCurrent ?? false) ? snapshot : null;
}

/// A page-owned account read, revoked on supersession, context change or close.
final class TokenBalanceCubit extends Cubit<TokenBalanceState>
    with RefreshBlocMixin {
  /// Constructs the reader without opening a socket or reading a wallet.
  TokenBalanceCubit({required this.zenon, required this.address})
    : super(const TokenBalanceState()) {
    listenToWsRestart(refresh);
  }

  /// The shared SDK object whose original ledger transport is captured.
  final Zenon zenon;

  /// The exact selected account represented by this reader.
  final String address;
  Object? _request;
  bool _closing = false;

  /// Replaces the old authority before issuing the new account request.
  void refresh() {
    if (_closing || isClosed) return;
    final Object request = Object();
    _request = request;
    emit(const TokenBalanceState());
    unawaited(_read(request));
  }

  bool _owns(Object request) =>
      !_closing &&
      !isClosed &&
      identical(_request, request) &&
      kSelectedAddress == address;

  Future<void> _read(Object request) async {
    TokenReadContext? context;
    try {
      final LedgerApi source = zenon.ledger;
      final Client client = source.client;
      context = TokenReadContext(
        client: client,
        sdk: zenon,
        ownsClient: () =>
            _owns(request) &&
            identical(source, zenon.ledger) &&
            identical(client, source.client),
      );
      final LedgerApi bound = LedgerApi()..setClient(client);
      context.requireCurrent();
      final AccountInfo account = await bound.getAccountInfoByAddress(
        Address.parse(address),
      );
      if (!_owns(request) || !context.isCurrent) return;
      final TokenBalanceSnapshot snapshot = TokenBalanceSnapshot.fromAccount(
        account,
        address,
      );
      emit(TokenBalanceState(snapshot: snapshot, context: context));
    } on Object catch (error, trace) {
      if (!_owns(request) || (context != null && !context.isCurrent)) return;
      emit(const TokenBalanceState(failed: true));
      try {
        addError(error, trace);
      } on Object {
        // Optional diagnostics cannot establish balances after a failed read.
      }
    }
  }

  @override
  Future<void> close() {
    _closing = true;
    _request = null;
    cancelStreamSubscription();
    return super.close();
  }
}
