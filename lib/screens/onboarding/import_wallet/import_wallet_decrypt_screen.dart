import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/entry_action_boundary.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/import_wallet/import_decrypt_attempt.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/import_wallet/import_draft.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/import_wallet/import_surface.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/import_wallet/import_wallet_password_screen.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/onboarding_step_route.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_file.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Authenticates the originally selected file before passing on its valid seed.
class ImportWalletDecryptScreen extends StatefulWidget {
  /// Captures the admitted private file path for one decrypt continuation.
  const ImportWalletDecryptScreen(this.path, {super.key});

  /// Original private encrypted-file path; never used as presentation text.
  final String path;

  @override
  State<ImportWalletDecryptScreen> createState() =>
      _ImportWalletDecryptScreenState();
}

class _ImportWalletDecryptScreenState extends State<ImportWalletDecryptScreen> {
  final TextEditingController _password = TextEditingController();
  Object _source = Object();
  ImportDecryptAttempt<WalletFile>? _attempt;
  ImportDecryptStatus? _error;
  bool _busy = false;

  @override
  void didUpdateWidget(ImportWalletDecryptScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _source = Object();
      _password.clear();
      _error = null;
      // The old attempt still owns its original futures and release.
      _attempt = null;
      _busy = false;
    }
  }

  Future<void> _decrypt(
    EntryActionLease lease,
    Object source,
    String path,
    String password,
  ) async {
    if (_busy ||
        !lease.isCurrent ||
        !identical(source, _source) ||
        password.isEmpty) {
      return;
    }
    const Future<WalletFile> Function(String, String) decryptor =
        WalletUtils.decryptWalletFile;
    final ImportDecryptAttempt<WalletFile> attempt =
        ImportDecryptAttempt<WalletFile>(
          path: path,
          source: source,
          decrypt: decryptor,
          accessOriginal: (WalletFile original) {
            if (original is! KeyStoreWalletFile) {
              throw const FormatException('Unsupported wallet file');
            }
            return original.access<String>(
              (Wallet wallet) async => (wallet as KeyStore).mnemonic!,
            );
          },
          isCurrent: () =>
              mounted &&
              lease.isCurrent &&
              identical(source, _source) &&
              widget.path == path,
          validateSeed: (String seed) {
            final List<String> words = seed.trim().split(RegExp(r'\s+'));
            return ImportSeedDraft(seed, expectedWords: words.length).valid;
          },
          isIncorrectPassword: (Object error) =>
              error is IncorrectPasswordException,
        );
    setState(() {
      _attempt = attempt;
      _busy = true;
      _error = null;
    });
    final ImportDecryptOutcome outcome = await attempt.start(password);
    if (!mounted || !identical(_attempt, attempt)) return;
    setState(() => _busy = false);
    if (!lease.isCurrent ||
        !identical(source, _source) ||
        widget.path != path) {
      return;
    }
    if (outcome.status == ImportDecryptStatus.ready) {
      final String seed = outcome.seed!;
      Navigator.of(context).push<void>(
        OnboardingStepRoute<void>(
          builder: (_) => ImportWalletPasswordScreen(seed),
        ),
      );
    } else if (outcome.status != ImportDecryptStatus.stale) {
      setState(() => _error = outcome.status);
    }
  }

  @override
  Widget build(BuildContext context) => EntryActionBoundary(
    source: _source,
    builder: (BuildContext context, EntryActionLease lease) {
      final Object source = _source;
      final String path = widget.path;
      final String password = _password.text;
      return ImportUnlockSurface(
        password: _password,
        busy: _busy,
        error: _error == null
            ? null
            : _error == ImportDecryptStatus.incorrectPassword
            ? context.l10n.importPasswordIncorrect
            : context.l10n.importDecryptFailed,
        onChanged: () {
          if (lease.isCurrent && identical(source, _source)) {
            setState(() {
              _source = Object();
              _error = null;
            });
          }
        },
        onBack: lease.guard(() => Navigator.pop(context)),
        onContinue: _busy || password.isEmpty
            ? null
            : lease.guard(() {
                if (_password.text == password) {
                  unawaited(_decrypt(lease, source, path, password));
                }
              }),
      );
    },
  );

  @override
  void dispose() {
    _source = Object();
    _password.dispose();
    super.dispose();
  }
}
