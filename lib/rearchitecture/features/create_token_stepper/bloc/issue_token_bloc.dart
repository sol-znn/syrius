import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/plasma_purpose.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

part 'issue_token_event.dart';

part 'issue_token_state.dart';

/// A bloc that issues a new ZTS token on-chain.
class IssueTokenBloc extends Bloc<IssueTokenEvent, IssueTokenState> {
  /// Creates an [IssueTokenBloc].
  IssueTokenBloc({
    required this._accountBlockUtils,
    required Zenon zenon,
    required this._zenonAddressUtils,
    TokenApi? tokenApi,
  }) : _tokenApi = tokenApi ?? zenon.embedded.token,
       super(const IssueTokenInitial()) {
    on<IssueTokenRequested>(_onIssueTokenRequested);
  }

  final AccountBlockUtils _accountBlockUtils;

  final TokenApi _tokenApi;

  final ZenonAddressUtils _zenonAddressUtils;

  AccountBlockTemplate? _lastAccepted;

  /// The exact original outcome remains available even when the bloc closes.
  AccountBlockTemplate? get lastAccepted => _lastAccepted;

  FutureOr<void> _onIssueTokenRequested(
    IssueTokenRequested event,
    Emitter<IssueTokenState> emit,
  ) async {
    if (emit.isDone) return;
    late final IssueTokenState terminal;
    try {
      emit(const IssueTokenLoading());

      final NewTokenData tokenData = event.tokenData;
      final AccountBlockTemplate transactionParams = _tokenApi.issueToken(
        tokenData.tokenName,
        tokenData.tokenSymbol,
        tokenData.tokenDomain,
        tokenData.totalSupply,
        tokenData.maxSupply,
        tokenData.decimals,
        tokenData.isMintable,
        tokenData.isBurnable,
        tokenData.isUtility,
      );

      final AccountBlockTemplate response = await _accountBlockUtils
          .createAccountBlock(
            transactionParams,
            PlasmaPurpose.issueToken.message,
            address: Address.parse(tokenData.address),
            waitForRequiredPlasma: true,
          );

      _lastAccepted = response;

      // Info on how the new token standard is generate can be found at:
      // https://github.com/zenon-network/go-zenon/blob/667a69d9e9a418edf7580b08492ba5dcb9efd63a/vm/embedded/implementation/token.go#L71
      // and
      // https://github.com/zenon-network/go-zenon/blob/667a69d9e9a418edf7580b08492ba5dcb9efd63a/common/types/tokenstandard.go#L12-L25
      final TokenStandard newTokenStandard = TokenStandard.fromBytes(
        Crypto.digest(response.hash.getBytes()!).sublist(
          0,
          TokenStandard.coreSize,
        ),
      );

      terminal = IssueTokenDone(
        accountBlock: response,
        newTokenStandard: newTokenStandard,
      );
    } on SyriusException catch (e, stackTrace) {
      _reportError(e, stackTrace);
      terminal = IssueTokenFailure(exception: e, error: e);
    } on Object catch (e, stackTrace) {
      _reportError(e, stackTrace);
      terminal = IssueTokenFailure(exception: FailureException(), error: e);
    }
    if (!emit.isDone) emit(terminal);
    if (terminal is IssueTokenDone) {
      try {
        _zenonAddressUtils.refreshBalance();
      } on Object catch (error, trace) {
        _reportError(error, trace);
      }
    }
  }

  @override
  void onChange(Change<IssueTokenState> change) {
    if (change.nextState is! IssueTokenDone &&
        change.nextState is! IssueTokenFailure) {
      super.onChange(change);
      return;
    }
    try {
      super.onChange(change);
    } on Object catch (error, trace) {
      // Terminal observer failure cannot replace the original delivered state.
      _reportError(error, trace);
    }
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    try {
      super.onError(error, stackTrace);
    } on Object {
      // A diagnostic observer cannot replace an original preparation or result.
    }
  }

  void _reportError(Object error, StackTrace trace) {
    try {
      addError(error, trace);
    } on Object {
      // Diagnostic observers cannot strand a form or replace acceptance.
    }
  }
}
