import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:window_manager/window_manager.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/services/i_web3wallet_service.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/apps_settings_presenter.dart';
import 'package:zxing2/qrcode.dart';

/// The existing native capturer; screenshots remain ephemeral in memory.
final ScreenCapturer screenCapturer = ScreenCapturer.instance;

/// Screen QR bytes stay in memory and are never cached on disk.
class WalletConnectQrCard extends StatefulWidget {
  /// Captures one region and admits only a strictly parsed pairing link.
  const WalletConnectQrCard({
    this.onPair,
    this.isCurrent,
    this.capture,
    super.key,
  });

  /// The original pairing admission, or the captured production client path.
  final AppsPairAdmission? onPair;

  /// Whether the original parent section still owns capture and display.
  final bool Function()? isCurrent;

  /// Optional in-memory capture for finite fixtures, without native screen use.
  final Future<Uint8List?> Function()? capture;

  @override
  State<WalletConnectQrCard> createState() => _WalletConnectQrCardState();
}

class _WalletConnectQrCardState extends State<WalletConnectQrCard> {
  bool _busy = false;
  bool _failed = false;
  bool _permission = false;
  int _epoch = 0;

  bool get _current =>
      mounted &&
      (widget.isCurrent?.call() ?? true) &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  Future<void> _scan() async {
    if (!_current || _busy) return;
    final int epoch = _epoch;
    bool revoked = false;
    bool owns() => !revoked && !(revoked = !_current || epoch != _epoch);
    final AppsPairAdmission? injected = widget.onPair;
    final ScreenCapturer capturer = screenCapturer;
    final WindowManager window = windowManager;
    final Future<Uint8List?> Function()? capture = widget.capture;
    setState(() {
      _busy = true;
      _failed = false;
      _permission = false;
    });
    try {
      final Web3WalletActions? original = injected == null
          ? (app.sl<IWeb3WalletService>() as CapturedWeb3WalletService)
                .captureActions()
          : null;
      Uint8List? bytes;
      if (capture != null) {
        bytes = await capture();
      } else {
        if (Platform.isMacOS && !await capturer.isAccessAllowed()) {
          if (!owns()) return;
          await capturer.requestAccess();
          if (owns()) setState(() => _permission = true);
          return;
        }
        if (!owns()) return;
        await window.minimize();
        if (!owns()) return;
        try {
          final CapturedData? data = await capturer.capture();
          bytes = data?.imageBytes;
        } finally {
          if (owns()) await window.show();
        }
      }
      if (!owns() || bytes == null) return;
      if (bytes.length > 32 * 1024 * 1024) {
        throw const FormatException('Invalid QR code');
      }
      final img.Image? image = img.decodeImage(bytes);
      if (image == null || image.width * image.height > 16000000) {
        throw const FormatException('Invalid QR code');
      }
      final Int32List pixels = Int32List(image.width * image.height);
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          final img.Pixel pixel = image.getPixel(x, y);
          pixels[y * image.width + x] =
              (pixel.r.toInt() << 16) |
              (pixel.g.toInt() << 8) |
              pixel.b.toInt();
        }
      }
      final BinaryBitmap bitmap = BinaryBitmap(
        HybridBinarizer(
          RGBLuminanceSource(image.width, image.height, pixels),
        ),
      );
      final Result result = QRCodeReader().decode(bitmap);
      final Uri? uri = parseWalletConnectLink(result.text);
      if (uri == null) throw const FormatException('Invalid QR code');
      if (!owns()) return;
      if (injected != null) {
        await injected(uri, owns);
      } else {
        await original!.pair(uri);
      }
    } on Object {
      if (owns()) setState(() => _failed = true);
    } finally {
      // A revoked capture cannot paint a result, but its actual settlement
      // releases the original busy slot for a still-mounted input owner.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final int epoch = _epoch;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        OutlinedButton.icon(
          key: const Key('wc_scan_screen'),
          onPressed: _current && !_busy
              ? () {
                  if (_current && epoch == _epoch) unawaited(_scan());
                }
              : null,
          icon: const Icon(Icons.qr_code_scanner, size: 16),
          label: Text(context.l10n.appsSettingsScanScreen),
        ),
        if (_failed || _permission)
          Text(
            _permission
                ? context.l10n.appsSettingsScreenPermission
                : context.l10n.appsSettingsInvalidQr,
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }

  @override
  void didUpdateWidget(WalletConnectQrCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.onPair, widget.onPair) ||
        !identical(oldWidget.isCurrent, widget.isCurrent) ||
        !identical(oldWidget.capture, widget.capture)) {
      _epoch++;
    }
  }

  @override
  void dispose() {
    _epoch++;
    super.dispose();
  }
}
