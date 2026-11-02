import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/home.dart'
    show AmountText;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_controller.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_list_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_parts.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/custom_material_stepper.dart'
    as steps;
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Read-only original view evidence; it conveys no transaction authority.
abstract interface class AcceleratorActionPresentationSource {
  /// Copies only the current original view evidence.
  AcceleratorActionPresentation get actionPresentation;
}

/// Private owner references are compared in memory and never serialized.
final class AcceleratorActionPresentation {
  /// Keeps opaque identities and a finite private copy of UI hashes.
  AcceleratorActionPresentation({
    required this._owner,
    required this._source,
    required this._draft,
    required this._epoch,
    required this._kind,
    required this._current,
    required this._submitted,
    required List<String> hashes,
  }) : _hashes = List<String>.unmodifiable(hashes);

  final Object _owner;
  final Object? _source;
  final Object? _draft;
  final int _epoch;
  final AcceleratorActionKind _kind;
  final bool _current;
  final bool _submitted;
  final List<String> _hashes;

  /// The originally captured operation, without creating another one.
  AcceleratorActionKind get kind => _kind;

  /// The original view is available at its submit or result position.
  bool get current => _current;

  /// A fresh view draft, before its original publication is entered.
  bool get prepared => _current && _source != null && _draft != null &&
      !_submitted && _hashes.isEmpty;

  /// Compares the captured view, source and draft by identity.
  bool sameOwner(AcceleratorActionPresentation other) =>
      identical(_owner, other._owner) && identical(_source, other._source) &&
      identical(_draft, other._draft) && _epoch == other._epoch &&
      _kind == other._kind;

  /// This is a UI receipt match, independent of chain confirmation/effect.
  bool submittedWith(String hash) => _current && _submitted &&
      _hashes.length == 1 && _hashes.single == hash;
}

/// Existing Accelerator forms share one original draft and publication owner.
class AcceleratorActionStepper extends StatefulWidget {
  /// Captures a draft under the originally supplied action and project scope.
  const AcceleratorActionStepper({
    required this.kind,
    this.source,
    this.project,
    this.phase,
    super.key,
  });

  /// Original explicit operation used to build and preflight this form.
  final AcceleratorActionKind kind;

  /// Original action capabilities, without later global source substitution.
  final AcceleratorActionSource? source;

  /// Original parent project when creating or updating a phase.
  final Project? project;

  /// Exact original phase to update, absent for other action kinds.
  final Phase? phase;
  @override
  State<AcceleratorActionStepper> createState() =>
      _AcceleratorActionStepperState();
}

class _AcceleratorActionStepperState extends State<AcceleratorActionStepper>
    implements AcceleratorActionPresentationSource {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _url = TextEditingController();
  final TextEditingController _znn = TextEditingController();
  final TextEditingController _qsr = TextEditingController();
  final AcceleratorActionController _actions =
      AcceleratorActionController.shared;
  AcceleratorActionSource? _source;
  Project? _project;
  String? _phaseId;
  AcceleratorActionBalance? _balance;
  AcceleratorActionRequest? _draft;
  AcceleratorActionOutcome? _outcome;
  int _step = 0;
  int _epoch = 0;
  bool _invalidated = false;
  bool _busy = false;
  bool _preparing = false;
  bool _phaseHeld = false;
  bool _balanceFailed = false;

  @override
  AcceleratorActionPresentation get actionPresentation =>
      AcceleratorActionPresentation(
        owner: this, source: _source, draft: _draft, epoch: _epoch,
        kind: widget.kind, current: _onPage && !_busy && _step == 2,
        submitted: _outcome?.state == AcceleratorActionState.submitted,
        hashes: _outcome?.hashes ?? <String>[],
      );

  bool get _donation => widget.kind == AcceleratorActionKind.donate;
  bool get _current =>
      mounted && !_invalidated && (_source?.isCurrent ?? false);
  bool get _onPage =>
      _current &&
      (ModalRoute.of(context)?.isCurrent ?? true) &&
      TickerMode.valuesOf(context).enabled;

  @override
  void initState() {
    super.initState();
    final Project? project = widget.project;
    _project = project == null
        ? null
        : AcceleratorListProject.fromProject(project).toProject();
    _phaseId = widget.phase?.id.toString();
    if (_phaseId != null) {
      final List<Phase> phases =
          _project?.phases
              .where((Phase phase) => phase.id.toString() == _phaseId)
              .toList() ??
          <Phase>[];
      if (phases.length != 1) {
        _invalidated = true;
      } else {
        final Phase phase = phases.single;
        _name.text = phase.name;
        _description.text = phase.description;
        _url.text = phase.url;
        _znn.text = phase.znnFundsNeeded.addDecimals(coinDecimals);
        _qsr.text = phase.qsrFundsNeeded.addDecimals(coinDecimals);
      }
    }
    // Entry controls pass their original click scope. A delayed route build
    // must never acquire a replacement wallet from mutable globals.
    _source = widget.source;
    if (_source == null) _invalidated = true;
    WalletContextRevision.changes.addListener(_invalidate);
    if (_source != null) unawaited(_prepareOriginal());
  }

  void _invalidate() {
    _invalidated = true;
    _epoch++;
    if (mounted) setState(() {});
  }

  Future<void> _prepareOriginal() async {
    final AcceleratorActionSource? source = _source;
    final int epoch = _epoch;
    if (source == null || !_current || _busy || _preparing || _step != 0) {
      return;
    }
    setState(() => _preparing = true);
    if (widget.kind == AcceleratorActionKind.createPhase ||
        widget.kind == AcceleratorActionKind.updatePhase) {
      // Reopening from fresh project details is a separate deliberate intent.
      // Release only a known original whose exact receipt and phase effect
      // are now present. This check never publishes or resumes a donation.
      final AcceleratorActionRequest probe = AcceleratorActionRequest(
        kind: widget.kind,
        projectId: _project?.id.toString(),
        phaseId: _phaseId,
      );
      final bool rearmed = await _actions.rearm(source, probe);
      if (!_current || epoch != _epoch) return;
      setState(() => _phaseHeld = !rearmed);
    }
    await _readBalance();
    if (_current && epoch == _epoch) setState(() => _preparing = false);
  }

  Future<void> _readBalance() async {
    final AcceleratorActionSource? source = _source;
    final int epoch = _epoch;
    if (source == null || !_current) return;
    try {
      final AcceleratorActionBalance result = await source.readBalance();
      if (_current && epoch == _epoch) {
        setState(() {
          _balance = result;
          _balanceFailed = false;
        });
      }
    } on Object {
      // A missing account response never supplies zero or a signing scope.
      if (_current && epoch == _epoch) {
        setState(() {
          _balance = null;
          _balanceFailed = true;
        });
      }
    }
  }

  AcceleratorActionRequest? _request() {
    if (_preparing || _phaseHeld) return null;
    final BigInt? znn = acceleratorDraftUnits(_znn.text);
    final BigInt? qsr = acceleratorDraftUnits(_qsr.text);
    if (znn == null || qsr == null) return null;
    final AcceleratorActionRequest request = AcceleratorActionRequest(
      kind: widget.kind,
      projectId: _project?.id.toString(),
      phaseId: _phaseId,
      phaseIds:
          _project?.phaseIds.map((Hash id) => id.toString()).toList() ??
          <String>[],
      name: _name.text,
      description: _description.text,
      url: _url.text,
      znn: znn,
      qsr: qsr,
    );
    if (_donation) {
      final AcceleratorActionBalance? balance = _balance;
      return balance != null &&
              (znn > BigInt.zero || qsr > BigInt.zero) &&
              znn <= balance.znn &&
              qsr <= balance.qsr
          ? request
          : null;
    }
    final AcceleratorActionSource? source = _source;
    if (source == null ||
        !source.validMetadata(request) ||
        znn > source.maximumZnn ||
        qsr > source.maximumQsr) {
      return null;
    }
    final Project? project = _project;
    if (project != null) {
      BigInt totalZnn = znn;
      BigInt totalQsr = qsr;
      for (final Phase phase in project.phases) {
        if (widget.kind == AcceleratorActionKind.updatePhase &&
            phase.id.toString() == _phaseId) {
          continue;
        }
        totalZnn += phase.znnFundsNeeded;
        totalQsr += phase.qsrFundsNeeded;
      }
      if (totalZnn > project.znnFundsNeeded ||
          totalQsr > project.qsrFundsNeeded) {
        return null;
      }
    }
    return request;
  }

  Future<void> _submit() async {
    final AcceleratorActionSource? source = _source;
    final AcceleratorActionRequest? request = _draft;
    final int epoch = _epoch;
    if (!_onPage ||
        _busy ||
        _step != 2 ||
        source == null ||
        request == null ||
        (_outcome != null &&
            _outcome!.state != AcceleratorActionState.refused)) {
      return;
    }
    setState(() => _busy = true);
    final Future<AcceleratorActionOutcome> original = _actions.submit(
      source,
      request,
      canContinue: () => _current && epoch == _epoch && _onPage,
    );
    final AcceleratorActionOutcome outcome = await original;
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (_current && epoch == _epoch) _outcome = outcome;
    });
  }

  Future<void> _newAction() async {
    final AcceleratorActionSource? source = _source;
    final AcceleratorActionRequest? request = _draft;
    final int epoch = _epoch;
    if (!_onPage ||
        _busy ||
        source == null ||
        request == null ||
        _outcome?.state != AcceleratorActionState.submitted) {
      return;
    }
    setState(() => _busy = true);
    final bool confirmed = await _actions.rearm(source, request);
    if (!mounted) return;
    bool reload = false;
    setState(() {
      _busy = false;
      if (confirmed && _current && epoch == _epoch) {
        _outcome = null;
        _draft = null;
        _step = 0;
        _balance = null;
        _balanceFailed = false;
        reload = true;
        _name.clear();
        _description.clear();
        _url.clear();
        _znn.clear();
        _qsr.clear();
      }
    });
    if (reload) unawaited(_readBalance());
  }

  void _close() {
    if (_onPage && !_busy) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _invalidated = true;
    _epoch++;
    WalletContextRevision.changes.removeListener(_invalidate);
    _name.dispose();
    _description.dispose();
    _url.dispose();
    _znn.dispose();
    _qsr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    if (!_current) {
      return Center(
        child: Text(
          context.l10n.acceleratorSessionChanged,
          style: tokens.compactText,
        ),
      );
    }
    final bool submitted = _outcome?.state == AcceleratorActionState.submitted;
    final List<Widget> bodies = <Widget>[
      _buildOwner(context),
      _buildDetails(context),
      _buildSubmit(context),
    ];
    final List<String> names = <String>[
      context.l10n.acceleratorOwner,
      context.l10n.acceleratorDetails,
      context.l10n.acceleratorSubmit,
    ];
    return AccStepperFrame(
      isDone: submitted,
      doneLabel: context.l10n.acceleratorProjects,
      onDone: _close,
      againLabel:
          submitted &&
              (widget.kind == AcceleratorActionKind.createProject || _donation)
          ? context.l10n.acceleratorNewAction
          : null,
      onAgain:
          submitted &&
              !_busy &&
              (widget.kind == AcceleratorActionKind.createProject || _donation)
          ? _newAction
          : null,
      stepper: steps.Stepper(
        currentStep: _step,
        onStepTapped: (_) {},
        steps: <steps.Step>[
          for (int index = 0; index < bodies.length; index++)
            steps.Step(
              title: Text(names[index]),
              content: bodies[index],
              isActive: index == _step,
              state: index < _step || submitted
                  ? steps.StepState.complete
                  : steps.StepState.indexed,
            ),
        ],
      ),
    );
  }

  Widget _buildOwner(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final AcceleratorActionBalance? balance = _balance;
    final bool paidAccount =
        widget.kind == AcceleratorActionKind.createProject || _donation;
    final bool available =
        !_preparing &&
        !_phaseHeld &&
        (!paidAccount ||
            balance != null &&
                (widget.kind != AcceleratorActionKind.createProject ||
                    balance.znn >= projectCreationFeeInZnn));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Tooltip(
          message: _source!.ownerAddress,
          child: Text(
            _source!.ownerAddress,
            style: tokens.dataText,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (balance != null) ...<Widget>[
          SizedBox(height: tokens.inlineGap),
          AmountText(
            balance.znn,
            decimals: coinDecimals,
            symbol: 'ZNN',
            style: tokens.dataText,
          ),
          AmountText(
            balance.qsr,
            decimals: coinDecimals,
            symbol: 'QSR',
            style: tokens.dataText.copyWith(color: tokens.dim),
          ),
        ],
        if (_phaseHeld)
          Text(context.l10n.acceleratorActionHeld, style: tokens.compactText),
        if (_balanceFailed || _phaseHeld)
          TextButton.icon(
            style: quietButtonStyle(context),
            onPressed: _onPage && !_preparing && !_busy && _step == 0
                ? _prepareOriginal
                : null,
            icon: const Icon(Icons.refresh, size: 16),
            label: Text(context.l10n.acceleratorRefresh),
          ),
        if (widget.kind == AcceleratorActionKind.createProject)
          Text(
            context.l10n.acceleratorCreateFee(
              accAmount(projectCreationFeeInZnn, coinDecimals, 'ZNN'),
            ),
            style: tokens.compactText,
          ),
        AccStepActions(
          primary: PrimaryPill(
            onPressed: available
                ? () {
                    if (!_onPage ||
                        _busy ||
                        _preparing ||
                        _phaseHeld ||
                        _step != 0) {
                      return;
                    }
                    final AcceleratorActionBalance? currentBalance = _balance;
                    if (paidAccount &&
                        (currentBalance == null ||
                            widget.kind ==
                                    AcceleratorActionKind.createProject &&
                                currentBalance.znn < projectCreationFeeInZnn)) {
                      return;
                    }
                    setState(() => _step = 1);
                  }
                : null,
            child: Text(context.l10n.acceleratorContinue),
          ),
          secondaryLabel: context.l10n.acceleratorCancel,
          onSecondary: _close,
        ),
      ],
    );
  }

  Widget _buildDetails(BuildContext context) {
    Widget field(
      String label,
      TextEditingController controller, {
      bool amount = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: kAccFieldGap),
      child: AccField(
        label: label,
        child: TextField(
          controller: controller,
          enabled: !_busy,
          style: accFieldTextStyle(context, mono: amount),
          onChanged: (_) {
            if (_current && !_busy && _step == 1) setState(() {});
          },
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (!_donation) ...<Widget>[
          field(context.l10n.acceleratorName, _name),
          field(context.l10n.acceleratorDescription, _description),
          field(context.l10n.acceleratorUrl, _url),
        ],
        field(
          _donation
              ? context.l10n.acceleratorDonationZnn
              : context.l10n.acceleratorZnnBudget,
          _znn,
          amount: true,
        ),
        field(
          _donation
              ? context.l10n.acceleratorDonationQsr
              : context.l10n.acceleratorQsrBudget,
          _qsr,
          amount: true,
        ),
        AccStepActions(
          primary: PrimaryPill(
            onPressed: _request() == null
                ? null
                : () {
                    if (!_onPage || _busy || _step != 1) return;
                    final AcceleratorActionRequest? request = _request();
                    if (request != null) {
                      setState(() {
                        _draft = request;
                        _step = 2;
                      });
                    }
                  },
            child: Text(context.l10n.acceleratorContinue),
          ),
          secondaryLabel: context.l10n.acceleratorBack,
          onSecondary: () {
            if (_onPage && !_busy && _step == 1) setState(() => _step = 0);
          },
        ),
      ],
    );
  }

  Widget _buildSubmit(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final AcceleratorActionOutcome? outcome = _outcome;
    final String? state = outcome == null
        ? null
        : switch (outcome.state) {
            AcceleratorActionState.submitted =>
              context.l10n.acceleratorActionSubmitted,
            AcceleratorActionState.uncertain =>
              context.l10n.acceleratorActionUnknown,
            AcceleratorActionState.held => context.l10n.acceleratorActionHeld,
            AcceleratorActionState.refused =>
              context.l10n.acceleratorActionRefused,
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (_draft != null) ...<Widget>[
          if (!_donation) Text(_draft!.name, style: tokens.bodyText),
          AmountText(
            _draft!.znn,
            decimals: coinDecimals,
            symbol: 'ZNN',
            style: tokens.dataText,
          ),
          AmountText(
            _draft!.qsr,
            decimals: coinDecimals,
            symbol: 'QSR',
            style: tokens.dataText,
          ),
        ],
        if (state != null) Text(state, style: tokens.compactText),
        for (final String hash in outcome?.hashes ?? <String>[])
          Tooltip(
            message: hash,
            child: Text(
              '${hash.substring(0, 7)}…${hash.substring(hash.length - 6)}',
              style: tokens.dataText,
            ),
          ),
        if (outcome == null || outcome.state == AcceleratorActionState.refused)
          AccStepActions(
            primary: PrimaryPill(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: tokens.foreground,
                      ),
                    )
                  : Text(context.l10n.acceleratorSubmit),
            ),
            secondaryLabel: context.l10n.acceleratorBack,
            onSecondary: () {
              if (_onPage && !_busy && _step == 2) {
                setState(() {
                  _draft = null;
                  _outcome = null;
                  _step = 1;
                });
              }
            },
          ),
      ],
    );
  }
}
