import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_controller.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_list_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_vote_policy.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// A project page is an RPC view, not proof of contract execution or quorum.
/// Node 590f43ca7a24dccd8e883bc8903a0cb02e54528a binds the UI policy:
/// phase updates replace the last hash, all phase allocations count against
/// the project budget, and VoteByName permits changes to existing votes.
final class AcceleratorProjectSnapshot {
  /// Freezes current display, ownership and retained original-action facts.
  AcceleratorProjectSnapshot({
    required this.project,
    required this.source,
    required this.authority,
    required this.isCurrent,
    required this.selectedId,
    required this.pillarName,
    required this.ownerComplete,
    required this.votesComplete,
    required Map<String, int?> votes,
    required this.failed,
    required this.busy,
    required this.held,
    required this.outcome,
  }) : votes = Map<String, int?>.unmodifiable(votes);

  /// Copied exact project response, absent before a valid original read.
  final AcceleratorListProject? project;

  /// Original read and publication capabilities governing this page.
  final AcceleratorActionSource? source;

  /// Ephemeral generation required by saved selection and vote callbacks.
  final Object authority;

  /// Whether the original source still owns its captured resources.
  final bool isCurrent;

  /// Exact selected project or phase hash from the copied original response.
  final String? selectedId;

  /// Exact owned Pillar name, when complete original owner lookup found one.
  final String? pillarName;

  /// Whether original Pillar ownership was established without ambiguity.
  final bool ownerComplete;

  /// Whether positional vote reads were complete and bound to exact targets.
  final bool votesComplete;

  /// Original exact-target votes; a present null means proven vote absence.
  final Map<String, int?> votes;

  /// Whether the original project read failed or returned a foreign project.
  final bool failed;

  /// Whether this presenter is observing an admitted original vote.
  final bool busy;

  /// Whether the action controller still retains an original on this lane.
  final bool held;

  /// Original retained outcome, including partial acceptance or uncertainty.
  final AcceleratorActionOutcome? outcome;

  /// The copied target matching [selectedId], or null without an exact match.
  AcceleratorVoteTarget? get target {
    for (final AcceleratorVoteTarget value
        in project?.targets ?? <AcceleratorVoteTarget>[]) {
      if (value.targetId == selectedId) return value;
    }
    return null;
  }

  /// Interface vote policy using original ownership and exact membership facts.
  AcceleratorVoteEligibility get eligibility => target == null
      ? AcceleratorVoteEligibility.unknown
      : AcceleratorVotePolicy.eligibility(
          target: target!,
          capturedContextCurrent: isCurrent,
          ownerLookupComplete: ownerComplete,
          exactOwnerPillarName: pillarName,
          nowTimestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );

  /// Whether this page can admit a fresh explicit vote, including change-votes.
  bool get canVote =>
      isCurrent &&
      !busy &&
      !held &&
      eligibility == AcceleratorVoteEligibility.eligible;

  /// Whether complete original vote reads prove the selected vote is absent.
  bool get needsVote =>
      eligibility == AcceleratorVoteEligibility.eligible &&
      votesComplete &&
      votes.containsKey(selectedId) &&
      votes[selectedId] == null;

  /// Whether the current signing account is the original project owner.
  bool get owner => isCurrent && project?.owner == source?.ownerAddress;
}

/// Pure source orchestration. It owns no SDK signer, file, socket or storage.
final class AcceleratorProjectPresenter extends ChangeNotifier {
  /// Retains the exact project hash and original action-controller owner.
  AcceleratorProjectPresenter({
    required this.projectId,
    AcceleratorActionController? actions,
  }) : _actions = actions ?? AcceleratorActionController.shared;

  /// Exact original project hash; later reads cannot reinterpret another hash.
  final String projectId;
  final AcceleratorActionController _actions;
  AcceleratorActionSource? _source;
  AcceleratorListProject? _project;
  String? _selectedId;
  String? _pillarName;
  bool _ownerComplete = false;
  bool _votesComplete = false;
  Map<String, int?> _votes = <String, int?>{};
  bool _failed = false;
  bool _disposed = false;
  Object _authority = Object();
  Object? _readRequest;
  Object? _operation;
  AcceleratorActionOutcome? _outcome;
  AcceleratorActionRequest? _lastVote;

  AcceleratorActionRequest? _voteRequest(AcceleratorProjectVote choice) {
    if (_project == null || _selectedId == null || _pillarName == null) {
      return null;
    }
    return AcceleratorActionRequest(
      kind: AcceleratorActionKind.vote,
      projectId: projectId,
      phaseId: _selectedId == projectId ? null : _selectedId,
      pillarName: _pillarName,
      vote: choice,
    );
  }

  /// Current copied facts and original retained vote outcome for this page.
  AcceleratorProjectSnapshot get snapshot {
    final AcceleratorActionRequest? request = _voteRequest(
      AcceleratorProjectVote.yes,
    );
    return AcceleratorProjectSnapshot(
      project: _project,
      source: _source,
      authority: _authority,
      isCurrent: !_disposed && (_source?.isCurrent ?? false),
      selectedId: _selectedId,
      pillarName: _pillarName,
      ownerComplete: _ownerComplete,
      votesComplete: _votesComplete,
      votes: _votes,
      failed: _failed,
      busy: _operation != null,
      held:
          _source != null &&
          request != null &&
          _actions.holds(_source!, request),
      outcome:
          _outcome ??
          (_source != null && request != null
              ? _actions.retained(_source!, request)
              : null),
    );
  }

  /// Checks the exact displayed generation without capturing a replacement.
  bool owns(Object authority) =>
      !_disposed &&
      identical(authority, _authority) &&
      (_source?.isCurrent ?? false);

  /// Revokes painted facts and saved callbacks before replacement reads begin.
  void invalidate() {
    if (_disposed) return;
    _authority = Object();
    _readRequest = null;
    _operation = null;
    _project = null;
    _source = null;
    _selectedId = null;
    _pillarName = null;
    _ownerComplete = false;
    _votesComplete = false;
    _votes = <String, int?>{};
    _outcome = null;
    _failed = false;
    notifyListeners();
  }

  /// Reads the exact original project, owner and positional target votes.
  /// Foreign, incomplete or superseded replies cannot authorize page actions.
  Future<void> load(AcceleratorActionSource source) async {
    if (_disposed) return;
    final String? previousSelection = _selectedId;
    invalidate();
    _source = source;
    final Object readRequest = Object();
    _readRequest = readRequest;
    bool current() =>
        !_disposed &&
        identical(readRequest, _readRequest) &&
        source.isCurrent &&
        identical(source, _source);
    await Future.wait<void>(<Future<void>>[
      () async {
        try {
          if (!current()) return;
          final Project result = await source.readProject(projectId);
          if (!current()) return;
          if (result.id.toString() != projectId) {
            throw const AcceleratorActionRefused();
          }
          final AcceleratorListProject copy =
              AcceleratorListProject.fromProject(result);
          _project = copy;
          final List<AcceleratorVoteTarget> available = copy.targets
              .where(
                (AcceleratorVoteTarget value) =>
                    !value.isPhase || value.exactPhaseMembership,
              )
              .toList();
          if (available.any(
            (AcceleratorVoteTarget value) =>
                value.targetId == previousSelection,
          )) {
            _selectedId = previousSelection;
          } else {
            _selectedId = projectId;
            if (copy.status != AcceleratorProjectStatus.voting) {
              for (final AcceleratorVoteTarget value in available) {
                if (value.isPhase &&
                    (value.status == AcceleratorProjectStatus.voting ||
                        value.status == AcceleratorProjectStatus.active)) {
                  _selectedId = value.targetId;
                }
              }
            }
          }
          notifyListeners();
        } on Object {
          if (current()) {
            _failed = true;
            notifyListeners();
          }
        }
      }(),
      () async {
        try {
          if (!current()) return;
          final List<PillarInfo> pillars = await source.readPillars();
          if (!current()) return;
          if (pillars.length > 1 ||
              pillars.any(
                (PillarInfo value) =>
                    value.ownerAddress.toString() != source.ownerAddress ||
                    value.name.isEmpty,
              )) {
            return;
          }
          _pillarName = pillars.isEmpty ? null : pillars.single.name;
          _ownerComplete = true;
          notifyListeners();
        } on Object {
          // Unknown ownership never becomes permission to vote.
        }
      }(),
    ]);
    if (!current() ||
        _project == null ||
        !_ownerComplete ||
        _pillarName == null) {
      return;
    }
    final String name = _pillarName!;
    final List<String> ids = List<String>.unmodifiable(
      _project!.targets
          .where(
            (AcceleratorVoteTarget target) =>
                !target.isPhase || target.exactPhaseMembership,
          )
          .map((AcceleratorVoteTarget target) => target.targetId),
    );
    final Map<String, int?> votes = <String, int?>{};
    try {
      for (int start = 0; start < ids.length; start += rpcMaxPageSize) {
        if (!current()) return;
        final List<String> batch = List<String>.unmodifiable(
          ids.skip(start).take(rpcMaxPageSize),
        );
        final List<PillarVote?> response = await source.readVotes(name, batch);
        if (!current()) return;
        if (response.length != batch.length) {
          throw const AcceleratorActionRefused();
        }
        for (int i = 0; i < batch.length; i++) {
          final PillarVote? vote = response[i];
          if (votes.containsKey(batch[i]) ||
              vote != null &&
                  (vote.name != name ||
                      vote.id.toString() != batch[i] ||
                      vote.vote < 0 ||
                      vote.vote >= AcceleratorProjectVote.values.length)) {
            throw const AcceleratorActionRefused();
          }
          votes[batch[i]] = vote?.vote;
        }
      }
      _votes = votes;
      _votesComplete = true;
      notifyListeners();
    } on Object {
      // A partial lookup does not label any target as needing a vote.
    }
  }

  /// Selects a copied exact member only under its original display generation.
  void select(String id, Object authority) {
    if (!owns(authority) ||
        _operation != null ||
        _project == null ||
        id == _selectedId ||
        !_project!.targets.any(
          (AcceleratorVoteTarget value) =>
              value.targetId == id &&
              (!value.isPhase || value.exactPhaseMembership),
        )) {
      return;
    }
    _selectedId = id;
    _outcome = null;
    _authority = Object();
    notifyListeners();
  }

  /// Admits one explicit original vote and retains its result through disposal.
  Future<AcceleratorActionOutcome> vote(
    AcceleratorProjectVote choice, {
    required Object authority,
    required bool Function() canContinue,
  }) async {
    final AcceleratorProjectSnapshot shown = snapshot;
    final AcceleratorActionSource? source = _source;
    final AcceleratorActionRequest? request = _voteRequest(choice);
    if (!owns(authority) ||
        !shown.canVote ||
        source == null ||
        request == null ||
        !canContinue()) {
      return AcceleratorActionOutcome(AcceleratorActionState.refused);
    }
    final Object operation = Object();
    _operation = operation;
    _lastVote = request;
    notifyListeners();
    final Future<AcceleratorActionOutcome> original = _actions.submit(
      source,
      request,
      canContinue: () =>
          owns(authority) && identical(_operation, operation) && canContinue(),
    );
    final AcceleratorActionOutcome outcome = await original;
    if (owns(authority) && identical(_operation, operation)) {
      _operation = null;
      _outcome = outcome;
      notifyListeners();
    }
    return outcome;
  }

  /// Explicitly rechecks the original vote effect before loading fresh facts.
  /// Uncertain originals remain held by their original action controller.
  Future<void> refresh(AcceleratorActionSource source) async {
    final AcceleratorActionRequest? original =
        _lastVote ?? _voteRequest(AcceleratorProjectVote.yes);
    invalidate();
    final Object authority = _authority;
    if (original != null) await _actions.rearm(source, original);
    if (_disposed || !identical(authority, _authority) || !source.isCurrent) {
      return;
    }
    await load(source);
  }

  @override
  void dispose() {
    _disposed = true;
    _authority = Object();
    _readRequest = null;
    _operation = null;
    super.dispose();
  }
}
