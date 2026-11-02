import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/security_settings_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/security_settings_rows.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/input_fields/input_field.dart';

/// Production may wrap explicit file inputs with its existing drop service.
typedef SecurityFileDropBuilder =
    Widget Function(
      Widget child,
      ValueChanged<String> onPath,
    );

/// Closed-group text and file actions with no default wallet or native input.
class SecurityCryptoPanel extends StatefulWidget {
  /// Every operation captures both its fields and its original session.
  const SecurityCryptoPanel({
    required this.signing,
    required this.capture,
    required this.isCurrent,
    this.fileDropBuilder,
    super.key,
  });

  /// True signs; false verifies an explicit signature and public key.
  final bool signing;

  /// Called once at admission, before any awaited input or signing.
  final SecurityCryptoSession? Function(bool Function() isCurrent) capture;

  /// Includes the exact expanded-group and section generation.
  final bool Function() isCurrent;

  /// Tests omit this adapter and never register a desktop drop listener.
  final SecurityFileDropBuilder? fileDropBuilder;

  @override
  State<SecurityCryptoPanel> createState() => _SecurityCryptoPanelState();
}

class _SecurityCryptoPanelState extends State<SecurityCryptoPanel> {
  final TextEditingController _message = TextEditingController();
  final TextEditingController _signature = TextEditingController();
  final TextEditingController _publicKey = TextEditingController();
  final TextEditingController _fileSignature = TextEditingController();
  final TextEditingController _filePublicKey = TextEditingController();
  bool _visible = true;
  bool _busy = false;
  int _epoch = 0;
  int _formEpoch = 0;
  String? _file;
  SecuritySignature? _textResult;
  SecuritySignature? _fileResult;
  String? _status;
  bool _verified = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of<void>(context)?.isCurrent ?? true);
    if (_visible != visible) {
      _visible = visible;
      _epoch++;
    }
  }

  @override
  void didUpdateWidget(SecurityCryptoPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.isCurrent, oldWidget.isCurrent) ||
        !identical(widget.capture, oldWidget.capture) ||
        widget.signing != oldWidget.signing) {
      _epoch++;
    }
  }

  bool Function() _capture({bool fields = true}) {
    final int epoch = _epoch;
    final int form = _formEpoch;
    final bool Function() external = widget.isCurrent;
    bool revoked = false;
    return () =>
        !revoked &&
        !(revoked =
            !mounted ||
            !_visible ||
            epoch != _epoch ||
            (fields && form != _formEpoch) ||
            !external());
  }

  Future<void> _run(
    bool Function() current,
    Future<void> Function(SecurityCryptoSession session) action,
  ) async {
    if (_busy || !current()) {
      return;
    }
    final String failed = widget.signing
        ? context.l10n.securitySettingsSignFailed
        : context.l10n.securitySettingsVerifyFailed;
    final SecurityCryptoSession? session = widget.capture(current);
    if (session == null || !session.isCurrent) {
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await action(session);
    } on Object {
      if (current() && session.isCurrent) {
        setState(() {
          _status = failed;
          _verified = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _sign(bool Function() current, {required bool file}) async {
    final String? originalFile = _file;
    final String message = _message.text;
    if (file ? originalFile == null : message.isEmpty || _textRefused) {
      return;
    }
    await _run(current, (SecurityCryptoSession session) async {
      final SecuritySignature result = file
          ? await session.signFile(originalFile!)
          : await session.signText(message);
      if (current() && session.isCurrent) {
        setState(() {
          if (file) {
            _fileResult = result;
          } else {
            _textResult = result;
          }
        });
      }
    });
  }

  Future<void> _verify(bool Function() current, {required bool file}) async {
    final String? originalFile = _file;
    final String message = _message.text;
    final String signature = file ? _fileSignature.text : _signature.text;
    final String publicKey = file ? _filePublicKey.text : _publicKey.text;
    if (signature.isEmpty ||
        publicKey.isEmpty ||
        (file ? originalFile == null : message.isEmpty || _textRefused)) {
      return;
    }
    final String success = file
        ? context.l10n.securitySettingsFileVerified
        : context.l10n.securitySettingsMessageVerified;
    final String invalid = file
        ? context.l10n.securitySettingsInvalidFileSignature
        : context.l10n.securitySettingsInvalidMessageSignature;
    await _run(current, (SecurityCryptoSession session) async {
      final bool verified = file
          ? await session.verifyFile(originalFile!, signature, publicKey)
          : await session.verifyText(message, signature, publicKey);
      if (current() && session.isCurrent) {
        setState(() {
          _verified = verified;
          _status = verified ? success : invalid;
        });
      }
    });
  }

  Future<void> _pick(bool Function() current) =>
      _run(current, (SecurityCryptoSession session) async {
        final String? selected = await session.pickFile();
        if (selected != null && current() && session.isCurrent) {
          setState(() {
            _file = selected;
            _fileResult = null;
            _formEpoch++;
          });
        }
      });

  Future<void> _paste(
    bool Function() current,
    TextEditingController controller,
  ) => _run(current, (SecurityCryptoSession session) async {
    final String? value = await session.paste();
    if (value != null && current() && session.isCurrent) {
      setState(() {
        controller.text = value;
        _formEpoch++;
      });
    }
  });

  Future<void> _copy(bool Function() current, String value) =>
      _run(current, (SecurityCryptoSession session) => session.copy(value));

  bool get _textRefused => utf8.encode(_message.text).length == 32;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final bool Function() current = _capture();
    final bool Function() edit = _capture(fields: false);
    final String prefix = widget.signing ? 'security_sign' : 'security_verify';
    void changed(String _) {
      if (edit() && !_busy) {
        setState(() {
          _formEpoch++;
          _textResult = null;
          _fileResult = null;
          _status = null;
        });
      }
    }

    final List<Widget> children = <Widget>[
      // The following File heading must not merge into the field's name.
      Semantics(
        container: true,
        child: InputField(
          key: Key('${prefix}_message'),
          controller: _message,
          hintText: context.l10n.securitySettingsMessage,
          enabled: !_busy,
          inputtedTextStyle: tokens.bodyText,
          onChanged: changed,
          errorText: _textRefused ? context.l10n.signMessage32BytesError : null,
          suffixIcon: !widget.signing ? _buildPaste(current, _message) : null,
        ),
      ),
      if (!widget.signing) ...<Widget>[
        SizedBox(height: tokens.cardGap),
        _buildIdentifier(
          '${prefix}_signature',
          _signature,
          context.l10n.securitySettingsSignature,
          current,
          changed,
        ),
        SizedBox(height: tokens.cardGap),
        _buildIdentifier(
          '${prefix}_public_key',
          _publicKey,
          context.l10n.securitySettingsPublicKey,
          current,
          changed,
        ),
      ],
      SizedBox(height: tokens.cardGap),
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: SecuritySettingsButton(
          key: Key('${prefix}_text'),
          label: widget.signing
              ? context.l10n.securitySettingsSign
              : context.l10n.securitySettingsVerify,
          onPressed:
              !_busy &&
                  _message.text.isNotEmpty &&
                  !_textRefused &&
                  (widget.signing ||
                      (_signature.text.isNotEmpty &&
                          _publicKey.text.isNotEmpty))
              ? () => unawaited(
                  widget.signing
                      ? _sign(current, file: false)
                      : _verify(current, file: false),
                )
              : null,
        ),
      ),
      if (_textResult != null) _buildResult(_textResult!, current),
      SizedBox(height: tokens.panelGap),
      Text(
        context.l10n.securitySettingsFile,
        style: tokens.securitySettingsLabelText,
      ),
      SizedBox(height: tokens.fieldLabelGap),
      _buildFile(prefix, current),
      if (!widget.signing) ...<Widget>[
        SizedBox(height: tokens.cardGap),
        _buildIdentifier(
          '${prefix}_file_signature',
          _fileSignature,
          context.l10n.securitySettingsFileSignature,
          current,
          changed,
        ),
        SizedBox(height: tokens.cardGap),
        _buildIdentifier(
          '${prefix}_file_public_key',
          _filePublicKey,
          context.l10n.securitySettingsPublicKey,
          current,
          changed,
        ),
      ],
      SizedBox(height: tokens.cardGap),
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: SecuritySettingsButton(
          key: Key('${prefix}_file'),
          label: widget.signing
              ? context.l10n.securitySettingsSignFile
              : context.l10n.securitySettingsVerifyFile,
          onPressed:
              !_busy &&
                  _file != null &&
                  (widget.signing ||
                      (_fileSignature.text.isNotEmpty &&
                          _filePublicKey.text.isNotEmpty))
              ? () => unawaited(
                  widget.signing
                      ? _sign(current, file: true)
                      : _verify(current, file: true),
                )
              : null,
        ),
      ),
      if (_fileResult != null) _buildResult(_fileResult!, current),
      if (_status != null) ...<Widget>[
        SizedBox(height: tokens.cardGap),
        Row(
          children: <Widget>[
            Icon(
              _verified ? Icons.check_circle_outline : Icons.error_outline,
              size: tokens.zapSmallGlyphSize,
              color: _verified ? tokens.znnInk : tokens.error,
            ),
            SizedBox(width: tokens.fieldLabelGap),
            Expanded(
              child: Text(
                _status!,
                key: Key('${prefix}_status'),
                style: tokens.bodyText.copyWith(
                  color: _verified ? tokens.znnInk : tokens.error,
                ),
              ),
            ),
          ],
        ),
      ],
    ];
    return Padding(
      padding: tokens.settingsRowPadding,
      child: FocusTraversalGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _buildPaste(bool Function() current, TextEditingController field) =>
      IconButton(
        tooltip: context.l10n.securitySettingsPaste,
        onPressed: _busy ? null : () => unawaited(_paste(current, field)),
        icon: const Icon(Icons.content_paste),
      );

  Widget _buildIdentifier(
    String key,
    TextEditingController controller,
    String label,
    bool Function() current,
    ValueChanged<String> changed,
  ) => InputField(
    key: Key(key),
    controller: controller,
    hintText: label,
    enabled: !_busy,
    onChanged: changed,
    inputtedTextStyle: AppTokens.of(context).dataText,
    textDirection: TextDirection.ltr,
    suffixIcon: _buildPaste(current, controller),
  );

  Widget _buildFile(String prefix, bool Function() current) {
    final AppTokens tokens = AppTokens.of(context);
    final String? file = _file;
    final Widget input = Align(
      alignment: AlignmentDirectional.centerStart,
      child: SecuritySettingsButton(
        key: Key('${prefix}_choose_file'),
        icon: Icons.upload_file_outlined,
        label: file == null ? context.l10n.selectFileHint : path.basename(file),
        data: file != null,
        onPressed: _busy ? null : () => unawaited(_pick(current)),
      ),
    );
    final Widget control = file == null
        ? input
        : Tooltip(
            message: file,
            child: DefaultTextStyle(style: tokens.dataText, child: input),
          );
    final SecurityFileDropBuilder? drop = widget.fileDropBuilder;
    return drop == null
        ? control
        : drop(control, (String path) {
            if (!_busy && current()) {
              setState(() {
                _file = path;
                _fileResult = null;
                _formEpoch++;
              });
            }
          });
  }

  Widget _buildResult(SecuritySignature result, bool Function() current) {
    final AppTokens tokens = AppTokens.of(context);
    Widget row(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(height: tokens.cardGap),
        Text(label, style: tokens.securitySettingsLabelText),
        Row(
          children: <Widget>[
            Expanded(
              child: Tooltip(
                message: value,
                child: Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: tokens.dataText,
                ),
              ),
            ),
            IconButton(
              tooltip: context.l10n.commonCopy,
              icon: const Icon(Icons.copy_outlined),
              onPressed: _busy ? null : () => unawaited(_copy(current, value)),
            ),
          ],
        ),
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        row(context.l10n.securitySettingsSignature, result.signature),
        row(context.l10n.securitySettingsPublicKey, result.publicKey),
      ],
    );
  }

  @override
  void dispose() {
    _epoch++;
    _message.dispose();
    _signature.dispose();
    _publicKey.dispose();
    _fileSignature.dispose();
    _filePublicKey.dispose();
    super.dispose();
  }
}
