import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/create_key_store_screen.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/entry_action_boundary.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/import_wallet/import_draft.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/import_wallet/import_surface.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/onboarding_step_route.dart';
import 'package:zenon_syrius_wallet_flutter/utils/input_validators.dart';

/// Validates a new password for the exact original imported mnemonic.
class ImportWalletPasswordScreen extends StatefulWidget {
  /// Retains private mnemonic input until guarded creation is admitted.
  const ImportWalletPasswordScreen(
    this.seed, {
    this.progressBarNumLevels = 5,
    super.key,
  });

  /// Original validated private mnemonic, never replaced after a saved action.
  final String seed;

  /// Existing flow length forwarded to the remaining creation and Ready steps.
  final int progressBarNumLevels;

  @override
  State<ImportWalletPasswordScreen> createState() =>
      _ImportWalletPasswordScreenState();
}

class _ImportWalletPasswordScreenState
    extends State<ImportWalletPasswordScreen> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirmation = TextEditingController();
  Object _source = Object();

  @override
  void didUpdateWidget(ImportWalletPasswordScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seed != widget.seed ||
        oldWidget.progressBarNumLevels != widget.progressBarNumLevels) {
      _source = Object();
      _password.clear();
      _confirmation.clear();
    }
  }

  bool get _valid {
    final List<String> words = widget.seed.trim().split(RegExp(r'\s+'));
    return ImportSeedDraft(widget.seed, expectedWords: words.length).valid &&
        InputValidators.validatePassword(_password.text) == null &&
        InputValidators.checkPasswordMatch(
              _password.text,
              _confirmation.text,
            ) ==
            null;
  }

  @override
  Widget build(BuildContext context) => EntryActionBoundary(
    source: _source,
    builder: (BuildContext context, EntryActionLease lease) {
      final Object source = _source;
      final String seed = widget.seed;
      final String password = _password.text;
      final int levels = widget.progressBarNumLevels;
      return ImportPasswordSurface(
        password: _password,
        confirmation: _confirmation,
        onChanged: () {
          if (lease.isCurrent && identical(source, _source)) {
            setState(() => _source = Object());
          }
        },
        onBack: lease.guard(() => Navigator.pop(context)),
        onContinue: _valid
            ? lease.guard(() {
                if (!identical(source, _source) ||
                    widget.seed != seed ||
                    _password.text != password ||
                    !_valid) {
                  return;
                }
                Navigator.of(context).push<void>(
                  OnboardingStepRoute<void>(
                    builder: (_) => CreateKeyStoreScreen(
                      seed,
                      password,
                      progressBarNumLevels: levels,
                      importedWallet: true,
                    ),
                  ),
                );
              })
            : null,
      );
    },
  );

  @override
  void dispose() {
    _source = Object();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }
}
