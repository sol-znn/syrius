import 'dart:async';

import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/wallet_settings_binding.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/wallet_settings_presenter.dart';

class PendingPreferenceWrite {
  PendingPreferenceWrite(this.preference, this.finish, {required this.value});

  final WalletPreference preference;
  final bool value;
  final void Function() finish;
  final Completer<void> reply = Completer<void>();

  void complete() {
    finish();
    reply.complete();
  }
}

class MemoryPreferenceStore implements WalletPreferenceStore {
  final Object owner = Object();
  final Map<String, Object?> entries = <String, Object?>{};
  final List<PendingPreferenceWrite> writes = <PendingPreferenceWrite>[];
  bool deferred = false;

  @override
  Object get identity => owner;

  @override
  WalletStoredPreference read(WalletPreference preference) =>
      WalletStoredPreference(
        exists: entries.containsKey(preference.key),
        value: entries[preference.key],
      );

  @override
  Future<void> write(WalletPreference preference, {required bool value}) {
    final PendingPreferenceWrite write = PendingPreferenceWrite(
      preference,
      () => entries[preference.key] = value,
      value: value,
    );
    writes.add(write);
    if (!deferred) {
      write.complete();
    }
    return write.reply.future;
  }
}

class WalletSettingsFixture {
  final MemoryPreferenceStore store = MemoryPreferenceStore();
  final List<(WalletPreference, bool)> effects = <(WalletPreference, bool)>[];
  final List<(WalletPreference, bool)> notices = <(WalletPreference, bool)>[];
  Object wallet = Object();
  Object preferences = Object();
  Object box = Object();
  Object client = Object();
  Object sender = Object();
  String node = 'fixture-node';
  String path = 'fixture-wallet';
  int revision = 0;
  int chain = 321;
  bool ready = true;
  bool visible = true;
  int viewEpoch = 0;
  Future<Object?> Function()? effect;
  Object? noticeError;

  bool Function() captureView() {
    final int epoch = viewEpoch;
    return () => visible && epoch == viewEpoch;
  }

  void leaveAndReturn() {
    visible = false;
    viewEpoch++;
    visible = true;
  }

  WalletSettingsBinding bind() {
    final WalletSettingsResources resources = WalletSettingsResources(
      identities: () => <Object?>[wallet, preferences, box, client, sender],
      values: () => <Object?>[revision, chain, node, path],
      ready: () => ready,
    );
    return WalletSettingsBinding(
      store: store,
      ownsResources: () => resources.isCurrent,
      apply:
          (
            WalletPreference preference, {
            required bool value,
            required bool Function() ownsResources,
          }) {
            final bool Function() owns = ownsResources;
            if (!owns()) {
              return Future<Object?>.value(false);
            }
            effects.add((preference, value));
            return effect?.call() ?? Future<Object?>.value(true);
          },
      notify:
          (
            WalletPreference preference, {
            required bool value,
            required bool Function() canDisplay,
          }) async {
            if (!canDisplay()) {
              return;
            }
            final Object? error = noticeError;
            if (error != null) {
              Error.throwWithStackTrace(error, StackTrace.current);
            }
            notices.add((preference, value));
          },
    );
  }
}
