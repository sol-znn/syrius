import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/services/i_web3wallet_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/apps_settings_presenter.dart';

/// The retained pairing-link field height used by the existing connection UI.
const double kWalletConnectFieldHeight = 44;

/// A pairing link is ephemeral input. It never enters logs or preferences.
class WalletConnectUriCard extends StatefulWidget {
  /// Owns ephemeral link input without logging or persisting its contents.
  const WalletConnectUriCard({
    this.onPair,
    this.isCurrent,
    this.incomingLink,
    super.key,
  });

  /// Admits the link to the original action boundary, after its durable intent.
  final AppsPairAdmission? onPair;

  /// Whether this original section can still accept input or show errors.
  final bool Function()? isCurrent;

  /// The captured application-link notifier; its value is consumed in memory.
  final ValueNotifier<String?>? incomingLink;

  @override
  State<WalletConnectUriCard> createState() => _WalletConnectUriCardState();
}

class _WalletConnectUriCardState extends State<WalletConnectUriCard> {
  final TextEditingController _input = TextEditingController();
  late ValueNotifier<String?> _incoming =
      widget.incomingLink ?? kLastWalletConnectUriNotifier;
  bool _busy = false;
  bool _failed = false;
  int _epoch = 0;

  bool get _current =>
      mounted &&
      (widget.isCurrent?.call() ?? true) &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  @override
  void initState() {
    super.initState();
    _incoming.addListener(_takeIncoming);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _takeIncoming();
    });
  }

  void _takeIncoming() {
    final String? text = _incoming.value;
    if (!_current || _busy || text == null) return;
    _input.text = text;
    if (_incoming.value == text) _incoming.value = null;
  }

  bool Function() _capture() {
    final int epoch = _epoch;
    bool revoked = false;
    return () => !revoked && !(revoked = !_current || epoch != _epoch);
  }

  Future<void> _paste() async {
    final bool Function() owns = _capture();
    if (!owns()) return;
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!owns() || _busy) return;
    _input.text = data?.text ?? '';
    setState(() => _failed = false);
  }

  Future<void> _connect() async {
    final Uri? uri = parseWalletConnectLink(_input.text);
    final bool Function() owns = _capture();
    if (uri == null || !owns() || _busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final AppsPairAdmission? injected = widget.onPair;
      final Web3WalletActions? original = injected == null
          ? (app.sl<IWeb3WalletService>() as CapturedWeb3WalletService)
                .captureActions()
          : null;
      if (!owns()) return;
      if (injected != null) {
        await injected(uri, owns);
      } else {
        await original!.pair(uri);
      }
      if (owns()) _input.clear();
    } on Object {
      if (owns()) setState(() => _failed = true);
    } finally {
      // The original operation still owns its busy slot after a source change.
      // Only its actual settlement releases input for the mounted replacement.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final int epoch = _epoch;
    bool original() => _current && epoch == _epoch;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _input,
      builder: (BuildContext context, TextEditingValue value, Widget? child) {
        final bool valid = parseWalletConnectLink(value.text) != null;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: TextField(
                key: const Key('wc_link'),
                controller: _input,
                enabled: !_busy && _current,
                style: tokens.dataText,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) {
                  if (valid && original()) unawaited(_connect());
                },
                decoration: InputDecoration(
                  hintText: context.l10n.appsSettingsWalletConnectLink,
                  errorText: _failed
                      ? context.l10n.appsSettingsFailed
                      : value.text.isNotEmpty && !valid
                      ? context.l10n.appsSettingsInvalidLink
                      : null,
                  suffixIcon: IconButton(
                    tooltip: context.l10n.securitySettingsPaste,
                    onPressed: _busy || !_current
                        ? null
                        : () {
                            if (original()) unawaited(_paste());
                          },
                    icon: const Icon(Icons.content_paste, size: 16),
                  ),
                ),
              ),
            ),
            SizedBox(width: tokens.settingsActionGap),
            OutlinedButton(
              key: const Key('wc_connect'),
              onPressed: valid && !_busy && _current
                  ? () {
                      if (original()) unawaited(_connect());
                    }
                  : null,
              child: Text(context.l10n.appsSettingsConnect),
            ),
          ],
        );
      },
    );
  }

  @override
  void didUpdateWidget(WalletConnectUriCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.onPair, widget.onPair) ||
        !identical(oldWidget.isCurrent, widget.isCurrent) ||
        !identical(oldWidget.incomingLink, widget.incomingLink)) {
      _epoch++;
      _input.clear();
      _failed = false;
    }
    if (!identical(oldWidget.incomingLink, widget.incomingLink)) {
      _incoming.removeListener(_takeIncoming);
      _incoming = widget.incomingLink ?? kLastWalletConnectUriNotifier;
      _incoming.addListener(_takeIncoming);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _takeIncoming();
      });
    }
  }

  @override
  void dispose() {
    _epoch++;
    _incoming.removeListener(_takeIncoming);
    _input.dispose();
    super.dispose();
  }
}
