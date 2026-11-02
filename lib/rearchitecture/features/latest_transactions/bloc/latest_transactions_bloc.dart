import 'dart:async';

import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/refresh_bloc_mixin.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_change.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Reads one address's history without admitting an older context's answer.
class LatestTransactionsBloc
    extends HydratedCubit<InfiniteListState<AccountBlock>>
    with RefreshBlocMixin {
  /// Keeps the existing event/state API and SDK reader.
  LatestTransactionsBloc({required this.zenon, this.pageSize = kPageSize})
    : super(const InfiniteListState<AccountBlock>.initial()) {
    listenToWsRestart(() {
      final String? address = kSelectedAddress;
      if (address == null) {
        invalidateReadContext();
      } else {
        add(InfiniteListRefreshRequested(address: Address.parse(address)));
      }
    });
  }

  /// The original SDK transport; node switches revoke outstanding reads.
  final Zenon zenon;

  /// The ledger page size, independent of de-duplicated visible rows.
  final int pageSize;
  String? _address;
  String? _node;
  int? _nodeChain;
  int? _chain;
  int _epoch = 0;
  int _nextPage = 0;
  _ActivityRead? _first;
  _ActivityRead? _more;
  bool _closing = false;

  /// Retains the existing per-node cache namespace with explicit inner scope.
  @override
  String get storagePrefix => nodeScopedStoragePrefix(runtimeType);

  /// Revokes even a context that changes away and back before an RPC returns.
  void invalidateReadContext() {
    if (_closing || isClosed) return;
    _epoch++;
    _first = null;
    _more = null;
    _address = null;
    _node = null;
    _nodeChain = null;
    _chain = null;
    _nextPage = 0;
    emit(const InfiniteListState<AccountBlock>.initial());
  }

  /// Admits the existing event API while owning each asynchronous read.
  ///
  /// Cubit state ownership permits synchronous invalidation before the next
  /// frame, including a node that changes away and back during an RPC.
  void add(InfiniteListEvent event) {
    if (_closing || isClosed) return;
    final Address? address = event.address;
    if (address == null) {
      invalidateReadContext();
      return;
    }
    final String value = address.toString();
    final int chain = getChainIdentifier();
    final bool same =
        _address == value &&
        _node == kCurrentNode &&
        _nodeChain == kNodeChainId &&
        _chain == chain;
    final bool more = event is InfiniteListMoreRequested;
    if (more &&
        (!same || _first != null || _more != null || state.hasReachedMax)) {
      return;
    }
    final bool reset = event is InfiniteListRefreshRequested || !same;
    if (!more) {
      _epoch++;
      _address = value;
      _node = kCurrentNode;
      _nodeChain = kNodeChainId;
      _chain = chain;
      _nextPage = 0;
      _more = null;
    }
    final _ActivityRead read = _ActivityRead(
      address: address,
      node: kCurrentNode,
      nodeChain: kNodeChainId,
      chain: chain,
      selection: kSelectedAddress,
      epoch: _epoch,
      page: more ? _nextPage : 0,
      more: more,
      reset:
          reset &&
          (event is InfiniteListRefreshRequested || state.data != null),
    );
    if (more) {
      _more = read;
    } else {
      _first = read;
    }
    unawaited(_read(read));
  }

  bool _current(_ActivityRead read) =>
      !_closing &&
      !isClosed &&
      read.epoch == _epoch &&
      read.address.toString() == _address &&
      read.node == kCurrentNode &&
      read.nodeChain == kNodeChainId &&
      read.chain == getChainIdentifier() &&
      read.selection == kSelectedAddress;

  Future<void> _read(_ActivityRead read) async {
    if (!_current(read)) return;
    if (read.reset) emit(const InfiniteListState<AccountBlock>.initial());
    try {
      final List<AccountBlock> page = await paginationFetch(
        address: read.address,
        pageIndex: read.page,
        pageSize: pageSize,
      );
      if (!_current(read)) return;
      if (page.any(
        (AccountBlock block) =>
            block.address != read.address ||
            block.chainIdentifier != read.chain,
      )) {
        throw const FormatException(
          'Activity response does not match its request',
        );
      }
      _nextPage = read.page + 1;
      emit(
        InfiniteListState<AccountBlock>(
          status: InfiniteListStatus.success,
          data: List<AccountBlock>.unmodifiable(<AccountBlock>[
            if (read.more) ...state.data ?? <AccountBlock>[],
            ...page,
          ]),
          hasReachedMax: page.length < pageSize,
        ),
      );
    } on Object catch (error, trace) {
      if (!_current(read)) return;
      try {
        addError(error, trace);
      } on Object {
        // A diagnostic observer cannot turn a failed read into success.
      }
      emit(
        state.copyWith(
          status: InfiniteListStatus.failure,
          error: FailureException(),
        ),
      );
    } finally {
      if (identical(_first, read)) _first = null;
      if (identical(_more, read)) _more = null;
    }
  }

  /// Calls the same ledger method as the existing address history.
  Future<List<AccountBlock>> paginationFetch({
    required Address? address,
    required int pageIndex,
    required int pageSize,
  }) async {
    final AccountBlockList accountBlock = await zenon.ledger
        .getAccountBlocksByPage(
          address!,
          pageIndex: pageIndex,
          pageSize: pageSize,
        );

    final List<AccountBlock>? rows = accountBlock.list;
    if (rows == null) throw const FormatException('Activity rows unavailable');
    return rows;
  }

  /// A legacy cache without a matching owner cannot identify whose data it is.
  @override
  InfiniteListState<AccountBlock>? fromJson(Map<String, dynamic> json) {
    try {
      final InfiniteListState<AccountBlock> decoded =
          InfiniteListState<AccountBlock>.fromJson(
            json,
            (Object? value) =>
                AccountBlock.fromJson(value! as Map<String, dynamic>),
          );
      if (decoded.status == InfiniteListStatus.initial &&
          decoded.data == null) {
        return decoded;
      }
      final Object? scope = json['context'];
      if (scope is! Map<String, dynamic> ||
          kSelectedAddress == null ||
          scope['address'] != kSelectedAddress ||
          scope['node'] != kCurrentNode ||
          scope['nodeChain'] != kNodeChainId ||
          scope['chain'] != getChainIdentifier()) {
        return null;
      }
      final Address address = Address.parse(kSelectedAddress!);
      if ((decoded.data ?? <AccountBlock>[]).any(
        (AccountBlock block) =>
            block.address != address || block.chainIdentifier != scope['chain'],
      )) {
        return null;
      }
      _address = kSelectedAddress;
      _node = kCurrentNode;
      _nodeChain = kNodeChainId;
      _chain = getChainIdentifier();
      _nextPage = json['nextPage'] is int && (json['nextPage'] as int) > 0
          ? json['nextPage'] as int
          : ((decoded.data?.length ?? 0) / pageSize).ceil();
      return decoded;
    } on Object {
      return null;
    }
  }

  /// Stores scope with rows; live request identities are never serialized.
  @override
  Map<String, dynamic> toJson(InfiniteListState<AccountBlock> state) =>
      <String, dynamic>{
        ...state.toJson((AccountBlock block) => block.toJson()),
        'context': _address == null
            ? null
            : <String, dynamic>{
                'address': _address,
                'node': _node,
                'nodeChain': _nodeChain,
                'chain': _chain,
              },
        'nextPage': _nextPage,
      };

  @override
  Future<void> close() async {
    _closing = true;
    _epoch++;
    _first = null;
    _more = null;
    cancelStreamSubscription();
    await super.close();
  }
}

class _ActivityRead {
  const _ActivityRead({
    required this.address,
    required this.node,
    required this.nodeChain,
    required this.chain,
    required this.selection,
    required this.epoch,
    required this.page,
    required this.more,
    required this.reset,
  });

  final Address address;
  final String? node;
  final int? nodeChain;
  final int chain;
  final String? selection;
  final int epoch;
  final int page;
  final bool more;
  final bool reset;
}
