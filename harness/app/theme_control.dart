import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/app_theme_notifier.dart';

/// Uses the same notifier and preference as Display. Only the harness imports
/// this controller; an ordinary wallet build has no remote theme controls.
class HarnessThemeControl {
  const HarnessThemeControl({
    required this.context,
    required this.readPreference,
    required this.savePreference,
    required this.settle,
  });

  final BuildContext Function() context;
  final Object? Function() readPreference;
  final Future<void> Function(Object?) savePreference;
  final Future<void> Function() settle;

  AppThemeNotifier get _notifier =>
      Provider.of<AppThemeNotifier>(context(), listen: false);

  Map<String, Object?> snapshot() => <String, Object?>{
    'mode': _notifier.currentThemeMode?.name,
    'savedMode': readPreference(),
    'brightness': Theme.of(context()).brightness.name,
  };

  Future<Map<String, Object?>> change(String mode) async {
    final ThemeMode selected = switch (mode) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => throw ArgumentError('theme must be dark or light'),
    };
    await savePreference(selected.toString());
    _notifier.changeThemeMode(selected);
    await settle();
    final Map<String, Object?> result = snapshot();
    if (result['brightness'] != mode ||
        result['savedMode'] != selected.toString() ||
        result['mode'] != mode) {
      throw StateError('the requested theme was not observed');
    }
    return result;
  }

  Future<Map<String, Object?>> restore(Map<String, dynamic> state) async {
    final Object? mode = state['mode'];
    final ThemeMode? selected = switch (mode) {
      null => null,
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => throw ArgumentError('invalid original theme mode'),
    };
    final Object? saved = state['savedMode'];
    if (saved != null && saved is! String) {
      throw ArgumentError('invalid original theme preference');
    }
    // An absent preference reads as null too; both select the app default on
    // its next initialization. No theme preference is inferred from the OS.
    await savePreference(saved);
    _notifier.changeThemeMode(selected);
    await settle();
    final Map<String, Object?> result = snapshot();
    if (result['mode'] != mode || result['savedMode'] != saved) {
      throw StateError('the original theme was not restored');
    }
    return result;
  }
}
