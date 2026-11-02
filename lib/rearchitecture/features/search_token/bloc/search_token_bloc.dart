import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:stream_transform/stream_transform.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/refresh_bloc_mixin.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/all_tokens/all_tokens.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/token_balance/token_balance_snapshot.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/token_list_projection.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

part 'search_token_event.dart';

part 'search_token_state.dart';

/// Searches all network tokens by name, symbol, owner, or token standard.
class SearchTokenBloc extends Bloc<SearchTokenEvent, SearchTokenState>
    with RefreshBlocMixin {
  /// Creates a new instance.
  SearchTokenBloc({
    required this._zenon,
    Duration debounceDuration = const Duration(milliseconds: 350),
  }) : super(const SearchTokenInitial()) {
    on<SearchTokenRequested>(
      _onSearchRequested,
      transformer: _debounceRestartable(debounceDuration),
    );
    listenToWsRestart(
      () => add(
        SearchTokenRequested(
          query: state.query,
          refresh: true,
        ),
      ),
    );
  }

  final Zenon _zenon;

  List<Token>? _allTokens;
  Future<List<Token>>? _allTokensRequest;
  TokenReadContext? _catalogContext;
  int _queryRevision = 0;
  int _catalogRevision = 0;
  bool _closing = false;

  @override
  void add(SearchTokenEvent event) {
    if (_closing || isClosed) return;
    _queryRevision++;
    if (event is SearchTokenRequested && event.refresh) _clearCatalog();
    super.add(event);
  }

  void _clearCatalog() {
    _catalogRevision++;
    _allTokens = null;
    _allTokensRequest = null;
    _catalogContext = null;
  }

  Future<void> _onSearchRequested(
    SearchTokenRequested event,
    Emitter<SearchTokenState> emit,
  ) async {
    final String query = event.query.trim();
    final int revision = _queryRevision;
    bool current() => !_closing && !emit.isDone && revision == _queryRevision;

    if (query.isEmpty) {
      emit(const SearchTokenInitial());
      return;
    }

    emit(SearchTokenLoading(query: query));

    try {
      final List<Token> allTokens = await _getAllTokens();
      if (!current() || !(_catalogContext?.isCurrent ?? false)) return;

      final String normalizedQuery = query.toLowerCase();
      final List<Token> matchingTokens = allTokens
          .where(
            (Token token) =>
                isNonNativeToken(token) &&
                tokenMatchesQuery(token, normalizedQuery),
          )
          .toList();

      emit(
        SearchTokenPopulated(
          query: query,
          tokens: matchingTokens,
        ),
      );
    } on Object catch (error, stackTrace) {
      if (!current() ||
          (_catalogContext != null && !_catalogContext!.isCurrent)) {
        return;
      }
      emit(
        SearchTokenFailure(
          query: query,
          exception: error is SyriusException ? error : FailureException(),
        ),
      );
      try {
        addError(error, stackTrace);
      } on Object {
        // Diagnostics cannot replace a complete search failure.
      }
    }
  }

  Future<List<Token>> _getAllTokens() async {
    if (_catalogContext != null && !_catalogContext!.isCurrent) _clearCatalog();
    final List<Token>? cachedTokens = _allTokens;
    if (cachedTokens != null) return cachedTokens;

    final Future<List<Token>> request;
    if (_allTokensRequest != null) {
      request = _allTokensRequest!;
    } else {
      final TokenApi source = _zenon.embedded.token;
      final Client client = source.client;
      final int revision = _catalogRevision;
      final TokenReadContext context = TokenReadContext(
        client: client,
        sdk: _zenon,
        ownsClient: () =>
            !_closing &&
            revision == _catalogRevision &&
            identical(source, _zenon.embedded.token) &&
            identical(client, source.client),
      );
      _catalogContext = context;
      final TokenApi bound = TokenApi()..setClient(client);
      request = fetchAllTokens(
        zenon: _zenon,
        tokenApi: bound,
        isCurrent: () => context.isCurrent,
      );
      _allTokensRequest = request;
    }

    try {
      final List<Token> tokens = await request;

      if (identical(_allTokensRequest, request) &&
          (_catalogContext?.isCurrent ?? false)) {
        _allTokens = tokens;
        _allTokensRequest = null;
      }

      return tokens;
    } on Object {
      if (identical(_allTokensRequest, request)) {
        _allTokensRequest = null;
      }
      rethrow;
    }
  }

  @override
  Future<void> close() {
    _closing = true;
    _queryRevision++;
    _clearCatalog();
    cancelStreamSubscription();
    return super.close();
  }
}

EventTransformer<E> _debounceRestartable<E>(Duration duration) {
  return (Stream<E> events, EventMapper<E> mapper) {
    return restartable<E>().call(events.debounce(duration), mapper);
  };
}
