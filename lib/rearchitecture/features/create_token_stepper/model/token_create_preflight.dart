import 'package:flutter/foundation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/create_token_stepper/model/token_create_session.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Fresh facts for admission, separate from form rebuilding and publication.
class TokenCreatePreflight extends ChangeNotifier {
  /// The authority signal only invalidates; it never starts another RPC.
  TokenCreatePreflight({required this.session, this._authority}) {
    _authority?.addListener(_authorityChanged);
  }

  /// One original account, chain and transport for this entire retained flow.
  final TokenCreateSession session;
  final Listenable? _authority;
  BigInt? _znn;
  int? _plasma;
  bool _loading = false;
  bool _failed = false;
  bool _disposed = false;
  bool _presentationClosed = false;
  int _generation = 0;
  Object? _ticket;

  /// A request in flight is unknown, even when an older read was sufficient.
  bool get loading => !_disposed && _loading;

  /// A failed or incomplete response offers only an explicit retry.
  bool get failed => !_disposed && _failed;

  /// No retained financial facts are painted after authority leaves.
  bool get isCurrent => !_disposed && !_presentationClosed && session.isCurrent;

  /// Null remains distinct from a complete successful zero balance.
  BigInt? get znn => isCurrent ? _znn : null;

  /// Raw Plasma is copied from the response before it can later mutate.
  int? get plasma => isCurrent ? _plasma : null;

  /// The exact fresh read under which dispatch may be admitted.
  Object? get ticket => isCurrent ? _ticket : null;

  /// Both original checks are retained even though neither is a visible step.
  bool get sufficient =>
      isCurrent &&
      !_loading &&
      !_failed &&
      _ticket != null &&
      _znn != null &&
      _znn! >= tokenZtsIssueFeeInZnn &&
      _plasma != null &&
      _plasma! >= kIssueTokenPlasmaAmountNeeded;

  bool _owns(int generation) => isCurrent && generation == _generation;

  /// Entry, explicit retry, Continue and Issue call this, never a build method.
  Future<bool> refresh() async {
    if (!isCurrent) return false;
    final int generation = ++_generation;
    _znn = null;
    _plasma = null;
    _ticket = null;
    _loading = true;
    _failed = false;
    _changed();
    try {
      final List<Object> facts = await Future.wait<Object>(<Future<Object>>[
        _readZnn(),
        _readPlasma(),
      ]);
      if (!_owns(generation)) return false;
      _znn = facts[0] as BigInt;
      _plasma = facts[1] as int;
      _ticket = Object();
    } on Object {
      if (!_owns(generation)) return false;
      _failed = true;
    } finally {
      if (_owns(generation)) {
        _loading = false;
        _changed();
      }
    }
    return _owns(generation) && sufficient;
  }

  Future<BigInt> _readZnn() async {
    final AccountInfo account = await session.readAccount();
    final BigInt? amount = tokenCreateZnnBalance(account, session.owner);
    if (amount == null) throw const FormatException('Incomplete token account');
    return amount;
  }

  Future<int> _readPlasma() async {
    final PlasmaInfo info = await session.readPlasma();
    final int amount = info.currentPlasma;
    if (amount < 0) throw const FormatException('Invalid token Plasma');
    return amount;
  }

  void _authorityChanged() {
    if (_disposed || session.isCurrent) return;
    _generation++;
    _znn = null;
    _plasma = null;
    _ticket = null;
    _loading = false;
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Leaving the form revokes pending dispatch, without rewriting its result.
  void closePresentation() {
    _presentationClosed = true;
    _generation++;
    _znn = null;
    _plasma = null;
    _ticket = null;
    _loading = false;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _authority?.removeListener(_authorityChanged);
    super.dispose();
  }
}
