import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/apps_settings_binding.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/apps_settings_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/apps_settings_view.dart';

/// Apps owns its original presenter; Settings owns section navigation.
class AppsSettingsSection extends StatefulWidget {
  /// Uses the supplied boundary, or captures the open production source.
  const AppsSettingsSection({required this.isCurrent, this.binding, super.key});

  /// Settings section ownership checked before input or result display.
  final bool Function() isCurrent;

  /// An optional original source for controlled embedding or finite fixtures.
  final AppsSettingsBinding? binding;

  @override
  State<AppsSettingsSection> createState() => _AppsSettingsSectionState();
}

class _AppsSettingsSectionState extends State<AppsSettingsSection> {
  late AppsSettingsPresenter _presenter = AppsSettingsPresenter(
    widget.binding ?? captureAppsSettingsBinding(),
  );

  @override
  Widget build(BuildContext context) => AppsSettingsView(
    presenter: _presenter,
    isCurrent: widget.isCurrent,
  );

  @override
  void didUpdateWidget(AppsSettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.binding, widget.binding)) {
      unawaited(_presenter.close());
      _presenter = AppsSettingsPresenter(
        widget.binding ?? captureAppsSettingsBinding(),
      );
    }
  }

  @override
  void dispose() {
    unawaited(_presenter.close());
    super.dispose();
  }
}
