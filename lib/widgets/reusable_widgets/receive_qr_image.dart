import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as path;
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:share_plus/share_plus.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/color_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Rasterizes one exact QR request for the existing image exports.
typedef ReceiveQrEncoder =
    Future<Uint8List?> Function(
      QrImage image,
      PrettyQrDecoration decoration,
      int size,
    );

/// A request QR with the existing Share and Save operations.
class ReceiveQrImage extends StatefulWidget {
  /// Creates the image. Tests may replace rasterization and native exports.
  const ReceiveQrImage({
    required this.data,
    required this.size,
    required this.tokenStandard,
    this.enabled = true,
    this.isRequestCurrent,
    this.onShareImage,
    this.onSaveImage,
    this.encodeImage,
    super.key,
  });

  /// The exact legacy request encoded in the image.
  final String data;

  /// The square image's logical size before its surrounding controls.
  final double size;

  /// Selects the existing native-coin mark's token color.
  final TokenStandard tokenStandard;

  /// A closing panel keeps its paint while refusing further exports.
  final bool enabled;

  /// Synchronously checks ownership at admission and native dispatch.
  /// An edited form can revoke this image before its next widget rebuild.
  final bool Function()? isRequestCurrent;

  /// Replaces native sharing of the generated PNG bytes.
  final Future<void> Function(Uint8List)? onShareImage;

  /// Replaces the existing cached-PNG save and open behavior.
  final Future<void> Function(Uint8List)? onSaveImage;

  /// Replaces image encoding without replacing the QR payload.
  final ReceiveQrEncoder? encodeImage;

  @override
  State<ReceiveQrImage> createState() => _ReceiveQrImageState();
}

class _ReceiveQrImageState extends State<ReceiveQrImage> {
  String? _cachedData;
  QrImage? _cachedImage;
  bool _exporting = false;
  bool _exportFailed = false;
  int _attempt = 0;

  QrImage _imageFor(String data) {
    if (_cachedData == data && _cachedImage != null) return _cachedImage!;
    final QrImage image = QrImage(
      QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M),
    );
    _cachedData = data;
    _cachedImage = image;
    return image;
  }

  @override
  void didUpdateWidget(ReceiveQrImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool dataChanged = oldWidget.data != widget.data;
    if (dataChanged || oldWidget.enabled != widget.enabled) {
      // An encoder may finish after an edited request has replaced its
      // image. Such bytes must never reach a native export callback.
      _attempt += 1;
      _exporting = false;
      _exportFailed = false;
      if (dataChanged) {
        _cachedData = null;
        _cachedImage = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    QrImage? image;
    PrettyQrDecoration? decoration;
    try {
      image = _imageFor(widget.data);
      decoration = PrettyQrDecoration(
        shape: PrettyQrSmoothSymbol(color: tokens.foreground, roundFactor: 0),
        image: PrettyQrDecorationImage(
          colorFilter: ColorFilter.mode(
            ColorUtils.getTokenColor(widget.tokenStandard),
            BlendMode.srcIn,
          ),
          image: const AssetImage(
            'assets/images/qr_code_child_image_znn_cut.png',
          ),
          fit: BoxFit.contain,
        ),
      );
    } on Object catch (_) {
      image = null;
    }
    final QrImage? qrImage = image;
    final PrettyQrDecoration? qrDecoration = decoration;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Tooltip(
          key: const Key('receive_qr_payload'),
          message: widget.data,
          child: SizedBox.square(
            dimension: widget.size,
            child: qrImage == null || qrDecoration == null
                ? _buildError(context.l10n.receiveQrFailedError, tokens)
                : RepaintBoundary(
                    child: PrettyQrView(
                      qrImage: qrImage,
                      decoration: qrDecoration,
                    ),
                  ),
          ),
        ),
        if (qrImage != null && qrDecoration != null) ...<Widget>[
          SizedBox(height: tokens.receiveFieldGap),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: tokens.receiveMicroGap,
            runSpacing: tokens.receiveMicroGap,
            children: <Widget>[
              TextButton.icon(
                key: const Key('receive_share_image'),
                style: TextButton.styleFrom(
                  foregroundColor: tokens.dim,
                  backgroundColor: Colors.transparent,
                  textStyle: tokens.captionText,
                  minimumSize: Size(0, tokens.smallButtonHeight),
                  padding: EdgeInsetsDirectional.symmetric(
                    horizontal: tokens.receiveMicroGap,
                  ),
                ),
                onPressed: _exporting || !widget.enabled
                    ? null
                    : () => unawaited(
                        _export(
                          image: qrImage,
                          decoration: qrDecoration,
                          action: widget.onShareImage ?? _shareImage,
                        ),
                      ),
                icon: Icon(Icons.share_rounded, size: tokens.heroCopyIconSize),
                label: Text(context.l10n.receiveShareImage),
              ),
              TextButton.icon(
                key: const Key('receive_save_image'),
                style: TextButton.styleFrom(
                  foregroundColor: tokens.dim,
                  backgroundColor: Colors.transparent,
                  textStyle: tokens.captionText,
                  minimumSize: Size(0, tokens.smallButtonHeight),
                  padding: EdgeInsetsDirectional.symmetric(
                    horizontal: tokens.receiveMicroGap,
                  ),
                ),
                onPressed: _exporting || !widget.enabled
                    ? null
                    : () => unawaited(
                        _export(
                          image: qrImage,
                          decoration: qrDecoration,
                          action: widget.onSaveImage ?? _saveImage,
                        ),
                      ),
                icon: Icon(
                  Icons.save_alt_rounded,
                  size: tokens.heroCopyIconSize,
                ),
                label: Text(context.l10n.saveQr),
              ),
            ],
          ),
        ],
        if (_exportFailed) ...<Widget>[
          SizedBox(height: tokens.receiveMicroGap),
          _buildError(context.l10n.receiveExportFailed, tokens),
        ],
      ],
    );
  }

  Widget _buildError(String message, AppTokens tokens) => Semantics(
    liveRegion: true,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(Icons.error_outline_rounded, color: tokens.error),
        SizedBox(height: tokens.receiveMicroGap),
        Text(
          message,
          textAlign: TextAlign.center,
          style: tokens.captionText.copyWith(color: tokens.error),
        ),
      ],
    ),
  );

  Future<void> _export({
    required QrImage image,
    required PrettyQrDecoration decoration,
    required Future<void> Function(Uint8List) action,
  }) async {
    final bool Function()? isCurrent = widget.isRequestCurrent;
    if (_exporting || !widget.enabled || !(isCurrent?.call() ?? true)) return;
    final int attempt = ++_attempt;
    setState(() {
      _exporting = true;
      _exportFailed = false;
    });
    try {
      final Uint8List? bytes = await (widget.encodeImage ?? _encodeImage)(
        image,
        decoration,
        widget.size.toInt(),
      );
      if (!mounted ||
          !widget.enabled ||
          attempt != _attempt ||
          !(isCurrent?.call() ?? true)) {
        return;
      }
      if (bytes == null || bytes.isEmpty) {
        setState(() => _exportFailed = true);
        return;
      }
      await action(bytes);
    } on Object catch (_) {
      if (mounted && attempt == _attempt && (isCurrent?.call() ?? true)) {
        setState(() => _exportFailed = true);
      }
    } finally {
      if (mounted && attempt == _attempt) {
        setState(() => _exporting = false);
      }
    }
  }

  static Future<Uint8List?> _encodeImage(
    QrImage image,
    PrettyQrDecoration decoration,
    int size,
  ) async {
    final ByteData? data = await image.toImageAsBytes(
      size: size,
      decoration: decoration,
    );
    if (data == null) return null;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  static Future<File> _writeImage(Uint8List bytes) async {
    final String name = DateTime.now().microsecondsSinceEpoch.toString();
    final File file = await File(
      '${znnDefaultPaths.cache.path}${path.separator}$name.png',
    ).create();
    await file.writeAsBytes(bytes);
    return file;
  }

  static Future<void> _saveImage(Uint8List bytes) async {
    final File file = await _writeImage(bytes);
    await OpenFilex.open(file.path);
  }

  static Future<void> _shareImage(Uint8List bytes) async {
    final File file = await _writeImage(bytes);
    await SharePlus.instance.share(
      ShareParams(files: <XFile>[XFile(file.path)]),
    );
  }
}
