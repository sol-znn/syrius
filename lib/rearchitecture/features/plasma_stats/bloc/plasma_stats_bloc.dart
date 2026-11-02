import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/constants/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Bloc that loads Plasma stats for wallet addresses.
class PlasmaStatsBloc extends InfiniteListBloc<PlasmaInfoWrapper> {
  /// Creates a [PlasmaStatsBloc].
  PlasmaStatsBloc({required super.zenon, super.pageSize = kPageSize})
    : super(
        fromJsonT: (Object? map) => PlasmaInfoWrapper.fromJson(
          map! as Map<String, dynamic>,
        ),
        toJsonT: (PlasmaInfoWrapper info) => info.toJson(),
      );

  int _epoch = 0;
  int? _completedRevision;
  String? _completedNode;
  String? _completedSelection;
  int? _completedChain;
  int? _completedNodeChain;
  PlasmaApi? _completedApi;
  Client? _completedClient;
  final Map<String, PlasmaInfoWrapper> _readings =
      <String, PlasmaInfoWrapper>{};

  /// Hydrated or superseded levels are never current beneficiary facts.
  bool get hasCurrentRead =>
      _completedRevision == WalletContextRevision.value &&
      identical(zenon, app.zenon) &&
      _completedNode == kCurrentNode &&
      _completedSelection == kSelectedAddress &&
      _completedChain == getChainIdentifier() &&
      _completedNodeChain == kNodeChainId &&
      identical(_completedApi, zenon.embedded.plasma) &&
      identical(_completedClient, _completedApi?.client);

  /// Fresh per-address values do not inherit an older paginated cache row.
  PlasmaInfoWrapper? currentReading(String address) =>
      hasCurrentRead ? _readings[address] : null;

  /// Current beneficiary readings without hydrated or superseded cache rows.
  List<PlasmaInfoWrapper> get currentReadings => hasCurrentRead
      ? List<PlasmaInfoWrapper>.unmodifiable(_readings.values)
      : const <PlasmaInfoWrapper>[];

  @override
  Future<List<PlasmaInfoWrapper>> paginationFetch({
    required Address? address,
    required int pageIndex,
    required int pageSize,
  }) async {
    final bool continueRead = hasCurrentRead && pageIndex > 0;
    final int epoch = ++_epoch;
    final int revision = WalletContextRevision.value;
    final String? node = kCurrentNode;
    final String? selection = kSelectedAddress;
    final int chain = getChainIdentifier();
    final int? nodeChain = kNodeChainId;
    final List<String?> owners = List<String?>.of(kDefaultAddressList);
    final PlasmaApi source = zenon.embedded.plasma;
    final Client client = source.client;
    final PlasmaApi bound = PlasmaApi()..setClient(client);
    _completedRevision = null;
    final int start = pageIndex * pageSize;
    final int end = start + pageSize;

    final int length = owners.length;

    final List<String?> targetedAddresses = owners.sublist(
      start < length ? start : length,
      end < length ? end : length,
    );

    final List<PlasmaInfoWrapper> result = await _getPlasmas(
      addresses: targetedAddresses,
      api: bound,
    );
    if (isClosed ||
        epoch != _epoch ||
        revision != WalletContextRevision.value ||
        node != kCurrentNode ||
        selection != kSelectedAddress ||
        chain != getChainIdentifier() ||
        nodeChain != kNodeChainId ||
        !identical(zenon, app.zenon) ||
        !listEquals(owners, kDefaultAddressList) ||
        !identical(source, zenon.embedded.plasma) ||
        !identical(client, source.client)) {
      throw StateError('Beneficiary Plasma context changed');
    }
    _completedRevision = revision;
    _completedNode = node;
    _completedSelection = selection;
    _completedChain = chain;
    _completedNodeChain = nodeChain;
    _completedApi = source;
    _completedClient = client;
    if (!continueRead) _readings.clear();
    for (final PlasmaInfoWrapper reading in result) {
      _readings[reading.address] = reading;
    }
    return result;
  }

  Future<List<PlasmaInfoWrapper>> _getPlasmas({
    required List<String?> addresses,
    required PlasmaApi api,
  }) async {
    final List<PlasmaInfoWrapper> plasmaInfoWrapper = await Future.wait(
      addresses.map((String? e) => _getPlasma(api, e!)).toList(),
    );

    return plasmaInfoWrapper;
  }

  Future<PlasmaInfoWrapper> _getPlasma(PlasmaApi api, String address) async {
    try {
      final PlasmaInfo plasmaInfo = await api.get(
        Address.parse(address),
      );
      if (plasmaInfo.currentPlasma < 0 ||
          plasmaInfo.maxPlasma < 0 ||
          plasmaInfo.qsrAmount < BigInt.zero) {
        throw const FormatException('Invalid beneficiary Plasma response');
      }
      return PlasmaInfoWrapper(address: address, plasmaInfo: plasmaInfo);
    } catch (e, stackTrace) {
      addError(e, stackTrace);
      rethrow;
    }
  }
}
