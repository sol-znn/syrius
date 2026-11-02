import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/all_tokens/all_tokens.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_change.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

part 'all_tokens_event.dart';

part 'all_tokens_state.dart';

/// A complete catalog bound to its original transport and context generation.
class AllTokensBloc extends HydratedCubit<AllTokensState>
    with RefreshBlocMixin {
  /// Creates a new instance.
  AllTokensBloc({required this.zenon}) : super(const AllTokensInitial()) {
    listenToWsRestart(() => add(const AllTokensRequested()));
  }

  /// The client used to interact with the Zenon network
  final Zenon zenon;
  Object? _request;
  bool _closing = false;

  /// Cached per node: see `lib/utils/node_change.dart`.
  @override
  String get storagePrefix => nodeScopedStoragePrefix(runtimeType);

  /// Admission supersedes an older read before its next asynchronous turn.
  void add(AllTokensEvent event) {
    if (_closing || isClosed || event is! AllTokensRequested) return;
    final Object request = Object();
    _request = request;
    if (state is! AllTokensInitial) emit(const AllTokensInitial());
    unawaited(_read(request));
  }

  bool _owns(Object request) =>
      !_closing && !isClosed && identical(_request, request);

  Future<void> _read(Object request) async {
    TokenReadContext? scope;
    try {
      final TokenApi source = zenon.embedded.token;
      final Client client = source.client;
      scope = TokenReadContext(
        client: client,
        sdk: zenon,
        ownsClient: () =>
            _owns(request) &&
            identical(source, zenon.embedded.token) &&
            identical(client, source.client),
      );
      // API objects are mutable in the SDK. This wrapper keeps the original
      // transport even if the shared SDK object is rebound between pages.
      final TokenApi bound = TokenApi()..setClient(client);
      final List<Token> tokens = await fetchAllTokens(
        zenon: zenon,
        tokenApi: bound,
        isCurrent: () => _owns(request) && scope!.isCurrent,
      );
      if (!_owns(request) || !scope.isCurrent) return;
      emit(
        AllTokensPopulated(
          data: tokens,
          context: scope,
        ),
      );
    } on Object catch (error, stackTrace) {
      if (!_owns(request) || (scope != null && !scope.isCurrent)) return;
      emit(
        AllTokensFailure(
          exception: error is SyriusException ? error : FailureException(),
        ),
      );
      try {
        addError(error, stackTrace);
      } on Object {
        // A diagnostic observer cannot change the unavailable catalog.
      }
    }
  }

  @override
  // Historical JSON has no current transport or request identity.
  AllTokensState? fromJson(Map<String, dynamic> json) => null;

  @override
  Map<String, dynamic>? toJson(AllTokensState state) => state.toJson();

  @override
  Future<void> close() async {
    _closing = true;
    _request = null;
    cancelStreamSubscription();
    await super.close();
  }
}
