import 'dart:async';

/// The presentation receives a classification, never an exception's text.
enum ImportDecryptStatus {
  /// The original authenticated file yielded a valid seed and was released.
  ready,

  /// The original decryptor classified the supplied password as incorrect.
  incorrectPassword,

  /// Authentication, seed validation or original release could not complete.
  failed,

  /// The admitted source or route lost ownership before continuation.
  stale,
}

/// A successful seed is retained only for the original admitted continuation.
class ImportDecryptOutcome {
  /// Exposes only a safe classification and, on success, the private seed.
  const ImportDecryptOutcome(this.status, {this.seed});

  /// The safe result used to choose localized interface text.
  final ImportDecryptStatus status;

  /// Private seed material for the original continuation; never log or display.
  final String? seed;
}

/// Owns one decrypt Future and the access Future of its original result.
///
/// The access operation must complete only after releasing that original.
/// Losing the route does not cancel, replace or start another access operation.
class ImportDecryptAttempt<T extends Object> {
  /// Captures decrypt, access and validation capabilities before any await.
  ImportDecryptAttempt({
    required this.path,
    required this.source,
    required this._decrypt,
    required this._accessOriginal,
    required this._isCurrent,
    required this._validateSeed,
    required this._isIncorrectPassword,
  });

  /// The original selected encrypted file location, retained as private input.
  final String path;

  /// The exact selection identity admitted by the original import route.
  final Object source;
  final Future<T> Function(String, String) _decrypt;
  final Future<String> Function(T) _accessOriginal;
  final bool Function() _isCurrent;
  final bool Function(String) _validateSeed;
  final bool Function(Object) _isIncorrectPassword;
  Future<ImportDecryptOutcome>? _completion;
  Future<T>? _decryption;
  Future<String>? _access;
  T? _original;
  Object? _failure;

  /// These identities are retained for ownership checks, never printed.
  Future<T>? get decryption => _decryption;

  /// The actual access Future, including release of the original file.
  Future<String>? get access => _access;

  /// The unmodified authenticated file returned by the original decryptor.
  T? get original => _original;

  /// The original private failure, retained independently of its display label.
  Object? get failure => _failure;

  /// Repeated callers receive the same completion and never decrypt twice.
  Future<ImportDecryptOutcome> start(String password) {
    final Future<ImportDecryptOutcome>? existing = _completion;
    if (existing != null) return existing;
    final Completer<ImportDecryptOutcome> completion =
        Completer<ImportDecryptOutcome>();
    // Reserve this identity before invoking an injected original operation.
    _completion = completion.future;
    unawaited(
      _run(password).then<void>(
        completion.complete,
        onError: completion.completeError,
      ),
    );
    return completion.future;
  }

  Future<ImportDecryptOutcome> _run(String password) async {
    if (!_isCurrent()) {
      return const ImportDecryptOutcome(ImportDecryptStatus.stale);
    }
    try {
      final Future<T> decryption = _decrypt(path, password);
      _decryption = decryption;
      final T original = await decryption;
      _original = original;
      if (!_isCurrent()) {
        return const ImportDecryptOutcome(ImportDecryptStatus.stale);
      }
      final Future<String> access = _accessOriginal(original);
      _access = access;
      final String seed = await access;
      // Access includes the original release. Navigation cannot race it.
      if (!_isCurrent()) {
        return const ImportDecryptOutcome(ImportDecryptStatus.stale);
      }
      if (!_validateSeed(seed)) {
        return const ImportDecryptOutcome(ImportDecryptStatus.failed);
      }
      return ImportDecryptOutcome(ImportDecryptStatus.ready, seed: seed);
    } on Object catch (error) {
      _failure = error;
      if (!_isCurrent()) {
        return const ImportDecryptOutcome(ImportDecryptStatus.stale);
      }
      return ImportDecryptOutcome(
        _isIncorrectPassword(error)
            ? ImportDecryptStatus.incorrectPassword
            : ImportDecryptStatus.failed,
      );
    }
  }
}
