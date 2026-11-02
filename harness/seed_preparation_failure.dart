import 'dart:async' as futures;

import 'app/fixtures/seed_policy.dart';

/// Only fixed observations from an original preparation may leave the agent.
const Set<String> seedPreparationUiFailureCodes = <String>{
  'seed-preparation-error-widget',
  'seed-preparation-target-covered',
  'seed-preparation-target-disabled',
  'seed-preparation-target-missing',
};

/// Reads an existing source-defined label without formatting private detail.
String? seedPreparationUiFailureCode(Object? message) {
  if (message is! String) return null;
  return switch (message) {
    'nothing matches' => 'seed-preparation-target-missing',
    'disabled' => 'seed-preparation-target-disabled',
    'covered by something else' || 'assert target is covered' =>
      'seed-preparation-target-covered',
    'error widget on screen' => 'seed-preparation-error-widget',
    _ => null,
  };
}

/// Calls the original once and preserves its result and every existing guard.
/// A failed preparation can expose a finite label without new input authority.
futures.Future<T> observeSeedPreparation<T>({
  required bool preparation,
  required futures.Future<T> Function() original,
  required Object? Function(Object) classify,
}) async {
  try {
    return await original();
  } on Object catch (error) {
    if (!preparation || error is SeedRefused) rethrow;
    Object? label;
    try {
      label = classify(error);
    } on Object {
      label = null;
    }
    if (label is String && seedPreparationUiFailureCodes.contains(label)) {
      throw SeedRefused(label);
    }
    rethrow;
  }
}
