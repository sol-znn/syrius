import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Immutable choices published by one mounted Receive form.
class ReceiveHeaderSnapshot {
  ReceiveHeaderSnapshot._(
    this._owner,
    Map<String, String> labels,
    this.selected,
  ) : labels = Map<String, String>.unmodifiable(labels);

  final Object _owner;

  /// The form's address labels, in wallet order.
  final Map<String, String> labels;

  /// The form's selected receiving address.
  final String selected;
}

/// Connects Transfer's compact picker to the existing Receive form owner.
///
/// Revocation is synchronous; presentation notifications wait until the frame
/// ends so a child can publish without rebuilding its parent during build.
class ReceiveHeaderController extends ChangeNotifier {
  ReceiveHeaderSnapshot? _snapshot;
  bool Function()? _isCurrent;
  bool Function(String)? _onSelected;
  int _revision = 0;
  bool _scheduled = false;
  bool _closed = false;

  /// Changes on every publication or revocation, including rapid mode swaps.
  int get revision => _revision;

  /// The current form's choices, or null while its owner is inactive.
  ReceiveHeaderSnapshot? get snapshot =>
      !_closed && (_isCurrent?.call() ?? false) ? _snapshot : null;

  /// Publishes only if no intervening revocation changed the expected revision.
  void publish({
    required Object owner,
    required int expectedRevision,
    required Map<String, String> labels,
    required String selected,
    required bool Function() isCurrent,
    required bool Function(String) onSelected,
  }) {
    if (_closed || expectedRevision != _revision || !isCurrent() ||
        !labels.containsKey(selected)) {
      return;
    }
    final ReceiveHeaderSnapshot? previous = _snapshot;
    if (previous != null && identical(previous._owner, owner) &&
        previous.selected == selected && mapEquals(previous.labels, labels) &&
        listEquals(previous.labels.keys.toList(), labels.keys.toList())) {
      return;
    }
    _snapshot = ReceiveHeaderSnapshot._(owner, labels, selected);
    _isCurrent = isCurrent;
    _onSelected = onSelected;
    _revision += 1;
    _notifyAfterFrame();
  }

  /// Refuses retained menu callbacks from an old owner or choice snapshot.
  bool select(ReceiveHeaderSnapshot choices, String address) {
    if (!identical(snapshot, choices) || !choices.labels.containsKey(address)) {
      return false;
    }
    final bool applied = _onSelected?.call(address) ?? false;
    if (applied && identical(_snapshot, choices)) invalidate();
    return applied;
  }

  /// Checks the form owner without exposing it to the header widget.
  bool ownsCurrent(Object owner) => identical(snapshot?._owner, owner);

  /// Immediately revokes menus and pending QR exports, even before a rebuild.
  void invalidate() {
    if (_closed) return;
    _revision += 1;
    _snapshot = null;
    _isCurrent = null;
    _onSelected = null;
    _notifyAfterFrame();
  }

  /// Detaches only the exact form that last published the choices.
  void detach(Object owner) {
    if (identical(_snapshot?._owner, owner)) invalidate();
  }

  void _notifyAfterFrame() {
    if (_scheduled || _closed) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((Duration _) {
      _scheduled = false;
      if (!_closed) notifyListeners();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _closed = true;
    _revision += 1;
    _snapshot = null;
    _isCurrent = null;
    _onSelected = null;
    super.dispose();
  }
}
