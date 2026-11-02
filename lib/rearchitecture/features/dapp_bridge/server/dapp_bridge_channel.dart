import 'dart:async';

import 'package:logging/logging.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/server/dapp_bridge_consent.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/server/dapp_bridge_link.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/server/dapp_bridge_server.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/server/dapp_bridge_service.dart';

/// The version of the handshake, sent in `syrius_hello`.
const int kDappBridgeProtocol = 1;

/// What the wallet's own screens may do with the channel: the Settings
/// switch and the Connected sites list are written against this, so they are
/// tested without a socket.
abstract class DappBridgeControl {
  /// The app's channel, registered by `DappBridge` when the app creates it.
  /// The widgets reach it here rather than by importing the app.
  static DappBridgeControl? app;

  /// [app], or a clear failure when the app has not created its channel.
  static DappBridgeControl of() =>
      app ?? (throw StateError('The page-to-desktop channel is not created'));

  /// Whether the person has the channel on.
  bool get enabled;

  /// The port being listened on, or null when off or when none was free.
  int? get port;

  /// Saves the choice, then starts or stops listening.
  Future<void> setEnabled({required bool enabled});

  /// The connected requesters.
  List<DappBridgeSite> get sites;

  /// Withdraws [requester]'s consent.
  Future<void> disconnect(String requester);

  /// Fires when [enabled], [port] or [sites] may have changed.
  Stream<void> get changes;
}

/// Production actions can retain their original settings and grant receipts.
abstract interface class DappBridgeOwnedControl {
  /// The persisted enablement state observed by this control.
  bool get enabled;

  /// Captures the exact preferences backend and queued effect admission.
  DappBridgeActions captureActions();
}

/// Captured settings and grant effects that never discover replacement Boxes.
class DappBridgeActions {
  /// Freezes the original backend identity and its fenced mutation closures.
  const DappBridgeActions({
    required this.identity,
    required this.isCurrent,
    required this.setEnabled,
    required this.disconnect,
  });

  /// The original preferences backend shared by this action boundary.
  final Object identity;

  /// Whether the captured preferences and channel still belong to this owner.
  final bool Function() isCurrent;

  /// Persists enablement before starting or stopping the original listener.
  final Future<void> Function({
    required bool enabled,
    required bool Function() owns,
  })
  setEnabled;

  /// Revokes only the captured requester incarnation while it remains owned.
  final Future<void> Function(DappBridgeSite, bool Function()) disconnect;
}

/// The page-to-desktop channel in one piece: the loopback server, the
/// `syrius://request` path, the service behind both, and the consent and the
/// on/off choice in a [DappBridgeStore].
///
/// It knows the wallet only as a [DappBridgeWallet], so the whole channel
/// runs in a test over a real socket with a fake wallet behind it.
class DappBridgeChannel implements DappBridgeControl, DappBridgeOwnedControl {
  /// Creates a channel over [wallet] that keeps its settings in [store].
  /// [open] opens a URL in the browser, for a link's answer.
  DappBridgeChannel({
    required DappBridgeWallet wallet,
    required DappBridgeStore store,
    required Future<void> Function(Uri url) open,
    this._ports = kDappBridgePorts,
    Duration watch = const Duration(seconds: 1),
    DateTime Function() now = DateTime.now,
  }) : _store = store,
       _watchEvery = watch,
       _consent = DappBridgeConsentStore(store) {
    _service = DappBridgeService(wallet: wallet, consent: _consent, now: now);
    _links = DappBridgeLinks(handler: _service.handle, open: open);
    _consentChanges = _consent.changes.listen((_) => _notify());
  }

  final DappBridgeStore _store;
  final List<int> _ports;
  final Duration _watchEvery;
  final DappBridgeConsentStore _consent;
  late final DappBridgeService _service;
  late final DappBridgeLinks _links;
  late final StreamSubscription<void> _consentChanges;
  final Logger _logger = Logger('DappBridge');
  final StreamController<void> _changes = StreamController<void>.broadcast();
  DappBridgeServer? _server;
  Timer? _watch;
  Future<void> _turn = Future<void>.value();

  @override
  bool get enabled => _store.read(kDappBridgeEnabledKey) != false;

  @override
  int? get port => _server?.port;

  @override
  List<DappBridgeSite> get sites => _consent.sites;

  @override
  Stream<void> get changes => _changes.stream;

  /// Starts listening, unless the person has turned the channel off.
  Future<void> start() => _inTurn(_start);

  /// Stops listening and closes every page's socket.
  Future<void> stop() => _inTurn(_stop);

  @override
  Future<void> setEnabled({required bool enabled}) =>
      captureActions().setEnabled(enabled: enabled, owns: () => true);

  @override
  DappBridgeActions captureActions() {
    final DappBridgeStore store = _store.capture();
    bool current() => store.isCurrent;
    return DappBridgeActions(
      identity: store.identity,
      isCurrent: current,
      setEnabled: ({required bool enabled, required bool Function() owns}) =>
          _inTurn(() async {
            if (!current() || !owns()) throw StateError('Setting unavailable');
            await store.write(kDappBridgeEnabledKey, enabled);
            if (!current() || !owns()) {
              throw StateError('Setting effect unavailable');
            }
            if (enabled) {
              await _start(isCurrent: () => current() && owns());
            } else {
              await _stop();
            }
          }),
      disconnect: (DappBridgeSite site, bool Function() owns) {
        if (!current() || !owns()) throw StateError('Connection unavailable');
        final DappBridgeConsentReceipt receipt = _consent.captureSite(site);
        return _service.revokeReceipt(
          site.requester,
          receipt,
          isCurrent: () => current() && owns(),
        );
      },
    );
  }

  @override
  Future<void> disconnect(String requester) => _service.revoke(requester);

  /// To be called when the selected address changes, the wallet locks or
  /// unlocks, or the node or chain changes. The channel also looks for
  /// itself every second, so a call that is missed costs a second, not an
  /// event.
  void walletChanged() {
    final DappBridgeServer? server = _server;
    if (server != null) {
      _service.walletChanged(server.origins);
    }
  }

  /// Takes a `syrius://request` link. Completes with true once the answer
  /// has been opened. A link that does not parse, or that arrives while the
  /// channel is off, gets no answer.
  Future<bool> handleLink(Uri link) =>
      enabled ? _links.handle(link) : Future<bool>.value(false);

  /// Stops and releases the channel.
  Future<void> close() async {
    await stop();
    await _consentChanges.cancel();
    await _consent.close();
    await _changes.close();
  }

  /// Start and stop one after the other. Two starts at once would each bind
  /// a port.
  Future<void> _inTurn(Future<void> Function() run) {
    final Future<void> next = _turn.then((_) => run());
    _turn = next.catchError((Object _) {});
    return next.whenComplete(_notify);
  }

  Future<void> _start({bool Function()? isCurrent}) async {
    if (!(isCurrent?.call() ?? true)) return;
    if (_server != null || !enabled) {
      return;
    }
    final DappBridgeServer server = DappBridgeServer(
      handler: _service.handle,
      ports: _ports,
      // Said to any page that reaches the socket, before any consent, so it
      // says nothing about this wallet: not an address, not whether it is
      // locked.
      hello: () => <String, Object?>{
        'wallet': 'syrius-desktop',
        'protocol': kDappBridgeProtocol,
      },
      // Records what a new page sees now, so the next change is a change.
      onOpen: (_) => walletChanged(),
    );
    final int? bound = await server.start();
    if (!(isCurrent?.call() ?? true)) {
      await server.stop();
      throw StateError('Setting effect unavailable');
    }
    if (bound == null) {
      _logger.warning('no free port');
      return;
    }
    _logger.info('listening on $bound');
    _service.emit = server.emit;
    _server = server;
    _watch = Timer.periodic(_watchEvery, (_) => walletChanged());
  }

  Future<void> _stop() async {
    _watch?.cancel();
    _watch = null;
    final DappBridgeServer? server = _server;
    _server = null;
    _service.emit = null;
    await server?.stop();
  }

  void _notify() {
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }
}
