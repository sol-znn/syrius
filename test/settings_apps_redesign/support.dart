import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/apps_settings_presenter.dart';

final String validPairingLink =
    'wc:${List<String>.filled(64, 'a').join()}@2'
    '?relay-protocol=irn&symKey=${List<String>.filled(64, 'b').join()}';

class PendingIntent {
  PendingIntent(this.intent, this.entries);
  final AppsIntent intent;
  final Map<String, Object?> entries;
  final Completer<void> reply = Completer<void>();
  void complete() {
    entries['intent'] = intent.stored;
    reply.complete();
  }
}

/// All connection facts in this fixture are synthetic and have no transport.
class AppsFixture {
  Object box = Object();
  Object client = Object();
  int revision = 0;
  int viewEpoch = 0;
  bool ready = true;
  bool visible = true;
  bool enabled = true;
  bool deferredPersistence = false;
  bool Function()? resourceProof;
  Map<String, Object?> entries = <String, Object?>{};
  final List<PendingIntent> writes = <PendingIntent>[];
  final List<(AppsActionKind, Object?)> actions = <(AppsActionKind, Object?)>[];
  final StreamController<void> changes = StreamController<void>.broadcast(
    sync: true,
  );
  final ValueNotifier<String?> incoming = ValueNotifier<String?>(null);
  Future<dynamic> Function(AppsActionKind, Object?)? effect;
  final Completer<void> effectStarted = Completer<void>();
  List<AppsConnection> rows = <AppsConnection>[
    AppsConnection(
      identity: 'https://sample.example',
      incarnation: 'grant:1',
      kind: AppsConnectionKind.webApp,
      site: 'sample.example',
      accounts: const <String>['fixture-account'],
    ),
    AppsConnection(
      identity: 'fixture-session',
      incarnation: Object(),
      kind: AppsConnectionKind.walletConnect,
      site: 'Example app',
      url: 'https://app.example',
      pairingTopic: 'fixture-pairing',
      expiry: 2000000000,
      acknowledged: true,
      accounts: const <String>['zenon:321:fixture-account'],
    ),
  ];
  List<AppsPairing> pairings = <AppsPairing>[
    const AppsPairing(
      topic: 'fixture-pairing',
      incarnation: Object(),
      site: 'Example app',
      url: 'https://app.example',
      expiry: 2000000000,
      active: true,
    ),
  ];

  bool Function() captureView() {
    final int epoch = viewEpoch;
    return () => visible && epoch == viewEpoch;
  }

  void leaveAndReturn() {
    visible = false;
    viewEpoch++;
    visible = true;
  }

  AppsSnapshot snapshot() => AppsSnapshot(
    webAppsAvailable: true,
    walletConnectAvailable: true,
    enabled: enabled,
    port: enabled ? 35996 : null,
    connections: rows,
    pairings: pairings,
    labels: const <String, String>{
      'fixture-account': 'Address 1',
      'zenon:321:fixture-account': 'Address 1',
    },
  );

  AppsSettingsBinding bind() {
    final Object originalBox = box;
    final Object originalClient = client;
    final int originalRevision = revision;
    final Map<String, Object?> originalEntries = entries;
    Future<dynamic> act(
      AppsActionKind kind,
      Object? value,
      bool Function() owns,
    ) {
      if (!owns()) throw StateError('Original source unavailable');
      actions.add((kind, value));
      if (!effectStarted.isCompleted) effectStarted.complete();
      final Future<dynamic> Function(AppsActionKind, Object?)? handler = effect;
      if (handler != null) return handler(kind, value);
      switch (kind) {
        case AppsActionKind.webApps:
          enabled = value! as bool;
        case AppsActionKind.disconnect:
          rows = rows
              .where(
                (AppsConnection row) =>
                    !row.sameGrant(value! as AppsConnection),
              )
              .toList();
        case AppsActionKind.disconnectPairing:
          pairings = pairings
              .where(
                (AppsPairing row) => !row.samePairing(value! as AppsPairing),
              )
              .toList();
        case AppsActionKind.pair:
          break;
      }
      return Future<Object?>.value(value);
    }

    return AppsSettingsBinding(
      identity: originalBox,
      ownsResources: () =>
          ready &&
          identical(box, originalBox) &&
          identical(client, originalClient) &&
          revision == originalRevision &&
          (resourceProof?.call() ?? true),
      read: snapshot,
      changes: changes.stream,
      incomingLink: incoming,
      persist: (AppsIntent intent) {
        final PendingIntent pending = PendingIntent(intent, originalEntries);
        writes.add(pending);
        if (!deferredPersistence) pending.complete();
        return pending.reply.future;
      },
      setEnabled: ({required bool enabled, required bool Function() owns}) =>
          act(AppsActionKind.webApps, enabled, owns),
      disconnect: (AppsConnection row, bool Function() owns) =>
          act(AppsActionKind.disconnect, row, owns),
      disconnectPairing: (AppsPairing row, bool Function() owns) =>
          act(AppsActionKind.disconnectPairing, row, owns),
      pair: (Uri uri, bool Function() owns) =>
          act(AppsActionKind.pair, uri, owns),
    );
  }

  Future<void> close() async {
    incoming.dispose();
    await changes.close();
  }
}
