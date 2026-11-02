import 'dart:async';

import 'package:zenon_syrius_wallet_flutter/screens/onboarding/import_wallet/import_draft.dart';

/// One admitted entry offer; a null selection retains an explicit refusal.
class ImportFileOffer {
  /// Transfers the bounded probe outcome into the genuine import owner.
  const ImportFileOffer(this.selection);

  /// The private admitted source, never a presentation or diagnostic field.
  final ImportFileSelection? selection;
}

/// Captures one picker capability and its source without a platform dependency.
class ImportFileOfferSession {
  /// Captures picker, probe and selection owners before opening a platform UI.
  ImportFileOfferSession({
    required this._pick,
    required this._probe,
    required this._isCurrent,
    required this._onSelected,
    required this._onPickerFailed,
  });

  final Future<String?> Function() _pick;
  final bool Function(String) _probe;
  final bool Function() _isCurrent;
  final ValueChangedSelection _onSelected;
  final void Function() _onPickerFailed;
  Future<void>? _pending;
  Future<String?>? _originalPicker;

  /// The identical platform picker Future retained through route changes.
  Future<String?>? get originalPicker => _originalPicker;

  /// A refused offer clears the previous source. No extension is consulted.
  void offer(String path) {
    if (!_isCurrent()) return;
    bool accepted;
    try {
      accepted = _probe(path);
    } on Object {
      accepted = false;
    }
    if (_isCurrent()) _onSelected(accepted ? ImportFileSelection(path) : null);
  }

  /// Clears the prior selection only while this offer still owns its source.
  void refuse() {
    if (_isCurrent()) _onSelected(null);
  }

  /// Admits one picker at a time and ignores a stale original picker answer.
  Future<void> browse() {
    final Future<void>? pending = _pending;
    if (pending != null) return pending;
    final Completer<void> completion = Completer<void>();
    _pending = completion.future;
    unawaited(
      _browse().then<void>(
        (_) {
          _pending = null;
          completion.complete();
        },
        onError: (Object error, StackTrace stack) {
          _pending = null;
          completion.completeError(error, stack);
        },
      ),
    );
    return completion.future;
  }

  Future<void> _browse() async {
    if (!_isCurrent()) return;
    try {
      final Future<String?> original = _pick();
      _originalPicker = original;
      final String? selected = await original;
      if (selected != null && _isCurrent()) offer(selected);
    } on Object {
      if (_isCurrent()) _onPickerFailed();
    }
  }
}

/// Publishes an admitted private selection, or clears it after refusal.
typedef ValueChangedSelection = void Function(ImportFileSelection?);
