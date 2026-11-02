import 'seed_policy.dart';

/// One observed original Deposit entry, without publication authority.
final class SeedDepositEntry {
  /// Retains the actual first-use warning and its original Continue pointer.
  SeedDepositEntry.warning({
    required bool Function() originalCurrent,
    required Future<void> Function(void Function()) tapOriginalContinue,
  }) : this._(originalCurrent, tapOriginalContinue);

  /// Observes an already-open real Start modal without dispatching a pointer.
  SeedDepositEntry.ready({required this._originalCurrent})
    : _tapOriginalContinue = null;

  SeedDepositEntry._(this._originalCurrent, this._tapOriginalContinue);

  final bool Function() _originalCurrent;
  final Future<void> Function(void Function())? _tapOriginalContinue;
  bool _attempted = false;
  bool _held = false;

  void _requireOwner(void Function() requireOwner) {
    try {
      requireOwner();
    } on Object {
      _held = true;
      rethrow;
    }
  }

  void _requireOriginal() {
    bool current = false;
    try {
      current = !_held && _originalCurrent();
    } on Object {
      current = false;
    }
    if (!current) {
      _held = true;
      throw const SeedRefused('original-deposit-entry-changed');
    }
  }

  /// Never changes a preference, opens a route directly or publishes an action.
  Future<void> prepare(void Function() requireOwner) async {
    if (_attempted || _held) {
      throw const SeedRefused('original-deposit-entry-held');
    }
    void current() {
      _requireOwner(requireOwner);
      _requireOriginal();
    }
    current();
    _attempted = true;
    try {
      final Future<void> Function(void Function())? tap = _tapOriginalContinue;
      if (tap != null) await tap(current);
      _requireOwner(requireOwner);
    } on Object {
      _held = true;
      rethrow;
    }
  }
}
