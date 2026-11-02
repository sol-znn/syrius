import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/motion/motion.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/security_settings_binding.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_parts.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_sensitive_fields.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_sensitive_session.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/widgets.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Shows only the original authenticated software wallet's seed words.
class DumpMnemonicScreen extends StatefulWidget {
  /// Tests inject a session; production captures only on an explicit action.
  const DumpMnemonicScreen({
    this.session,
    this.routeLease,
    this.isCurrent,
    super.key,
  });

  /// The original resource, never a replacement global after decryption.
  final SettingsSensitiveSession? session;

  /// The original Settings child route, when present.
  final SettingsRouteLease? routeLease;

  /// The original external caller's visible scope.
  final bool Function()? isCurrent;

  @override
  State<DumpMnemonicScreen> createState() => _DumpMnemonicScreenState();
}

class _DumpMnemonicScreenState extends State<DumpMnemonicScreen> {
  final TextEditingController _password = TextEditingController();
  late final SettingsScreenScope _scope = SettingsScreenScope(
    mounted: () => mounted,
  );
  List<String>? _words;
  String? _error;
  bool _busy = false;
  bool _revoked = false;
  SettingsSensitiveSession? _captured;

  @override
  void initState() {
    super.initState();
    WalletContextRevision.changes.addListener(_onRevision);
  }

  void _onRevision() {
    _scope.revoke();
    _revoked = true;
    if (mounted) {
      setState(() => _words = null);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind();
  }

  void _bind() {
    final bool Function()? external = widget.isCurrent;
    _scope.bind(
      context,
      lease: widget.routeLease,
      isCurrent: () => !_revoked && (external == null || external()),
    );
  }

  @override
  void didUpdateWidget(DumpMnemonicScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.session, oldWidget.session) ||
        !identical(widget.routeLease, oldWidget.routeLease)) {
      _scope.revoke();
      _words = null;
    }
    _bind();
  }

  Future<void> _show(bool Function() current) async {
    if (_busy || !current() || _password.text.isEmpty) {
      return;
    }
    final String password = _password.text;
    final String failed = context.l10n.securitySettingsSeedFailed;
    final String incorrect = context.l10n.walletPasswordIncorrectError;
    final SettingsSensitiveSession? session =
        widget.session ??
        (_captured ??= captureSettingsSensitiveSession(
          isCurrent: current,
          fileType: context.l10n.securitySettingsVaultFileType,
        ));
    if (session == null || !session.isCurrent || session.isHardwareWallet) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final List<String> words = await session.revealSeed(
        password,
        isCurrent: current,
      );
      if (current() && session.isCurrent) {
        setState(() {
          _password.clear();
          _words = List<String>.unmodifiable(words);
        });
      }
    } on IncorrectPasswordException {
      if (current() && session.isCurrent) {
        setState(() => _error = incorrect);
      }
    } on Object {
      if (current() && session.isCurrent) {
        setState(() => _error = failed);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool Function() current = _scope.capture();
    final bool allowed =
        current() &&
        (widget.session?.isCurrent ?? _captured?.isCurrent ?? true);
    final List<String>? words = allowed ? _words : null;
    return SettingsScreenFrame(
      title: context.l10n.securitySettingsSeedPhrase,
      note: words == null
          ? context.l10n.securitySettingsSeedPrompt
          : context.l10n.securitySettingsSeedWarning,
      width: words == null ? 480 : 860,
      actions: <Widget>[
        ScreenBackAction(
          label: words == null
              ? context.l10n.securitySettingsBack
              : context.l10n.securitySettingsDone,
          onPressed: () => _scope.back(current),
        ),
        if (words == null)
          OutlinedButton(
            key: const Key('security_seed_show'),
            style: OutlinedButton.styleFrom(minimumSize: kScreenActionSize),
            onPressed: !_busy && _password.text.isNotEmpty
                ? () => unawaited(_show(current))
                : null,
            child: Text(context.l10n.securitySettingsShow),
          ),
      ],
      child: !allowed
          ? const SizedBox.shrink()
          : StateSwitcher(
              axis: Axis.horizontal,
              child: words == null
                  ? SettingsSecretField(
                      key: const Key('security_seed_password'),
                      controller: _password,
                      label: context.l10n.securitySettingsCurrentPassword,
                      isCurrent: current,
                      enabled: !_busy,
                      error: _error,
                      onChanged: (String _) {
                        if (current() && !_busy) {
                          setState(() => _error = null);
                        }
                      },
                      onSubmitted: (String _) => unawaited(_show(current)),
                    )
                  : SeedGrid(
                      words,
                      key: const ValueKey<String>('seed_phrase_words'),
                      enableSeedInputFields: false,
                    ),
            ),
    );
  }

  @override
  void dispose() {
    WalletContextRevision.changes.removeListener(_onRevision);
    _scope.revoke();
    _words = null;
    _password.dispose();
    super.dispose();
  }
}
