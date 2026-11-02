import 'dart:async';
import 'dart:io';

import 'package:ai_barcode_scanner/ai_barcode_scanner.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/services/i_web3wallet_service.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/apps_settings_presenter.dart';

/// The existing macOS camera flow only pairs its strictly selected barcode.
class WalletConnectCameraCard extends StatefulWidget {
  /// Keeps camera input tied to one section and its captured pairing admission.
  const WalletConnectCameraCard({this.onPair, this.isCurrent, super.key});

  /// Admits a selected barcode to the original pairing owner.
  final AppsPairAdmission? onPair;

  /// Whether the original parent section still owns this input.
  final bool Function()? isCurrent;

  @override
  State<WalletConnectCameraCard> createState() =>
      _WalletConnectCameraCardState();
}

class _WalletConnectCameraCardState extends State<WalletConnectCameraCard> {
  bool _busy = false;
  int _epoch = 0;
  Route<void>? _ownedRoute;
  NavigatorState? _navigator;

  bool get _current => mounted && (widget.isCurrent?.call() ?? true);

  Future<void> _scan() async {
    if (!_current || _busy) return;
    final int epoch = ++_epoch;
    final AppsPairAdmission? injected = widget.onPair;
    Web3WalletActions? original;
    try {
      if (injected == null) {
        original = (app.sl<IWeb3WalletService>() as CapturedWeb3WalletService)
            .captureActions();
      }
    } on Object {
      return;
    }
    final NavigatorState navigator = Navigator.of(context);
    final Web3WalletActions? originalClient = original;
    final MobileScannerController controller = MobileScannerController(
      facing: CameraFacing.front,
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
    bool pairing = false;
    Completer<void>? pairingSettled;
    bool revoked = false;
    late final MaterialPageRoute<void> route;
    bool owns() =>
        !revoked &&
        !(revoked =
            !_current ||
            epoch != _epoch ||
            !route.isCurrent ||
            !identical(_ownedRoute, route));
    Uri? selected(BarcodeCapture capture) => selectWalletConnectLink(
      capture.barcodes.map((Barcode barcode) => barcode.displayValue),
    );
    route = MaterialPageRoute<void>(
      builder: (BuildContext context) => AiBarcodeScanner(
        controller: controller,
        validator: (BarcodeCapture capture) => selected(capture) != null,
        onDetect: (BarcodeCapture capture) async {
          final Uri? uri = selected(capture);
          if (uri == null || pairing || !owns()) return;
          pairing = true;
          final Completer<void> originalPairing = Completer<void>();
          pairingSettled = originalPairing;
          try {
            if (injected != null) {
              await injected(uri, owns);
            } else {
              await originalClient!.pair(uri);
            }
            if (owns()) navigator.removeRoute(route);
          } on Object {
            // The original action journal owns the error. Never log QR data.
          } finally {
            pairing = false;
            originalPairing.complete();
          }
        },
        errorBuilder: (BuildContext context, MobileScannerException error) =>
            Center(child: Text(context.l10n.appsSettingsInvalidQr)),
      ),
    );
    _ownedRoute = route;
    _navigator = navigator;
    setState(() => _busy = true);
    try {
      await navigator.push<void>(route);
    } finally {
      try {
        await route.completed;
        await controller.dispose();
      } finally {
        // Closing the scanner does not cancel the already admitted pairing.
        // Reserve before its callback so a synchronous pop cannot miss it.
        await pairingSettled?.future;
      }
      if (identical(_ownedRoute, route)) {
        _ownedRoute = null;
        _navigator = null;
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS) return const SizedBox.shrink();
    final int epoch = _epoch;
    return OutlinedButton.icon(
      key: const Key('wc_scan_camera'),
      onPressed: _current && !_busy
          ? () {
              if (_current && epoch == _epoch) unawaited(_scan());
            }
          : null,
      icon: const Icon(Icons.photo_camera_outlined, size: 16),
      label: Text(context.l10n.appsSettingsCamera),
    );
  }

  @override
  void didUpdateWidget(WalletConnectCameraCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.onPair, widget.onPair) ||
        !identical(oldWidget.isCurrent, widget.isCurrent)) {
      _epoch++;
    }
  }

  @override
  void dispose() {
    _epoch++;
    final Route<void>? route = _ownedRoute;
    final NavigatorState? navigator = _navigator;
    if (route != null && navigator != null) {
      scheduleMicrotask(() {
        if (navigator.mounted && route.isActive) navigator.removeRoute(route);
      });
    }
    super.dispose();
  }
}
