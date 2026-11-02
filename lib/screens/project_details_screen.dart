import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/refresh_bloc_mixin.dart';
import 'package:zenon_syrius_wallet_flutter/screens/stepper_screen.dart';
import 'package:zenon_syrius_wallet_flutter/utils/explorer_links.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_binding.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_list_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_project_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_project_view.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/phase_creation_stepper.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/update_phase_stepper.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Existing detail route. Its original source is never rebound after an await.
class ProjectDetailsScreen extends StatefulWidget {
  /// Opens the exact original project or a supplied phase's parent project.
  const ProjectDetailsScreen({
    required this.project,
    required this.pillarInfo,
    required this.onStepperNotificationSeeMorePressed,
    super.key,
  });

  /// Original project or phase selecting the exact parent hash for fresh reads.
  final AcceleratorProject project;

  /// Legacy Pillar context; current ownership is independently read.
  final PillarInfo? pillarInfo;

  /// Original notification-details navigation callback.
  final VoidCallback onStepperNotificationSeeMorePressed;
  @override
  State<ProjectDetailsScreen> createState() => _ProjectDetailsScreenState();
}

class _ProjectDetailsScreenState extends State<ProjectDetailsScreen>
    with RefreshBlocMixin {
  late final AcceleratorProjectPresenter _presenter;
  AcceleratorActionBinding? _source;
  String? _explorer;
  bool _invalidated = false;

  @override
  void initState() {
    super.initState();
    final AcceleratorProject original = widget.project;
    final String id = original is Phase
        ? original.projectId.toString()
        : original.id.toString();
    _presenter = AcceleratorProjectPresenter(projectId: id);
    _explorer = ExplorerLinks.transaction(
      id,
      chainId: kNodeChainId,
    )?.toString();
    try {
      _source = AcceleratorActionBinding.capture();
    } on Object {
      _invalidated = true;
    }
    WalletContextRevision.changes.addListener(_invalidate);
    listenToWsRestart(_refresh);
    final AcceleratorActionBinding? source = _source;
    if (source != null) unawaited(_presenter.load(source));
  }

  void _invalidate() {
    _invalidated = true;
    _presenter.invalidate();
  }

  bool get _onPage =>
      mounted &&
      (ModalRoute.of(context)?.isCurrent ?? true) &&
      TickerMode.valuesOf(context).enabled;
  bool get _current => !_invalidated && (_source?.isCurrent ?? false);

  void _refresh() {
    final AcceleratorActionBinding? source = _source;
    if (!_current || source == null) return;
    unawaited(_presenter.refresh(source));
  }

  void _openPhase(Project original, {Phase? phase}) {
    final AcceleratorActionBinding? source = _source;
    if (!_onPage ||
        !_current ||
        source == null ||
        original.id.toString() != _presenter.projectId ||
        original.owner.toString() != source.ownerAddress) {
      return;
    }
    final Project project = AcceleratorListProject.fromProject(
      original,
    ).toProject();
    Phase? selected;
    if (phase != null) {
      for (final Phase value in project.phases) {
        if (value.id == phase.id) selected = value;
      }
      if (selected == null) return;
    }
    final Widget stepper = selected == null
        ? PhaseCreationStepper(project, source: source)
        : UpdatePhaseStepper(selected, project, source: source);
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => StepperScreen(
          stepper: stepper,
          onStepperNotificationSeeMorePressed:
              widget.onStepperNotificationSeeMorePressed,
        ),
      ),
    );
  }

  Future<void> _openUrl(String text) async {
    if (!_onPage || !_current) return;
    final Uri? parsed = Uri.tryParse(text);
    if (parsed == null) return;
    final Uri? exact = parsed.scheme.isEmpty
        ? Uri.tryParse('https://$text')
        : parsed;
    if (exact == null ||
        (exact.scheme != 'https' && exact.scheme != 'http') ||
        exact.host.isEmpty) {
      return;
    }
    // The exact URI is captured before launch. A failed external observer
    // cannot notify a replacement wallet or change an original publication.
    try {
      await launchUrl(exact);
    } on Object {
      return;
    }
  }

  @override
  void dispose() {
    _invalidated = true;
    WalletContextRevision.changes.removeListener(_invalidate);
    cancelStreamSubscription();
    _presenter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: AcceleratorProjectView(
      presenter: _presenter,
      title: widget.project.name,
      explorer: _explorer,
      onBack: () {
        if (_onPage) Navigator.of(context).pop();
      },
      onRefresh: _refresh,
      onCreatePhase: _openPhase,
      onUpdatePhase: (Project project, Phase phase) =>
          _openPhase(project, phase: phase),
      onOpenUrl: _openUrl,
    ),
  );
}
