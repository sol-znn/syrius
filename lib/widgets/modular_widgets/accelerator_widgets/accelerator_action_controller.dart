import 'dart:async';

import 'package:zenon_syrius_wallet_flutter/services/accelerator_project_cache.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_vote_policy.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The explicit original intent used to build an Accelerator publication.
enum AcceleratorActionKind {
  /// Create a project from the copied metadata and funding request.
  createProject,

  /// Add a phase to an exact original project's current membership.
  createPhase,

  /// Replace an exact original latest phase with a copied draft.
  updatePhase,

  /// Donate one or both native coins in the requested exact units.
  donate,

  /// Submit the chosen Pillar vote for the exact project or phase hash.
  vote,
}

/// Submission state, independent of later confirmation or contract effects.
enum AcceleratorActionState {
  /// The original request failed before publication handoff.
  refused,

  /// Original sends returned accepted hashes; effects require fresh proof.
  submitted,

  /// Publication was invoked and its complete outcome is not established.
  uncertain,

  /// A different original intent already occupies this action lane.
  held,
}

/// Exact native units for a form draft. No floating point or rounding.
BigInt? acceleratorDraftUnits(String text) {
  if (text.isEmpty) return BigInt.zero;
  if (!RegExp(r'^\d+(?:\.\d{0,8})?$').hasMatch(text)) return null;
  final List<String> parts = text.split('.');
  return BigInt.parse(parts.first) * BigInt.from(10).pow(coinDecimals) +
      BigInt.parse(
        (parts.length == 2 ? parts.last : '').padRight(coinDecimals, '0'),
      );
}

/// One deliberate original action, copied before any read or question.
final class AcceleratorActionRequest {
  /// Freezes one deliberate draft before asynchronous reads or confirmation.
  AcceleratorActionRequest({
    required this.kind,
    this.projectId,
    this.phaseId,
    this.pillarName,
    this.vote,
    this.name = '',
    this.description = '',
    this.url = '',
    BigInt? znn,
    BigInt? qsr,
    List<String> phaseIds = const <String>[],
  }) : znn = znn ?? BigInt.zero,
       qsr = qsr ?? BigInt.zero,
       phaseIds = List<String>.unmodifiable(phaseIds);

  /// The originally chosen operation, never inferred from a later response.
  final AcceleratorActionKind kind;

  /// Exact original project hash for project-specific operations.
  final String? projectId;

  /// Exact original phase hash when updating or voting on a phase.
  final String? phaseId;

  /// The originally selected Pillar name required by a vote.
  final String? pillarName;

  /// The original explicit vote choice.
  final AcceleratorProjectVote? vote;

  /// Copied project or phase name from the admitted draft.
  final String name;

  /// Copied project or phase description from the admitted draft.
  final String description;

  /// Copied project or phase URL, validated before publication.
  final String url;

  /// Exact requested ZNN native units, without floating-point conversion.
  final BigInt znn;

  /// Exact requested QSR native units, without floating-point conversion.
  final BigInt qsr;

  /// Ordered original phase membership used by fresh phase preflight checks.
  final List<String> phaseIds;

  /// The exact phase target when supplied, otherwise the original project.
  String? get targetId => phaseId ?? projectId;

  /// Value identity for coalescing repeated submission of this same intent.
  Object get identity => (
    kind,
    projectId,
    phaseId,
    pillarName,
    vote,
    name,
    description,
    url,
    znn,
    qsr,
    phaseIds.join(':'),
  );

  /// Binds conflicting intents to one original wallet/account/chain target.
  Object lane(Object scope) => (
    scope,
    switch (kind) {
      AcceleratorActionKind.createPhase ||
      AcceleratorActionKind.updatePhase => 'phase',
      _ => kind.name,
    },
    kind == AcceleratorActionKind.vote ? targetId : projectId,
  );
}

/// Exact native-coin balances returned by the original account read.
final class AcceleratorActionBalance {
  /// Captures both native amounts without rounding or display conversion.
  const AcceleratorActionBalance(this.znn, this.qsr);

  /// Original ZNN balance in native units.
  final BigInt znn;

  /// Original QSR balance in native units.
  final BigInt qsr;
}

/// Production binds these operations to copied original APIs and transports.
/// Pure fixtures replace this interface, without a wallet, signer or storage.
abstract interface class AcceleratorActionSource {
  /// Original wallet/account/chain identity shared by conflicting action lanes.
  Object get scopeKey;

  /// Canonical original signing account used by preflight ownership checks.
  String get ownerAddress;

  /// Whether the captured source still owns its original resources.
  bool get isCurrent;

  /// Existing maximum project allocation in exact ZNN units.
  BigInt get maximumZnn;

  /// Existing maximum project allocation in exact QSR units.
  BigInt get maximumQsr;

  /// Applies existing metadata and URL validation to the copied draft.
  bool validMetadata(AcceleratorActionRequest request);

  /// Builds original unsigned templates without publishing or retrying them.
  List<AccountBlockTemplate> build(AcceleratorActionRequest request);

  /// Reads the exact project through the originally bound API and transport.
  Future<Project> readProject(String id);

  /// Reads Pillars owned by the captured original signing account.
  Future<List<PillarInfo>> readPillars();

  /// Reads exact native balances for the captured original signing account.
  Future<AcceleratorActionBalance> readBalance();

  /// Reads positional votes for the exact original Pillar and target hashes.
  Future<List<PillarVote?>> readVotes(String name, List<String> ids);

  /// Checks matching-block confirmation metadata through the original ledger.
  Future<bool> readConfirmed(String hash);

  /// Returns the original send Future; later revocation cannot cancel its send.
  Future<AccountBlockTemplate> publish(
    AccountBlockTemplate template,
    AcceleratorActionKind kind, {
    required bool Function() canPublish,
  });
}

/// Original raw results and copied hashes survive view disposal and lock.
final class AcceleratorActionOutcome {
  /// Retains raw accepted blocks, copied hashes and any original failure.
  AcceleratorActionOutcome(
    this.state, {
    List<AccountBlockTemplate> blocks = const <AccountBlockTemplate>[],
    List<String>? hashes,
    this.error,
    this.stackTrace,
  }) : blocks = List<AccountBlockTemplate>.unmodifiable(blocks),
       hashes = List<String>.unmodifiable(
         hashes ??
             blocks.map((AccountBlockTemplate block) => block.hash.toString()),
       );

  /// Original submission state, without claiming a later contract effect.
  final AcceleratorActionState state;

  /// Unmodified original accepted responses, including a partial donation.
  final List<AccountBlockTemplate> blocks;

  /// Original accepted hashes copied before later observers can mutate blocks.
  final List<String> hashes;

  /// Original failure, retained separately from any earlier accepted blocks.
  final Object? error;

  /// The original trace belonging to [error].
  final StackTrace? stackTrace;
}

final class _ActionEntry {
  _ActionEntry(this.request);
  final AcceleratorActionRequest request;
  final Completer<AcceleratorActionOutcome> completion =
      Completer<AcceleratorActionOutcome>();
  AcceleratorActionOutcome? outcome;
}

/// One retained lane per original wallet, account, chain and operation target.
/// An uncertain original is never replaced or resumed. A deliberate later
/// action requires exact confirmation and fresh effect reads before rearming.
final class AcceleratorActionController {
  /// Session-wide owner retaining original action lanes across view disposal.
  static final AcceleratorActionController shared =
      AcceleratorActionController();
  final Map<Object, _ActionEntry> _entries = <Object, _ActionEntry>{};
  final List<AcceleratorActionOutcome> _history = <AcceleratorActionOutcome>[];

  /// Retired preflight refusals and submissions explicitly rearmed by proof.
  List<AcceleratorActionOutcome> get history =>
      List<AcceleratorActionOutcome>.unmodifiable(_history);

  /// The original terminal outcome still occupying this lane, if settled.
  AcceleratorActionOutcome? retained(
    AcceleratorActionSource source,
    AcceleratorActionRequest request,
  ) => _entries[request.lane(source.scopeKey)]?.outcome;

  /// Whether an unfinished or retained original currently occupies this lane.
  bool holds(
    AcceleratorActionSource source,
    AcceleratorActionRequest request,
  ) => _entries.containsKey(request.lane(source.scopeKey));

  /// Coalesces identical intents and reserves before callbacks can reenter.
  /// A later source change suppresses continuation but cannot cancel a send.
  Future<AcceleratorActionOutcome> submit(
    AcceleratorActionSource source,
    AcceleratorActionRequest request, {
    bool Function()? canContinue,
  }) {
    final Object lane = request.lane(source.scopeKey);
    final _ActionEntry? existing = _entries[lane];
    if (existing != null) {
      if (existing.request.identity == request.identity) {
        return existing.completion.future;
      }
      return Future<AcceleratorActionOutcome>.value(
        AcceleratorActionOutcome(AcceleratorActionState.held),
      );
    }
    final _ActionEntry entry = _ActionEntry(request);
    _entries[lane] = entry;
    unawaited(_run(source, entry, lane, canContinue ?? () => true));
    return entry.completion.future;
  }

  Future<void> _run(
    AcceleratorActionSource source,
    _ActionEntry entry,
    Object lane,
    bool Function() visible,
  ) async {
    final List<AccountBlockTemplate> accepted = <AccountBlockTemplate>[];
    final List<String> hashes = <String>[];
    bool handedOff = false;
    bool freshOriginalProof = false;
    bool allowed() =>
        source.isCurrent && visible() && identical(_entries[lane], entry);
    void requireCurrent() {
      if (!allowed()) throw const AcceleratorActionRefused();
    }

    late AcceleratorActionOutcome outcome;
    try {
      requireCurrent();
      final AcceleratorActionRequest request = entry.request;
      _validateDraft(source, request);
      // Both the builder and sender are original source operations. No mutable
      // globals or changed choices are resolved after a suspension.
      final List<AccountBlockTemplate> templates =
          List<AccountBlockTemplate>.unmodifiable(source.build(request));
      final Future<AccountBlockTemplate> Function(
        AccountBlockTemplate,
        AcceleratorActionKind, {
        required bool Function() canPublish,
      })
      send = source.publish;
      if (templates.isEmpty ||
          templates.length >
              (request.kind == AcceleratorActionKind.donate ? 2 : 1)) {
        throw const AcceleratorActionRefused();
      }
      await _fresh(source, request, requireCurrent);
      requireCurrent();
      freshOriginalProof = true;
      for (final AccountBlockTemplate template in templates) {
        // A second donation is admitted only after a fresh original balance.
        // If the first result is uncertain, no remaining coin is attempted.
        if (accepted.isNotEmpty) {
          await _fresh(
            source,
            request,
            requireCurrent,
            donationZnnAlreadySent: true,
          );
        }
        requireCurrent();
        handedOff = true;
        final Future<AccountBlockTemplate> original = send(
          template,
          request.kind,
          canPublish: () => freshOriginalProof && allowed(),
        );
        final AccountBlockTemplate result = await original;
        accepted.add(result);
        hashes.add(result.hash.toString());
        if (result.hash == emptyHash) throw const AcceleratorActionRefused();
      }
      outcome = AcceleratorActionOutcome(
        AcceleratorActionState.submitted,
        blocks: accepted,
        hashes: hashes,
      );
    } on Object catch (error, stackTrace) {
      outcome = AcceleratorActionOutcome(
        handedOff
            ? AcceleratorActionState.uncertain
            : AcceleratorActionState.refused,
        blocks: accepted,
        hashes: hashes,
        error: error,
        stackTrace: stackTrace,
      );
    }
    entry.outcome = outcome;
    // A known preflight refusal can be corrected. Publication uncertainty and
    // accepted original results remain owned independently of UI lifetime.
    if (outcome.state == AcceleratorActionState.refused &&
        identical(_entries[lane], entry)) {
      _entries.remove(lane);
      _history.add(outcome);
    }
    entry.completion.complete(outcome);
  }

  void _validateDraft(
    AcceleratorActionSource source,
    AcceleratorActionRequest request,
  ) {
    if (request.znn.isNegative ||
        request.qsr.isNegative ||
        request.znn.bitLength > 256 ||
        request.qsr.bitLength > 256) {
      throw const AcceleratorActionRefused();
    }
    if (request.kind == AcceleratorActionKind.vote) {
      if (request.projectId == null ||
          request.targetId == null ||
          request.pillarName == null ||
          request.pillarName!.isEmpty ||
          request.vote == null) {
        throw const AcceleratorActionRefused();
      }
      return;
    }
    if (request.kind == AcceleratorActionKind.donate) {
      if (request.znn == BigInt.zero && request.qsr == BigInt.zero) {
        throw const AcceleratorActionRefused();
      }
      return;
    }
    if (!source.validMetadata(request) ||
        request.znn > source.maximumZnn ||
        request.qsr > source.maximumQsr) {
      throw const AcceleratorActionRefused();
    }
  }

  Future<void> _fresh(
    AcceleratorActionSource source,
    AcceleratorActionRequest request,
    void Function() requireCurrent, {
    bool donationZnnAlreadySent = false,
  }) async {
    requireCurrent();
    if (request.kind == AcceleratorActionKind.createProject ||
        request.kind == AcceleratorActionKind.donate) {
      final AcceleratorActionBalance balance = await source.readBalance();
      requireCurrent();
      final BigInt znn = request.kind == AcceleratorActionKind.createProject
          ? projectCreationFeeInZnn
          : donationZnnAlreadySent
          ? BigInt.zero
          : request.znn;
      if (balance.znn < znn ||
          balance.qsr <
              (request.kind == AcceleratorActionKind.donate
                  ? request.qsr
                  : BigInt.zero)) {
        throw const AcceleratorActionRefused();
      }
      return;
    }
    final String? id = request.projectId;
    if (id == null) throw const AcceleratorActionRefused();
    final Project response = await source.readProject(id);
    requireCurrent();
    final Project project = Project.fromJson(
      AcceleratorProjectCache.projectToJson(response),
    );
    if (project.id.toString() != id) throw const AcceleratorActionRefused();
    final List<String> ids = project.phaseIds
        .map((Hash value) => value.toString())
        .toList();
    final List<String> loadedIds = project.phases
        .map((Phase value) => value.id.toString())
        .toList();
    if (ids.length != ids.toSet().length ||
        ids.length != project.phases.length ||
        loadedIds.length != loadedIds.toSet().length ||
        !ids.every(loadedIds.contains) ||
        !project.phases.every(
          (Phase phase) =>
              ids.contains(phase.id.toString()) &&
              phase.projectId.toString() == id,
        )) {
      throw const AcceleratorActionRefused();
    }
    if (request.kind == AcceleratorActionKind.vote) {
      Phase? selected;
      if (request.phaseId != null) {
        for (final Phase phase in project.phases) {
          if (phase.id.toString() == request.phaseId) selected = phase;
        }
        if (selected == null) throw const AcceleratorActionRefused();
      }
      final AcceleratorVoteTarget target = AcceleratorVoteTarget.fromProject(
        project,
        phase: selected,
      );
      final List<PillarInfo> pillars = await source.readPillars();
      requireCurrent();
      if (pillars.length != 1 ||
          pillars.single.ownerAddress.toString() != source.ownerAddress ||
          pillars.single.name != request.pillarName ||
          AcceleratorVotePolicy.eligibility(
                target: target,
                capturedContextCurrent: source.isCurrent,
                ownerLookupComplete: true,
                exactOwnerPillarName: pillars.single.name,
                nowTimestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              ) !=
              AcceleratorVoteEligibility.eligible) {
        throw const AcceleratorActionRefused();
      }
      // Existing votes are deliberately not excluded. The contract supports
      // change-votes; absence is only a list presentation fact.
      return;
    }
    if (project.znnFundsNeeded > source.maximumZnn ||
        project.qsrFundsNeeded > source.maximumQsr) {
      throw const AcceleratorActionRefused();
    }
    if (project.owner.toString() != source.ownerAddress ||
        ids.join(':') != request.phaseIds.join(':')) {
      throw const AcceleratorActionRefused();
    }
    Phase? current;
    if (ids.isNotEmpty) {
      for (final Phase phase in project.phases) {
        if (phase.id.toString() == ids.last) current = phase;
      }
    }
    if (request.kind == AcceleratorActionKind.createPhase) {
      if (project.status != AcceleratorProjectStatus.active ||
          current != null && current.status != AcceleratorProjectStatus.paid) {
        throw const AcceleratorActionRefused();
      }
    } else if (request.kind == AcceleratorActionKind.updatePhase) {
      if (current == null ||
          current.id.toString() != request.phaseId ||
          current.status != AcceleratorProjectStatus.voting) {
        throw const AcceleratorActionRefused();
      }
    }
    BigInt znn = request.znn;
    BigInt qsr = request.qsr;
    for (final Phase phase in project.phases) {
      if (request.kind == AcceleratorActionKind.updatePhase &&
          phase.id.toString() == request.phaseId) {
        continue;
      }
      znn += phase.znnFundsNeeded;
      qsr += phase.qsrFundsNeeded;
    }
    // checkPhaseFunds includes paid phases. Remaining-by-paid helpers cannot
    // authorize a new allocation or a replacement of the latest phase.
    if (znn > project.znnFundsNeeded || qsr > project.qsrFundsNeeded) {
      throw const AcceleratorActionRefused();
    }
  }

  /// Explicit refresh can rearm a known submission after exact confirmation
  /// and operation-specific current evidence. Uncertain results stay held.
  Future<bool> rearm(
    AcceleratorActionSource source,
    AcceleratorActionRequest request,
  ) async {
    final Object lane = request.lane(source.scopeKey);
    final _ActionEntry? entry = _entries[lane];
    final AcceleratorActionOutcome? result = entry?.outcome;
    if (entry == null) return true;
    if (result == null ||
        !source.isCurrent ||
        result.state != AcceleratorActionState.submitted ||
        result.hashes.isEmpty) {
      return false;
    }
    try {
      for (final String hash in result.hashes) {
        if (!source.isCurrent ||
            !await source.readConfirmed(hash) ||
            !source.isCurrent) {
          return false;
        }
      }
      final AcceleratorActionRequest original = entry.request;
      if (original.kind == AcceleratorActionKind.createProject) {
        final Project project = await source.readProject(result.hashes.single);
        if (!source.isCurrent ||
            !_matches(
              project,
              original,
              source.ownerAddress,
              result.hashes.single,
            )) {
          return false;
        }
      } else if (original.kind == AcceleratorActionKind.createPhase ||
          original.kind == AcceleratorActionKind.updatePhase) {
        final Project project = await source.readProject(original.projectId!);
        if (!source.isCurrent ||
            project.id.toString() != original.projectId ||
            project.owner.toString() != source.ownerAddress) {
          return false;
        }
        final List<Phase> matches = project.phases
            .where((Phase phase) => phase.id.toString() == result.hashes.single)
            .toList();
        if (matches.length != 1 ||
            !project.phaseIds.any(
              (Hash id) => id.toString() == result.hashes.single,
            ) ||
            matches.single.projectId.toString() != original.projectId ||
            matches.single.name != original.name ||
            matches.single.description != original.description ||
            matches.single.url != original.url ||
            matches.single.znnFundsNeeded != original.znn ||
            matches.single.qsrFundsNeeded != original.qsr) {
          return false;
        }
        if (original.kind == AcceleratorActionKind.updatePhase &&
            project.phaseIds.any(
              (Hash id) => id.toString() == original.phaseId,
            )) {
          return false;
        }
      } else if (original.kind == AcceleratorActionKind.vote) {
        final List<PillarVote?> votes = await source.readVotes(
          original.pillarName!,
          <String>[original.targetId!],
        );
        if (!source.isCurrent ||
            votes.length != 1 ||
            votes.single == null ||
            votes.single!.id.toString() != original.targetId ||
            votes.single!.name != original.pillarName ||
            votes.single!.vote != original.vote!.index) {
          return false;
        }
      }
      // A later donation is a separate explicit intent after exact Send
      // confirmation. This does not claim a contract Receive effect.
      if (!source.isCurrent || !identical(_entries[lane], entry)) return false;
      _history.add(result);
      _entries.remove(lane);
      return true;
    } on Object {
      return false;
    }
  }

  bool _matches(
    Project project,
    AcceleratorActionRequest request,
    String owner,
    String id,
  ) =>
      project.id.toString() == id &&
      project.owner.toString() == owner &&
      project.name == request.name &&
      project.description == request.description &&
      project.url == request.url &&
      project.znnFundsNeeded == request.znn &&
      project.qsrFundsNeeded == request.qsr;
}

/// A safe refusal classification with no private source or backend diagnostics.
final class AcceleratorActionRefused implements Exception {
  /// Refuses preflight or revalidation without inventing a replacement intent.
  const AcceleratorActionRefused();
}
