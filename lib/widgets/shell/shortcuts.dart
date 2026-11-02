import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/rail.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/tabs.dart';

/// Shows a page: a rail page by its number, or the lock.
class OpenPageIntent extends Intent {
  /// Creates the intent for [tab].
  const OpenPageIntent(this.tab);

  /// The page to show.
  final Tabs tab;
}

/// Opens the "Go to" palette.
class OpenGoToIntent extends Intent {
  /// Creates the intent.
  const OpenGoToIntent();
}

/// Opens the rail if it is collapsed, collapses it if it is open.
class ToggleRailIntent extends Intent {
  /// Creates the intent.
  const ToggleRailIntent();
}

/// Refreshes only the active page's existing reads.
class RefreshPageIntent extends Intent {
  /// Creates the refresh intent.
  const RefreshPageIntent();
}

/// Changes the shared balance visibility choice.
class ToggleBalancesIntent extends Intent {
  /// Creates the visibility intent.
  const ToggleBalancesIntent();
}

/// Replays the lock well without unlocking or navigating.
class ReplayLockIntent extends Intent {
  /// Creates the lock animation intent.
  const ReplayLockIntent();
}

/// Whether the chord key is Cmd. On macOS Ctrl with a letter edits text
/// (Ctrl+K kills to the end of the line), and Cmd is where a Mac user looks
/// for an application's shortcuts.
bool get _kChordIsMeta => defaultTargetPlatform == TargetPlatform.macOS;

/// The chord key's name, for the hints in the palette.
String get kChordName => _kChordIsMeta ? 'Cmd' : 'Ctrl';

/// [key] with the chord key and nothing else held.
SingleActivator _chord(LogicalKeyboardKey key) =>
    SingleActivator(key, control: !_kChordIsMeta, meta: _kChordIsMeta);

const List<LogicalKeyboardKey> _kDigitKeys = <LogicalKeyboardKey>[
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
];

const List<LogicalKeyboardKey> _kNumpadKeys = <LogicalKeyboardKey>[
  LogicalKeyboardKey.numpad1,
  LogicalKeyboardKey.numpad2,
  LogicalKeyboardKey.numpad3,
  LogicalKeyboardKey.numpad4,
  LogicalKeyboardKey.numpad5,
  LogicalKeyboardKey.numpad6,
  LogicalKeyboardKey.numpad7,
  LogicalKeyboardKey.numpad8,
];

/// The shell's bindings while the wallet is unlocked.
Map<ShortcutActivator, Intent> get kShellShortcuts =>
    <ShortcutActivator, Intent>{
      for (
        int i = 0;
        i < kRailPages.length && i < 8;
        i++
      ) ...<ShortcutActivator, Intent>{
        _chord(_kDigitKeys[i]): OpenPageIntent(kRailPages[i].tab),
        _chord(_kNumpadKeys[i]): OpenPageIntent(kRailPages[i].tab),
      },
      _chord(LogicalKeyboardKey.keyL): const OpenPageIntent(Tabs.lock),
      _chord(LogicalKeyboardKey.keyK): const OpenGoToIntent(),
      _chord(LogicalKeyboardKey.keyB): const ToggleRailIntent(),
      _chord(LogicalKeyboardKey.keyR): const RefreshPageIntent(),
      _chord(LogicalKeyboardKey.keyH): const ToggleBalancesIntent(),
      _chord(LogicalKeyboardKey.comma): const OpenPageIntent(Tabs.settings),
      const SingleActivator(LogicalKeyboardKey.escape): const DismissIntent(),
    };

/// The locked shell exposes only the animation's replay chord.
Map<ShortcutActivator, Intent> get kLockedShellShortcuts =>
    <ShortcutActivator, Intent>{
      _chord(LogicalKeyboardKey.keyL): const ReplayLockIntent(),
      const SingleActivator(LogicalKeyboardKey.escape):
          const DoNothingAndStopPropagationIntent(),
    };
