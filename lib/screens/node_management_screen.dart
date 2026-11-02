import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/auto_receive_tx_worker.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_transition.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/main_app_container.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/node_management.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/wallet_settings_presenter.dart';

/// Entry's node picker uses the same owned transition and consent as Settings.
class NodeManagementScreen extends StatefulWidget {
  /// The original callback receives only a positively accepted node transition.
  const NodeManagementScreen({this.nodeConfirmationCallback, super.key});

  /// Completes the original creation route; absent means return to the wallet.
  final VoidCallback? nodeConfirmationCallback;

  /// The existing splash route for a wallet with no saved node selection.
  static const String route = 'node-management-screen';

  @override
  State<NodeManagementScreen> createState() => _NodeManagementScreenState();
}

class _NodeManagementScreenState extends State<NodeManagementScreen> {
  late final VoidCallback? _confirmed = widget.nodeConfirmationCallback;
  bool? _autoReceive;
  bool _autoReceiveBusy = false;
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    final Object? stored = app.sharedPrefsService?.get(
      kAutoReceiveKey,
      defaultValue: kAutoReceiveDefaultValue,
    );
    _autoReceive = stored is bool ? stored : null;
  }

  void _accepted() {
    if (!mounted ||
        _opened ||
        NodeTransitions.pending ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _opened = true;
    final VoidCallback? callback = _confirmed;
    if (callback != null) {
      callback();
    } else {
      Navigator.of(
        context,
        rootNavigator: true,
      ).pushReplacementNamed<void, void>(MainAppContainer.route);
    }
  }

  Future<void> _changeAutoReceive(bool enabled) async {
    if (!mounted || _autoReceiveBusy || !kWalletInitCompleted) return;
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    final int revision = WalletContextRevision.value;
    final AutoReceiveTxWorker? worker =
        app.sl.isRegistered<AutoReceiveTxWorker>()
        ? app.sl<AutoReceiveTxWorker>()
        : null;
    bool revoked = false;
    bool current() =>
        !revoked &&
        !(revoked =
            !mounted ||
            route?.isCurrent != true ||
            revision != WalletContextRevision.value);
    final WalletSettingsBinding? binding = WalletSettingsBinding.capture(
      scanForReceives: () async {
        if (!current() ||
            worker == null ||
            !app.sl.isRegistered<AutoReceiveTxWorker>() ||
            !identical(worker, app.sl<AutoReceiveTxWorker>())) {
          return;
        }
        final ReceiveOrigin? origin = worker.captureOrigin(
          sourceIsCurrent: current,
        );
        if (origin == null) return;
        await NodeUtils.getUnreceivedTransactions(origin: origin);
        if (origin.isCurrent) await worker.autoReceive();
      },
    );
    if (binding == null || !current()) return;
    setState(() => _autoReceiveBusy = true);
    try {
      final WalletPreferenceOutcome outcome = await binding.change(
        WalletPreference.autoReceive,
        value: enabled,
        isCurrent: current,
      );
      if (current() && outcome.committed) {
        setState(() => _autoReceive = outcome.value);
      }
    } finally {
      if (mounted) setState(() => _autoReceiveBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          NodeSettingsSection(
            onboarding: true,
            isCurrent: () => mounted && !_opened,
            onNodeChangedCallback: _accepted,
          ),
          SwitchListTile(
            title: Text(currentL10n.walletSettingsAutoReceive),
            value: _autoReceive ?? false,
            onChanged:
                _autoReceive == null ||
                    _autoReceiveBusy ||
                    !kWalletInitCompleted ||
                    NodeTransitions.pending
                ? null
                : (bool value) => unawaited(_changeAutoReceive(value)),
          ),
        ],
      ),
    ),
  );
}
