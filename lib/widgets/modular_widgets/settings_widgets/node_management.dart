import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/auto_receive_tx_worker.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/auto_unlock_htlc_worker.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/notifications_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/handlers/htlc_swaps_handler.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/node_update/node_update.dart';
import 'package:zenon_syrius_wallet_flutter/services/htlc_swaps_service.dart';
import 'package:zenon_syrius_wallet_flutter/services/i_web3wallet_service.dart';
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_change.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/original_publications.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/node_settings_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/node_settings_view.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/tabs.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

part 'node_settings_wallet.dart';

/// The Node section's production owner. The child supplies its single scroller.
class NodeSettingsSection extends StatefulWidget {
  /// Keeps the existing return-to-wallet callback after a genuine connection.
  const NodeSettingsSection({
    required this.onNodeChangedCallback,
    this.isCurrent,
    this.onboarding = false,
    super.key,
  });

  /// Called only after the selected node was accepted, kept and announced.
  final VoidCallback onNodeChangedCallback;

  /// The Settings owner revokes outgoing sections before transition teardown.
  final bool Function()? isCurrent;

  /// Uses the genuine entry route, including a pristine absent node selection.
  final bool onboarding;

  @override
  State<NodeSettingsSection> createState() => _NodeSettingsSectionState();
}

class _NodeSettingsSectionState extends State<NodeSettingsSection> {
  late final NodeSettingsPresenter _presenter = NodeSettingsPresenter(
    initial: NodeSettingsState(
      entries: _walletNodeEntries(),
      activeNode: kCurrentNode,
      clientChain: getChainIdentifier(),
    ),
    capture: _capture,
  );
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    WalletContextRevision.changes.addListener(_authorityChanged);
    _refresh = Timer.periodic(
      const Duration(seconds: 10),
      (Timer _) => unawaited(_presenter.refresh()),
    );
  }

  NodeSettingsSession? _capture() {
    final bool Function()? external = widget.isCurrent;
    if (!mounted || !_presenter.visible || !(external?.call() ?? true)) {
      return null;
    }
    return _WalletNodeSettingsSession.capture(
      onboarding: widget.onboarding,
      visible: () =>
          mounted && _presenter.visible && (external?.call() ?? true),
      didConnect: widget.onNodeChangedCallback,
    );
  }

  @override
  void didUpdateWidget(NodeSettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!(oldWidget.isCurrent?.call() ?? true)) {
      _presenter.invalidate();
      unawaited(_presenter.refresh());
    }
  }

  void _authorityChanged() {
    if (_presenter.committing) {
      return;
    }
    _presenter.invalidate();
    unawaited(_presenter.refresh());
  }

  @override
  Widget build(BuildContext context) => NodeSettingsView(
    presenter: _presenter,
    embeddedNode: const NodeUpdateCard(),
    isCurrent: widget.isCurrent,
    confirmSelected: widget.onboarding,
  );

  @override
  void dispose() {
    _refresh?.cancel();
    WalletContextRevision.changes.removeListener(_authorityChanged);
    unawaited(_presenter.close());
    super.dispose();
  }
}

/// Compatibility for the existing Settings import and callback contract.
class NodeManagement extends NodeSettingsSection {
  /// New routing should use [NodeSettingsSection] directly, without a grid.
  const NodeManagement({
    required super.onNodeChangedCallback,
    super.isCurrent,
    super.key,
  });
}
