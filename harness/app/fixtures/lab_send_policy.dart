import 'seed_policy.dart';

enum LabSendConfirmationState { absent, unconfirmed }

/// One P09 UI confirmation, observed through its identical original request.
/// This policy never signs, submits, cancels or substitutes a wallet operation.
final class LabSendGuard {
  LabSendGuard({
    required this.source,
    required this.journal,
    Future<void> Function(Duration)? delay,
    this.readTimeout = const Duration(seconds: 3),
  }) : _delay = delay ?? Future<void>.delayed,
       _admission = SeedGuard.forLabSend(
         source: source,
         journal: journal,
         delay: delay,
         readTimeout: readTimeout,
       );

  final SeedSource source;
  final SeedJournal journal;
  final Duration readTimeout;
  final Future<void> Function(Duration) _delay;
  final SeedGuard _admission;
  bool _attempted = false;
  SeedOriginal? _original;
  Object? _identity;
  String? _hash;
  final List<Object> _failures = <Object>[];
  int _confirmationPolls = 0;
  int _confirmationAbsent = 0;
  int _confirmationUnconfirmed = 0;
  LabSendConfirmationState? _confirmationLast;

  /// Only completed original reads, with no receipt or retry authority.
  Map<String, Object>? get pendingConfirmationObservation {
    final LabSendConfirmationState? last = _confirmationLast;
    if (_confirmationPolls != 18 || last == null) return null;
    return Map<String, Object>.unmodifiable(<String, Object>{
      'polls': _confirmationPolls, 'absent': _confirmationAbsent,
      'unconfirmed': _confirmationUnconfirmed, 'last': last.name,
    });
  }

  String? get acceptedHash => _hash;
  SeedOriginal? get original => _original;

  /// Pointer-path errors remain private and cannot authorize replacement input.
  List<Object> get failures => List<Object>.unmodifiable(_failures);

  void requireCurrent() => _admission.requireCurrent();

  void requirePreparation() {
    requireCurrent();
    if (_attempted) throw const SeedRefused('original-attempt-held');
  }

  void _retainHash() {
    final SeedOriginal value = _original!;
    if (!identical(value.identity, _identity)) {
      throw const SeedRefused('original-publication-replaced');
    }
    final String? accepted = value.acceptedHash;
    if (accepted == null) {
      if (_hash != null) throw const SeedRefused('invalid-original-hash');
      return;
    }
    if (!seedHash(accepted) || _hash != null && _hash != accepted) {
      throw const SeedRefused('invalid-original-hash');
    }
    if (_hash == null) {
      _hash = accepted;
      journal.accepted(labSendRecipeId, accepted);
    }
  }

  Future<T> _read<T>(Future<T> Function() read) async {
    requireCurrent();
    final T value = await read().timeout(readTimeout);
    requireCurrent();
    return value;
  }

  /// [tapOnce] must use ordinary pointer input and recheck the supplied
  /// admission at pointer down/up. [requireOriginalReady] belongs to the actual
  /// confirmation witness, never to a reconstructed or scalar-matched request.
  Future<String> publish({
    required SeedOriginal original,
    required void Function() requireOriginalReady,
    required Future<void> Function(void Function() admission) tapOnce,
  }) async {
    requirePreparation();
    _original = original;
    _identity = original.identity;
    void admission() {
      requireCurrent();
      if (!identical(original.identity, _identity) ||
          original.settled || original.failed || original.releaseFailed ||
          original.acceptedHash != null) {
        throw const SeedRefused('original-transfer-attempt-held');
      }
      requireOriginalReady();
    }

    admission();
    // The existing read admission still refuses any earlier unresolved original
    // publication. After this claim, unrelated automatic receives are not used
    // to select or replace the exact request supplied above.
    await _admission.admit(labSendRecipeId);
    requirePreparation();
    admission();
    _attempted = true;
    journal.claim(labSendRecipeId);
    try {
      await tapOnce(admission);
    } on Object catch (error) {
      _failures.add(error);
      try {
        _retainHash();
      } on Object catch (retentionError) {
        _failures.add(retentionError);
      }
      rethrow;
    }
    for (int poll = 0; poll < 60; poll++) {
      // Retain the first original answer even when its owner was just revoked.
      _retainHash();
      requireCurrent();
      if (original.failed || original.releaseFailed) {
        throw const SeedRefused('original-outcome-unknown');
      }
      if (original.settled && _hash != null) break;
      await _delay(const Duration(milliseconds: 500));
    }
    if (!original.settled || _hash == null) {
      throw const SeedRefused('original-outcome-unknown');
    }
    final String hash = _hash!;
    for (int poll = 0; poll < 18; poll++) {
      _retainHash();
      if (original.failed || original.releaseFailed) {
        throw const SeedRefused('original-outcome-unknown');
      }
      final SeedConfirmed? block = await _read(
        () => source.confirmed(labSendRecipeId, hash),
      );
      if (block != null &&
          (block.hash != hash || block.owner != source.environment.owner ||
              block.chain != 321 || !block.matchesRecipe)) {
        throw const SeedRefused('exact-original-receipt-mismatch');
      }
      if (block?.positiveConfirmation == true) {
        _retainHash();
        requireCurrent();
        if (original.failed || original.releaseFailed) {
          throw const SeedRefused('original-outcome-unknown');
        }
        journal.confirmed(labSendRecipeId, hash);
        return hash;
      }
      _confirmationPolls = poll + 1;
      if (block == null) {
        _confirmationAbsent++;
        _confirmationLast = LabSendConfirmationState.absent;
      } else {
        _confirmationUnconfirmed++;
        _confirmationLast = LabSendConfirmationState.unconfirmed;
      }
      await _delay(const Duration(seconds: 2));
    }
    throw const SeedRefused('exact-confirmation-pending');
  }
}
