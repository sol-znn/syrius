import 'dart:async';
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/server/dapp_bridge_origin.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/server/dapp_bridge_service.dart';

/// The setting that turns the channel off. Absent means on.
const String kDappBridgeEnabledKey = 'dapp_bridge_enabled';

/// Where the connected sites are kept.
const String kDappBridgeConsentKey = 'dapp_bridge_consent';

/// The key-value store the channel keeps its two settings in.
///
/// In the app it is the wallet's own settings box. That box is among those a
/// wallet reset deletes, which is the point: consent given under one wallet
/// must not be there for the next one, and it goes without the reset having
/// to know this feature exists.
abstract class DappBridgeStore {
  /// The value under [key], or null.
  Object? read(String key);

  /// Saves [value] under [key].
  Future<void> write(String key, Object? value);
}

/// Existing in-memory stores keep their two-method contract.
abstract interface class DappBridgeCapturedStore implements DappBridgeStore {
  /// Returns a store fixed to the actual open Box used by the current wallet.
  DappBridgeStore capture();

  /// The exact backend identity used to serialize consent writes.
  Object get identity;

  /// Whether this captured store is still the registered, open original.
  bool get isCurrent;
}

/// Preserves two-method fake stores while production retains its original Box.
extension DappBridgeStoreCapture on DappBridgeStore {
  /// Captures a production backend without replacing compatible memory stores.
  DappBridgeStore capture() => this is DappBridgeCapturedStore
      ? (this as DappBridgeCapturedStore).capture()
      : this;

  /// The captured Box identity, or this compatible store itself.
  Object get identity => this is DappBridgeCapturedStore
      ? (this as DappBridgeCapturedStore).identity
      : this;

  /// Memory stores remain current; production verifies exact Box ownership.
  bool get isCurrent =>
      this is! DappBridgeCapturedStore ||
      (this as DappBridgeCapturedStore).isCurrent;
}

/// One requester the person has connected, and the addresses it may see.
class DappBridgeSite extends Equatable {
  /// Creates a site.
  const DappBridgeSite({
    required this.requester,
    required this.addresses,
    this.incarnation = 0,
  });

  /// What consent is stored under: an origin, or a link requester.
  final String requester;

  /// The addresses it was shown and may ask to sign with.
  final List<String> addresses;

  /// Changes when this requester is revoked or receives a new grant.
  final Object incarnation;

  /// The origin to show.
  String get origin => dappBridgeShownOrigin(requester);

  /// Whether it asks by `syrius://request` rather than over the socket.
  bool get viaLink => dappBridgeIsLink(requester);

  @override
  List<Object?> get props => <Object?>[requester, addresses, incarnation];
}

/// The connected sites, kept in a [DappBridgeStore] as one JSON text.
///
/// Nothing is cached: every question reads the store, so a revoke, a reset
/// or a cleared settings box is in force for the very next request. What
/// does not parse counts as no consent.
class DappBridgeConsentStore
    implements DappBridgeConsent, DappBridgeCapturedConsent {
  /// Creates the consent kept in [store].
  DappBridgeConsentStore(DappBridgeStore store) : _store = store;

  final DappBridgeStore _store;
  final StreamController<void> _changes = StreamController<void>.broadcast();
  static final Expando<_ConsentTurn> _turns = Expando<_ConsentTurn>();

  /// Fires after a grant or a revoke.
  Stream<void> get changes => _changes.stream;

  /// Every connected requester, sorted by the origin shown.
  List<DappBridgeSite> get sites {
    final List<DappBridgeSite> sites = <DappBridgeSite>[
      for (final MapEntry<String, _Grant> entry in _read(_store).grants.entries)
        if (entry.value.addresses.isNotEmpty)
          DappBridgeSite(
            requester: entry.key,
            addresses: List<String>.unmodifiable(entry.value.addresses),
            incarnation: entry.value.stamp,
          ),
    ];
    return sites..sort(
      (DappBridgeSite a, DappBridgeSite b) =>
          '${a.origin} ${a.requester}'.compareTo('${b.origin} ${b.requester}'),
    );
  }

  @override
  bool has(String origin, String address) =>
      _read(_store).grants[origin]?.addresses.contains(address) ?? false;

  @override
  bool hasAny(String origin) =>
      _read(_store).grants[origin]?.addresses.isNotEmpty ?? false;

  @override
  Future<void> grant(String origin, String address) =>
      captureConsent(origin).grant(address);

  @override
  Future<void> revoke(String origin) => captureConsent(origin).revoke();

  @override
  DappBridgeConsentReceipt captureConsent(String origin) {
    final DappBridgeStore original = _store.capture();
    return _ConsentReceipt(this, original, origin, _stamp(original, origin));
  }

  /// A retained row cannot revoke a newer same-requester grant.
  DappBridgeConsentReceipt captureSite(DappBridgeSite site) {
    final DappBridgeStore original = _store.capture();
    final Object stamp = _stamp(original, site.requester);
    if (stamp != site.incarnation) {
      throw StateError('Connection unavailable');
    }
    return _ConsentReceipt(this, original, site.requester, stamp);
  }

  /// Releases the change stream.
  Future<void> close() => _changes.close();

  _ConsentData _read(DappBridgeStore store) {
    final Object? raw = store.read(kDappBridgeConsentKey);
    final Map<String, _Grant> all = <String, _Grant>{};
    if (raw is! String) {
      return _ConsentData(0, all);
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return _ConsentData(0, all);
      }
      if (decoded['_version'] == 2) {
        final Object? records = decoded['grants'];
        final Object? next = decoded['next'];
        if (records is! Map<String, dynamic> || next is! int || next < 0) {
          return _ConsentData(0, all);
        }
        int highest = next;
        for (final MapEntry<String, dynamic> entry in records.entries) {
          final Object? record = entry.value;
          if (record is! Map<String, dynamic>) continue;
          final Object? revision = record['revision'];
          final Object? addresses = record['addresses'];
          if (revision is! int || revision < 0 || addresses is! List) continue;
          if (revision > highest) highest = revision;
          all[entry.key] = _Grant(
            revision,
            addresses.whereType<String>().toList(),
          );
        }
        return _ConsentData(highest, all);
      }
      // Legacy grants retain their exact address list until an explicit action.
      for (final MapEntry<String, dynamic> entry in decoded.entries) {
        final Object? value = entry.value;
        final List<String> addresses = value is List
            ? value.whereType<String>().toList()
            : <String>[];
        if (addresses.isNotEmpty) {
          all[entry.key] = _Grant(0, addresses);
        }
      }
    } on FormatException {
      return _ConsentData(0, <String, _Grant>{});
    }
    return _ConsentData(0, all);
  }

  Object _stamp(DappBridgeStore store, String origin) =>
      _read(store).grants[origin]?.stamp ?? 'absent';

  Future<void> _mutate(
    _ConsentReceipt receipt,
    String? address, {
    bool Function()? isCurrent,
  }) {
    final _ConsentTurn turn = _turns[receipt.store.identity] ??= _ConsentTurn();
    final Future<void> next = turn.pending.then((_) async {
      if (!receipt.isCurrent || !(isCurrent?.call() ?? true)) {
        throw StateError('Connection unavailable');
      }
      final _ConsentData all = _read(receipt.store);
      final List<String> before =
          all.grants[receipt.origin]?.addresses ?? <String>[];
      if (address != null && before.contains(address)) {
        receipt._applied = receipt.stamp;
        return;
      }
      final List<String> after = address == null
          ? <String>[]
          : <String>[...before, address];
      final _Grant grant = _Grant(++all.next, after);
      all.grants[receipt.origin] = grant;
      // An empty tombstone keeps revoke/regrant from reviving old consent.
      final String encoded = jsonEncode(<String, Object>{
        '_version': 2,
        'next': all.next,
        'grants': <String, Object>{
          for (final MapEntry<String, _Grant> entry in all.grants.entries)
            entry.key: <String, Object>{
              'revision': entry.value.revision,
              'addresses': entry.value.addresses,
            },
        },
      });
      await receipt.store.write(kDappBridgeConsentKey, encoded);
      receipt._applied = grant.stamp;
      if (receipt.store.isCurrent && !_changes.isClosed) _changes.add(null);
    });
    turn.pending = next.catchError((Object _) {});
    return next;
  }
}

class _ConsentTurn {
  Future<void> pending = Future<void>.value();
}

class _Grant {
  _Grant(this.revision, this.addresses);
  final int revision;
  final List<String> addresses;
  Object get stamp => '$revision:${jsonEncode(addresses)}';
}

class _ConsentData {
  _ConsentData(this.next, this.grants);
  int next;
  final Map<String, _Grant> grants;
}

class _ConsentReceipt implements DappBridgeConsentReceipt {
  _ConsentReceipt(this.owner, this.store, this.origin, this.stamp);
  final DappBridgeConsentStore owner;
  final DappBridgeStore store;
  final String origin;
  final Object stamp;
  Object? _applied;
  bool _revoked = false;

  @override
  bool get isCurrent {
    if (_revoked) return false;
    return !(_revoked =
        !store.isCurrent || owner._stamp(store, origin) != stamp);
  }

  @override
  bool get outcomeIsCurrent =>
      store.isCurrent &&
      _applied != null &&
      owner._stamp(store, origin) == _applied;

  @override
  Future<void> grant(String address) => owner._mutate(this, address);

  @override
  Future<void> revoke({bool Function()? isCurrent}) =>
      owner._mutate(this, null, isCurrent: isCurrent);
}
