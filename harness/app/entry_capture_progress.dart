import 'dart:convert';

/// Fixed process-output prefix; no profile or exception text follows it.
const String entryEffectTracePrefix = 'SYRIUS_ENTRY_EFFECT:';

/// Maximum observations emitted by one original native process.
const int entryEffectTraceMaxEvents = 384;

/// Diagnostic output stays below the existing process-output cap.
const int entryEffectTraceMaxBytes = 98304;

const List<(String, String)> _entryTraceScenes = <(String, String)>[
  ('welcome', 'dark'), ('welcome', 'light'),
  ('import', 'dark'), ('import', 'light'),
];

const Set<String> _entryEffectPhases = <String>{
  'original-entry-artwork-ready',
  'original-image-release',
  'original-import-controller-end',
  'original-import-navigation-end',
  'original-import-route-end',
  'original-incomplete-import-input',
  'original-native-frame',
  'original-png-encoding',
  'original-renderer-image',
  'original-restored-window-position',
  'original-restored-window-size',
  'original-restored-window-visibility',
  'original-route-frame',
  'original-route-transition',
  'original-theme-flush',
  'original-theme-frame',
  'original-theme-write',
  'original-welcome-import',
  'original-window-position',
  'original-window-size',
  'original-window-visibility',
};

/// Copies only fixed original-effect observations, without invoking an owner.
Map<String, Object?>? projectEntryEffectTrace(Map<String, Object?> value) {
  const Set<String> fields = <String>{
    'schema', 'screen', 'theme', 'scopes', 'effects', 'phase',
    'boundary', 'future', 'failed', 'milliseconds',
  };
  final Object? schema = value['schema'];
  final Object? screen = value['screen'];
  final Object? theme = value['theme'];
  final Object? scopes = value['scopes'];
  final Object? effects = value['effects'];
  final Object? phase = value['phase'];
  final Object? boundary = value['boundary'];
  final Object? future = value['future'];
  final Object? failed = value['failed'];
  final Object? milliseconds = value['milliseconds'];
  if (value.length != fields.length || !value.keys.every(fields.contains) ||
      schema is! int || schema != 1 ||
      screen is! String || !<String>{'welcome', 'import'}.contains(screen) ||
      theme is! String || !<String>{'dark', 'light'}.contains(theme) ||
      scopes is! int || scopes < 1 || scopes > 4 ||
      (screen, theme) != _entryTraceScenes[scopes - 1] ||
      effects is! int || effects < 1 || effects > 192 ||
      phase is! String || !_entryEffectPhases.contains(phase) ||
      boundary is! String ||
      !<String>{'begin', 'returned', 'ended'}.contains(boundary) ||
      future is! String || !<String>{
        'not_returned', 'pending', 'succeeded', 'failed',
      }.contains(future) || failed is! bool ||
      milliseconds is! int || milliseconds < 0 ||
      milliseconds > 0x7fffffff ||
      boundary == 'begin' && (future != 'not_returned' || failed) ||
      boundary == 'returned' && (future == 'not_returned' || failed) ||
      boundary == 'ended' && future == 'not_returned' && !failed) {
    return null;
  }
  return Map<String, Object?>.unmodifiable(<String, Object?>{
    for (final String field in fields) field: value[field],
  });
}

/// Writes bounded fixed observations without replacing an original outcome.
final class EntryEffectTraceEmitter {
  /// The native host supplies its existing blocking stdout sink.
  EntryEffectTraceEmitter(this._write);

  final void Function(String) _write;
  int _events = 0;
  int _bytes = 0;
  bool _closed = false;

  /// Invalid observations and failed output never invoke an application owner.
  void add(Map<String, Object?> value) {
    if (_closed) return;
    final Map<String, Object?>? fixed = projectEntryEffectTrace(value);
    if (fixed == null) return;
    final String line = '$entryEffectTracePrefix${jsonEncode(fixed)}';
    final int bytes = utf8.encode(line).length + 1;
    try {
      if (_events >= entryEffectTraceMaxEvents ||
          _bytes + bytes > entryEffectTraceMaxBytes) {
        _closed = true;
        _write('$entryEffectTracePrefix{"schema":1,"capped":true}');
        return;
      }
      // Reserve before a test sink can synchronously reenter this emitter.
      _events++;
      _bytes += bytes;
      _write(line);
    } on Object {
      // Diagnostic output cannot replace an original effect or its failure.
      _closed = true;
    }
  }
}

/// Projects existing receipts and elapsed effects without invoking an owner.
/// Invalid or private fields cannot become a partially accepted observation.
Map<String, Object?>? projectEntryCaptureProgress({
  required String screen,
  required String theme,
  required int scopes,
  required int completedCaptures,
  required List<Map<String, Object?>> effects,
  required int artworkCount,
  required bool imageCreated,
  required bool restoring,
  required bool restored,
  required bool held,
}) {
  if (!<String>{'welcome', 'import'}.contains(screen) ||
      !<String>{'dark', 'light'}.contains(theme) ||
      scopes < 1 || scopes > 16 ||
      completedCaptures < 0 || completedCaptures > scopes ||
      effects.length > 192 || artworkCount < 0 || artworkCount > 2) {
    return null;
  }
  const Set<String> fields = <String>{
    'phase', 'future', 'failed', 'milliseconds',
  };
  final List<Map<String, Object?>> fixed = <Map<String, Object?>>[];
  Map<String, Object?>? slowest;
  int largest = -1;
  for (final Map<String, Object?> effect in effects) {
    final Object? phase = effect['phase'];
    final Object? future = effect['future'];
    final Object? failed = effect['failed'];
    final Object? milliseconds = effect['milliseconds'];
    if (effect.length != fields.length ||
        !effect.keys.every(fields.contains) ||
        phase is! String || !_entryEffectPhases.contains(phase) ||
        future is! String || !<String>{
          'not_returned', 'pending', 'succeeded', 'failed',
        }.contains(future) || failed is! bool ||
        milliseconds is! int || milliseconds < 0 ||
        milliseconds > 0x7fffffff) {
      return null;
    }
    final Map<String, Object?> value = Map<String, Object?>.unmodifiable(
      <String, Object?>{
        'phase': phase, 'future': future, 'failed': failed,
        'milliseconds': milliseconds,
      },
    );
    fixed.add(value);
    if (milliseconds > largest) {
      largest = milliseconds;
      slowest = value;
    }
  }
  return Map<String, Object?>.unmodifiable(<String, Object?>{
    'schema': 1, 'screen': screen, 'theme': theme,
    'scopes': scopes, 'completedCaptures': completedCaptures,
    'effects': fixed.length, 'last': fixed.isEmpty ? null : fixed.last,
    'slowest': slowest, 'artworkCount': artworkCount,
    'imageCreated': imageCreated, 'restoring': restoring,
    'restored': restored, 'held': held,
  });
}
