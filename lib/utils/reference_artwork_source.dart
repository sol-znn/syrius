/// The two original moving surfaces used by the entry references.
enum ReferenceArtworkKind {
  /// The original welcome composition at the reference's selected frame.
  welcomeGlobe,

  /// The original entry painter at the reference capture-time position.
  entryField,
}

/// Implemented by the actual private State; it creates no alternate surface.
abstract interface class ReferenceArtworkSource {
  /// The original kind, independent of any theme or capture command.
  ReferenceArtworkKind get referenceArtworkKind;

  /// The identical asset entry or clock; never serialized by the harness.
  Object get referenceArtworkGeneration;

  /// Only an already started original asset Future, never another load.
  Future<Object?>? get referenceArtworkReadiness;

  /// Samples the renderer without stopping or resetting its original clock.
  ReferenceArtworkFrame? captureReferenceArtwork();
}

/// One reversible renderer binding; losing its owner permanently retires it.
final class ReferenceArtworkFrame {
  /// The producer supplies only finite artwork metrics and original guards.
  ReferenceArtworkFrame({
    required this.owner,
    required this.generation,
    required this.kind,
    required Map<String, Object> observation,
    required this._current,
    required this._observed,
    required this._restore,
    required this._restoration,
  }) : observation = Map<String, Object>.unmodifiable(observation);

  /// The exact private State that returned this frame.
  final Object owner;

  /// The original composition entry or shader clock.
  final Object generation;

  /// Only an entry artwork kind, with no application-operation authority.
  final ReferenceArtworkKind kind;

  /// Finite artwork position only; no owner, input or transport is serialized.
  final Map<String, Object> observation;
  final bool Function() _current;
  final bool Function() _observed;
  final void Function() _restore;
  final bool Function() _restoration;
  bool _held = false;
  bool _restoreRequested = false;
  bool _restored = false;

  /// A lost original cannot become valid again after a later replacement.
  bool get isCurrent {
    if (_held || _restoreRequested) return false;
    final bool value = _current();
    if (!value) _held = true;
    return value;
  }

  /// Read only after the original frame has built the sampled binding.
  bool get observed => isCurrent && _observed();

  /// Retains the actual positive binding event even after later disposal.
  /// A request alone remains pending until the original frame rebuilds.
  bool get restored {
    if (_restored) return true;
    if (!_restoreRequested || _held) return false;
    if (_restoration()) _restored = true;
    return _restored;
  }

  /// Requests restoration once; then await the original frame and [restored].
  bool restore() {
    if (_restoreRequested) return _restored;
    if (!isCurrent) return false;
    _restoreRequested = true;
    _restore();
    return true;
  }
}
