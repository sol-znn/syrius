import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_flight_registry.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/flight.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Keeps the original result while its mutable SDK identity is copied once.
@immutable
class RegistrationPublication {
  /// [name] is the submitted name, before the form can clear its controllers.
  RegistrationPublication({
    required AccountBlockTemplate accountBlock,
    this._name,
    this._qsrCost,
  }) : _accountBlock = accountBlock,
       _hash = accountBlock.hash.toString(),
       _ownerAddress = accountBlock.address.toString(),
       _chainId = accountBlock.chainIdentifier,
       _amount = accountBlock.amount;

  final AccountBlockTemplate _accountBlock;
  final String _hash;
  final String _ownerAddress;
  final int _chainId;
  final BigInt _amount;
  final String? _name;
  final BigInt? _qsrCost;

  /// The exact accepted response, never replaced by a later read or retry.
  AccountBlockTemplate get accountBlock => _accountBlock;

  /// Fresh SDK wrappers cannot mutate the retained identity.
  Hash get hash => Hash.fromBytes(
    List<int>.unmodifiable(Hash.parse(_hash).getBytes()!),
  );

  /// The immutable hash displayed by the receipt.
  String get hashText => _hash;

  /// The original publishing account.
  String get ownerAddress => _ownerAddress;

  /// The original signing chain.
  int get chainId => _chainId;

  /// The exact published amount in its original smallest units.
  BigInt get amount => _amount;

  /// The original form's name, when the object has one.
  String? get name => _name;

  /// The QSR cost shown by the original review, absent when unknown.
  BigInt? get qsrCost => _qsrCost;
}

/// Follows one original publication without signing, retrying or timing out.
class RegistrationConfirmation extends ChangeNotifier {
  /// An injected registry keeps source tests independent of a running node.
  RegistrationConfirmation({
    required this._context,
    required this._chainId,
    required Iterable<String> walletAddresses,
    WalletFlightRegistry? registry,
  }) : _addresses = List<String>.unmodifiable(walletAddresses),
       _registry = registry ?? WalletFlightRegistry.instance {
    WalletContextRevision.changes.addListener(_authorityChanged);
  }

  /// Captures the unlocked account before this registration flow can yield.
  factory RegistrationConfirmation.capture() {
    final String? owner = kSelectedAddress;
    return RegistrationConfirmation(
      context: owner == null ? null : WalletActionContext.capture(owner),
      chainId: getChainIdentifier(),
      walletAddresses: kDefaultAddressList.whereType<String>(),
    );
  }

  final WalletActionContext? _context;
  final int _chainId;
  final List<String> _addresses;
  final WalletFlightRegistry _registry;
  Object _originalAttempt = Object();
  RegistrationPublication? _publication;
  InFlightBlocks? _flights;
  Future<void>? _checking;
  bool _confirmed = false;
  bool _revoked = false;
  bool _disposed = false;

  /// The same captured authority is used before publication and confirmation.
  WalletActionContext? get context => _context;

  /// The chain captured before any asynchronous registration work.
  int get chainId => _chainId;

  /// The original accepted result remains available after context revocation.
  RegistrationPublication? get publication => _publication;

  /// Opaque identity of this original attempt, replaced only by Another.
  /// Reading it cannot query a chain or grant publication authority.
  Object get originalAttempt => _originalAttempt;

  /// A context that leaves cannot acquire confirmation authority on return.
  bool get isCurrent {
    if (_disposed || _revoked) return false;
    return !(_revoked = !(_context?.isCurrent ?? false));
  }

  /// Absence from pending, elapsed time and failed reads are never evidence.
  bool get isConfirmed => isCurrent && _confirmed;

  /// Only retained positive evidence for this owner and chain can rearm a send.
  /// Looking up this fact never starts a new RPC or changes an original result.
  bool hasConfirmedOriginal({
    required String hash,
    required String owner,
    required int chainId,
  }) {
    if (!isCurrent ||
        chainId != _chainId ||
        owner != _context?.ownerAddress ||
        !_addresses.contains(owner)) {
      return false;
    }
    try {
      final Hash original = Hash.parse(hash);
      return original != emptyHash &&
          _registry.forWallet(_chainId, _addresses).hasConfirmed(original);
    } on Object {
      return false;
    }
  }

  bool get _matchesOriginal {
    final RegistrationPublication? publication = _publication;
    return publication != null &&
        publication.hash != emptyHash &&
        publication.chainId == _chainId &&
        publication.ownerAddress == _context?.ownerAddress &&
        _addresses.contains(publication.ownerAddress);
  }

  /// Accepts only the first returned result until an explicit new registration.
  bool accept(RegistrationPublication publication) {
    if (_disposed || _publication != null) return false;
    _publication = publication;
    if (_matchesOriginal && isCurrent) {
      final InFlightBlocks flights = _registry.forWallet(_chainId, _addresses);
      _flights = flights;
      flights.addListener(_observe);
      // Publication observation may already have settled this exact hash.
      if (!flights.hasConfirmed(publication.hash)) {
        try {
          flights.sent(hash: publication.hash, amount: publication.amount);
        } on Object {
          // A display listener cannot replace the retained original result.
        }
      }
      _observe();
      unawaited(check());
    } else {
      _notify();
    }
    return true;
  }

  /// Requests positive evidence through the existing chain-bound registry.
  Future<void> check() {
    final Future<void>? running = _checking;
    if (running != null) return running;
    if (_disposed || !_matchesOriginal || !isCurrent) {
      return Future<void>.value();
    }
    final Future<void> read = _check();
    _checking = read;
    unawaited(
      read.then((_) {
        if (identical(_checking, read)) _checking = null;
      }),
    );
    return read;
  }

  Future<void> _check() async {
    try {
      await _flights?.check();
    } on Object {
      // A failed observation cannot replace the accepted registration.
    }
    _observe();
  }

  void _observe() {
    if (_disposed) return;
    final RegistrationPublication? publication = _publication;
    if (_matchesOriginal && isCurrent && publication != null) {
      _confirmed =
          _confirmed || (_flights?.hasConfirmed(publication.hash) ?? false);
    }
    _notify();
  }

  void _authorityChanged() {
    if (!_disposed && !isCurrent) _notify();
  }

  void _notify() {
    try {
      notifyListeners();
    } on Object {
      // Optional UI observers cannot rewrite a node-accepted result.
    }
  }

  /// Only the explicit Another action can replace a confirmed registration.
  bool resetForAnother() {
    if (!isConfirmed) return false;
    _flights?.removeListener(_observe);
    _flights = null;
    _publication = null;
    _originalAttempt = Object();
    _confirmed = false;
    _notify();
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    WalletContextRevision.changes.removeListener(_authorityChanged);
    _flights?.removeListener(_observe);
    super.dispose();
  }
}
