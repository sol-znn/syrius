import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/blocs/fetch_bloc/fetch_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// A current address read, with no unbound historical cache used as authority.
///
/// The legacy request and state API is retained for its feature consumers.
/// Admission revokes an earlier response before an asynchronous read starts.
abstract class AddressOwnedFetchCubit<T extends Object>
    extends Cubit<FetchState<T>> {
  /// Uses the existing feature RPC transport.
  AddressOwnedFetchCubit({required this.zenon}) : super(FetchInitial<T>());

  /// The original SDK client for this reader's lifetime.
  final Zenon zenon;
  _AddressRead? _read;
  bool _completed = false;
  bool _closing = false;

  /// Opaque identity of a completed read, including a proven empty answer.
  Object? get readOwner => _completed ? _read : null;

  /// Whether the displayed state belongs to this address's current context.
  bool isCurrentFor(String address) {
    final _AddressRead? read = _read;
    return read != null &&
        _completed &&
        read.address.toString() == address &&
        _current(read);
  }

  /// A panel may retain only its original completed read's identity.
  bool ownsRead(Object owner, String address) =>
      identical(readOwner, owner) && isCurrentFor(address);

  /// The feature's existing public read.
  Future<T> getData({required Address address});

  /// Rejects a successful answer that belongs to another account.
  bool accepts(T data, Address address);

  /// A node or selection boundary revokes an old result synchronously.
  void invalidateReadContext() {
    if (_closing || isClosed) return;
    _read = null;
    _completed = false;
    if (state is! FetchInitial<T>) emit(FetchInitial<T>());
  }

  /// A fresh request supersedes every older result, failure and empty answer.
  void add(FetchEvent event) {
    if (_closing || isClosed || event is! FetchRequestData) return;
    final _AddressRead read = _AddressRead(event.address);
    _read = read;
    _completed = false;
    if (state is! FetchInitial<T>) emit(FetchInitial<T>());
    unawaited(_fetch(read));
  }

  bool _current(_AddressRead read) =>
      !_closing && !isClosed && identical(_read, read) && read.isCurrent;

  Future<void> _fetch(_AddressRead read) async {
    if (!_current(read)) return;
    try {
      final T data = await getData(address: read.address);
      if (!_current(read)) return;
      if (!accepts(data, read.address)) {
        throw const FormatException(
          'Owner response does not match its request',
        );
      }
      _completed = true;
      emit(FetchPopulated<T>(data: data));
    } on Object catch (error, trace) {
      if (!_current(read)) return;
      _completed = true;
      emit(
        FetchFailure<T>(
          exception: error is SyriusException ? error : FailureException(),
        ),
      );
      try {
        addError(error, trace);
      } on Object {
        // Diagnostic observers cannot change the read's failure result.
      }
    }
  }

  @override
  Future<void> close() {
    _closing = true;
    _read = null;
    _completed = false;
    return super.close();
  }
}

class _AddressRead {
  _AddressRead(this.address)
    : revision = WalletContextRevision.value,
      client = app.zenon,
      selection = kSelectedAddress,
      node = kCurrentNode,
      nodeChain = kNodeChainId,
      chain = getChainIdentifier();

  final Address address;
  final int revision;
  final Zenon? client;
  final String? selection;
  final String? node;
  final int? nodeChain;
  final int chain;
  bool _revoked = false;

  bool get isCurrent {
    if (_revoked) return false;
    return !(_revoked =
        revision != WalletContextRevision.value ||
        !identical(client, app.zenon) ||
        selection != kSelectedAddress ||
        node != kCurrentNode ||
        nodeChain != kNodeChainId ||
        chain != getChainIdentifier());
  }
}
