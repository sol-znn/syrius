import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:zenon_syrius_wallet_flutter/services/accelerator_project_cache.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_list_binding.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_vote_policy.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Local project-list selection, independent of publication permission.
enum AcceleratorListFilter {
  /// Projects with an eligible display voting window on a project or phase.
  voting,

  /// Projects whose original response reports active status.
  active,

  /// Projects owned by a member of the captured original wallet.
  mine,

  /// Every project from the complete original page result.
  all,
}

/// A validated tally for one exact hash. Invalid tallies remain unknown.
final class AcceleratorListTally {
  /// Records nonnegative vote counts after exact-target tally validation.
  const AcceleratorListTally(this.yes, this.no, this.abstain);

  /// Original affirmative vote count.
  final int yes;

  /// Original negative vote count.
  final int no;

  /// Original abstaining count derived from the validated tally total.
  final int abstain;

  /// The returned tally total, without claiming an active-Pillar denominator.
  int get total => yes + no + abstain;

  /// Returns unknown for a foreign hash or inconsistent original vote counts.
  static AcceleratorListTally? from(VoteBreakdown votes, String id) {
    if (votes.id.toString() != id ||
        votes.yes < 0 ||
        votes.no < 0 ||
        votes.total < votes.yes + votes.no) {
      return null;
    }
    return AcceleratorListTally(
      votes.yes,
      votes.no,
      votes.total - votes.yes - votes.no,
    );
  }
}

/// Scalars and exact target identities copied before another asynchronous read.
final class AcceleratorListProject {
  AcceleratorListProject._(this._project)
    : id = _project.id.toString(),
      owner = _project.owner.toString(),
      name = _project.name,
      description = _project.description,
      url = _project.url,
      creationTimestamp = _project.creationTimestamp,
      lastUpdateTimestamp = _project.lastUpdateTimestamp,
      znn = _project.znnFundsNeeded,
      qsr = _project.qsrFundsNeeded,
      status = _project.status,
      targets = List<AcceleratorVoteTarget>.unmodifiable(
        <AcceleratorVoteTarget>[
          AcceleratorVoteTarget.fromProject(_project),
          for (final Phase phase in _project.phases)
            AcceleratorVoteTarget.fromProject(_project, phase: phase),
        ],
      );

  /// Copies the complete original response before another asynchronous read.
  factory AcceleratorListProject.fromProject(Project project) =>
      AcceleratorListProject._(
        Project.fromJson(AcceleratorProjectCache.projectToJson(project)),
      );

  final Project _project;

  /// Exact original project hash.
  final String id;

  /// Canonical original owner address.
  final String owner;

  /// Copied original project name.
  final String name;

  /// Copied original project description.
  final String description;

  /// Copied original project URL, never resolved during an action callback.
  final String url;

  /// Original creation time in Unix seconds, used by local list ordering.
  final int creationTimestamp;

  /// Original last-update time in Unix seconds.
  final int lastUpdateTimestamp;

  /// Exact requested ZNN funding in native units.
  final BigInt znn;

  /// Exact requested QSR funding in native units.
  final BigInt qsr;

  /// Status copied from the original project response.
  final AcceleratorProjectStatus status;

  /// Copied project and phase targets with their original membership facts.
  final List<AcceleratorVoteTarget> targets;

  /// Details get another copy; the list's copied facts cannot be mutated there.
  Project toProject() =>
      Project.fromJson(AcceleratorProjectCache.projectToJson(_project));

  /// Whether any copied target has a display voting window at Unix time [now].
  bool votingAt(int now) => targets.any(
    (AcceleratorVoteTarget target) =>
        AcceleratorVotePolicy.hasVotingWindow(target, nowTimestamp: now),
  );

  /// Uses the latest displayed voting-phase tally, otherwise the project tally.
  AcceleratorListTally? tallyAt(int now) {
    for (final Phase phase in _project.phases.reversed) {
      final AcceleratorVoteTarget target = AcceleratorVoteTarget.fromProject(
        _project,
        phase: phase,
      );
      if (AcceleratorVotePolicy.hasVotingWindow(target, nowTimestamp: now)) {
        return AcceleratorListTally.from(
          phase.voteBreakdown,
          phase.id.toString(),
        );
      }
    }
    return AcceleratorListTally.from(_project.voteBreakdown, id);
  }
}

/// Native balances are independent: a missing or invalid coin is not zero.
final class AcceleratorListFund {
  /// Records independently known native amounts; null remains unknown.
  const AcceleratorListFund({this.znn, this.qsr});

  /// Validates exact native entries from the original Accelerator account.
  factory AcceleratorListFund.fromAccount(AccountInfo account) {
    final List<BalanceInfoListItem>? entries = account.balanceInfoList;
    if (account.address != acceleratorAddress.toString() ||
        account.blockCount == null ||
        account.blockCount! < 0 ||
        entries == null ||
        account.blockCount == 0 && entries.isNotEmpty) {
      return const AcceleratorListFund();
    }
    BigInt? native(TokenStandard standard) {
      BalanceInfoListItem? found;
      for (final BalanceInfoListItem entry in entries) {
        final Token? token = entry.token;
        // An unidentified entry could be another native entry.
        if (token == null) return null;
        if (token.tokenStandard != standard) continue;
        if (found != null) return null;
        found = entry;
      }
      if (found == null) return BigInt.zero;
      final BigInt? value = found.balance;
      if (found.token!.decimals != coinDecimals ||
          value == null ||
          value.isNegative ||
          value.bitLength > 256) {
        return null;
      }
      return value;
    }

    return AcceleratorListFund(znn: native(znnZts), qsr: native(qsrZts));
  }

  /// Exact ZNN native balance, or null when its original proof is incomplete.
  final BigInt? znn;

  /// Exact QSR native balance, or null when its original proof is incomplete.
  final BigInt? qsr;
}

/// A source-bound display receipt, including explicit incomplete outcomes.
final class AcceleratorListSnapshot {
  /// Captures display facts without converting missing proof into zero.
  AcceleratorListSnapshot({
    required this.binding,
    required this.projects,
    required this.fund,
    required this.ownerLookupComplete,
    required this.pillarName,
    required this.votesComplete,
    required Map<String, int?> votes,
    required this.projectsFailed,
    required this.reading,
  }) : votes = Map<String, int?>.unmodifiable(votes);

  /// Original read source whose authority still governs these facts.
  final AcceleratorListBinding? binding;

  /// Complete copied project list, or null before a complete response exists.
  final List<AcceleratorListProject>? projects;

  /// Independently validated native fund amounts.
  final AcceleratorListFund fund;

  /// Whether a complete unambiguous lookup established original ownership.
  final bool ownerLookupComplete;

  /// The exact owned Pillar name, or null when no owned Pillar was returned.
  final String? pillarName;

  /// Whether all requested positional original vote results were validated.
  final bool votesComplete;

  /// Exact target-to-vote facts; present null values mean proven absent votes.
  final Map<String, int?> votes;

  /// Whether the original project-page read failed or was incomplete.
  final bool projectsFailed;

  /// Whether this source's requested list reads are still being observed.
  final bool reading;

  /// Whether the original binding still owns its captured resources.
  bool get isCurrent => binding?.isCurrent ?? false;

  /// Null means absent proof, while zero is a complete actual outcome.
  int? needsYourVote(int now) {
    if (!isCurrent || projects == null || !ownerLookupComplete) return null;
    if (pillarName == null) return 0;
    if (!votesComplete) return null;
    return projects!
        .where((AcceleratorListProject row) => needsVote(row, now))
        .length;
  }

  /// Whether exact current ownership and vote reads prove an absent vote.
  bool needsVote(AcceleratorListProject row, int now) =>
      isCurrent &&
      votesComplete &&
      row.targets.any(
        (AcceleratorVoteTarget target) =>
            AcceleratorVotePolicy.eligibility(
                  target: target,
                  capturedContextCurrent: isCurrent,
                  ownerLookupComplete: ownerLookupComplete,
                  exactOwnerPillarName: pillarName,
                  nowTimestamp: now,
                ) ==
                AcceleratorVoteEligibility.eligible &&
            votes.containsKey(target.targetId) &&
            votes[target.targetId] == null,
      );
}

/// Complete node pages and exact owner results, without signing or storage.
final class AcceleratorListPresenter extends ChangeNotifier {
  /// A smaller page size keeps isolated source fixtures finite.
  AcceleratorListPresenter({
    DateTime Function()? now,
    int pageSize = rpcMaxPageSize,
  }) : assert(
         pageSize > 0 && pageSize <= rpcMaxPageSize,
         'Page size must be within the existing RPC limit.',
       ),
       _pageSize = pageSize,
       _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final int _pageSize;
  AcceleratorListBinding? _binding;
  Object? _request;
  bool _disposed = false;
  List<AcceleratorListProject>? _projects;
  AcceleratorListFund _fund = const AcceleratorListFund();
  bool _ownerComplete = false;
  String? _pillarName;
  bool _votesComplete = false;
  Map<String, int?> _votes = <String, int?>{};
  bool _projectsFailed = false;
  bool _reading = false;
  AcceleratorListFilter _filter = AcceleratorListFilter.voting;
  String _query = '';
  bool _newestFirst = true;

  /// Current local list selection, retained across source refreshes.
  AcceleratorListFilter get filter => _filter;

  /// Original search text, normalized only when matching displayed rows.
  String get query => _query;

  /// Whether original creation times sort descending rather than ascending.
  bool get newestFirst => _newestFirst;

  /// Current display time in Unix seconds from the captured clock capability.
  int get nowTimestamp => _now().millisecondsSinceEpoch ~/ 1000;

  /// Current source-bound facts, including explicit unknown and partial states.
  AcceleratorListSnapshot get snapshot => AcceleratorListSnapshot(
    binding: _binding,
    projects: _projects,
    fund: _fund,
    ownerLookupComplete: _ownerComplete,
    pillarName: _pillarName,
    votesComplete: _votesComplete,
    votes: _votes,
    projectsFailed: _projectsFailed,
    reading: _reading,
  );

  /// Filtered, searched and stably sorted rows from a complete current source.
  List<AcceleratorListProject>? get rows {
    final AcceleratorListSnapshot source = snapshot;
    if (!source.isCurrent || source.projects == null) return null;
    final int now = nowTimestamp;
    final String term = _query.trim().toLowerCase();
    final List<AcceleratorListProject> shown =
        source.projects!.where(
          (AcceleratorListProject row) {
            final bool includes = switch (_filter) {
              AcceleratorListFilter.voting => row.votingAt(now),
              AcceleratorListFilter.active =>
                row.status == AcceleratorProjectStatus.active,
              AcceleratorListFilter.mine =>
                source.binding!.walletAddresses.contains(row.owner),
              AcceleratorListFilter.all => true,
            };
            return includes &&
                (term.isEmpty ||
                    <String>[
                      row.id,
                      row.owner,
                      row.name,
                      row.description,
                      row.url,
                    ].any(
                      (String value) => value.toLowerCase().contains(term),
                    ));
          },
        ).toList()..sort((AcceleratorListProject a, AcceleratorListProject b) {
          final int time = _newestFirst
              ? b.creationTimestamp.compareTo(a.creationTimestamp)
              : a.creationTimestamp.compareTo(b.creationTimestamp);
          return time == 0 ? a.id.compareTo(b.id) : time;
        });
    return List<AcceleratorListProject>.unmodifiable(shown);
  }

  /// Updates the local filter without starting new reads or wallet actions.
  void select(AcceleratorListFilter value) {
    if (_disposed || value == _filter) return;
    _filter = value;
    notifyListeners();
  }

  /// Updates local search while retaining the original source snapshot.
  void search(String value) {
    if (_disposed || value == _query) return;
    _query = value;
    notifyListeners();
  }

  /// Reverses creation-time ordering, retaining exact hash tie-breaking.
  void toggleSort() {
    if (_disposed) return;
    _newestFirst = !_newestFirst;
    notifyListeners();
  }

  /// Revokes painted facts synchronously, before starting replacement reads.
  void invalidate() {
    if (_disposed) return;
    _request = null;
    _binding = null;
    _projects = null;
    _fund = const AcceleratorListFund();
    _ownerComplete = false;
    _pillarName = null;
    _votesComplete = false;
    _votes = <String, int?>{};
    _projectsFailed = false;
    _reading = false;
    notifyListeners();
  }

  bool _owns(Object request, AcceleratorListBinding source) =>
      !_disposed && identical(request, _request) && source.isCurrent;

  /// Loads complete original pages and independent owner, fund and vote facts.
  /// Superseded replies cannot repaint a replacement source generation.
  Future<void> load(AcceleratorListBinding source) async {
    if (_disposed) return;
    invalidate();
    final Object request = Object();
    _request = request;
    _binding = source;
    _reading = true;
    notifyListeners();
    await Future.wait<void>(<Future<void>>[
      _readProjects(request, source),
      _readPillar(request, source),
      _readFund(request, source),
    ]);
    if (!_owns(request, source)) return;
    await _readVotes(request, source);
    if (!_owns(request, source)) return;
    _reading = false;
    notifyListeners();
  }

  Future<void> _readProjects(
    Object request,
    AcceleratorListBinding source,
  ) async {
    try {
      final List<AcceleratorListProject> all = <AcceleratorListProject>[];
      final Set<String> seen = <String>{};
      int? count;
      for (int page = 0; page < 10000; page++) {
        if (!_owns(request, source)) return;
        final ProjectList got = await source.readProjects(page, _pageSize);
        if (!_owns(request, source)) return;
        count ??= got.count;
        if (count < 0 || got.count != count || got.list.length > _pageSize) {
          throw const FormatException('Incomplete Accelerator projects');
        }
        for (final Project project in got.list) {
          final AcceleratorListProject copy =
              AcceleratorListProject.fromProject(project);
          if (!seen.add(copy.id)) {
            throw const FormatException('Repeated Accelerator project');
          }
          all.add(copy);
        }
        if (all.length > count ||
            got.list.length < _pageSize && all.length != count) {
          throw const FormatException('Incomplete Accelerator projects');
        }
        if (all.length == count) {
          _projects = List<AcceleratorListProject>.unmodifiable(all);
          notifyListeners();
          return;
        }
      }
      throw const FormatException('Accelerator project page limit');
    } on Object {
      if (!_owns(request, source)) return;
      _projectsFailed = true;
      notifyListeners();
    }
  }

  Future<void> _readPillar(
    Object request,
    AcceleratorListBinding source,
  ) async {
    try {
      if (!_owns(request, source)) return;
      final List<PillarInfo> pillars = await source.readPillars();
      if (!_owns(request, source)) return;
      // An ambiguous multi-Pillar result does not choose an arbitrary sender.
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
      // Projects and fund reads retain their independent outcomes.
    }
  }

  Future<void> _readFund(Object request, AcceleratorListBinding source) async {
    try {
      if (!_owns(request, source)) return;
      final AccountInfo account = await source.readFund();
      if (!_owns(request, source)) return;
      _fund = AcceleratorListFund.fromAccount(account);
      notifyListeners();
    } on Object {
      // Unavailable balances remain unknown for each coin.
    }
  }

  Future<void> _readVotes(Object request, AcceleratorListBinding source) async {
    if (_projects == null || !_ownerComplete) return;
    if (_pillarName == null) {
      _votesComplete = true;
      return;
    }
    final String name = _pillarName!;
    final List<String> ids = List<String>.unmodifiable(<String>[
      for (final AcceleratorListProject row in _projects!)
        for (final AcceleratorVoteTarget target in row.targets)
          if (AcceleratorVotePolicy.hasVotingWindow(
            target,
            nowTimestamp: nowTimestamp,
          ))
            target.targetId,
    ]);
    final Map<String, int?> complete = <String, int?>{};
    try {
      // The RPC returns one positional entry per requested hash. A short,
      // foreign or reordered response cannot establish an absent vote.
      for (int start = 0; start < ids.length; start += rpcMaxPageSize) {
        if (!_owns(request, source)) return;
        final List<String> batch = List<String>.unmodifiable(
          ids.skip(start).take(rpcMaxPageSize),
        );
        final List<PillarVote?> votes = await source.readVotes(name, batch);
        if (!_owns(request, source)) return;
        if (votes.length != batch.length) {
          throw const FormatException('Incomplete Accelerator votes');
        }
        for (int i = 0; i < batch.length; i++) {
          final PillarVote? vote = votes[i];
          if (complete.containsKey(batch[i]) ||
              vote != null &&
                  (vote.id.toString() != batch[i] ||
                      vote.name != name ||
                      vote.vote < 0 ||
                      vote.vote >= AcceleratorProjectVote.values.length)) {
            throw const FormatException('Foreign Accelerator vote');
          }
          complete[batch[i]] = vote?.vote;
        }
      }
      _votes = complete;
      _votesComplete = true;
      notifyListeners();
    } on Object {
      // Unknown vote membership cannot paint the actionable Your vote state.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _request = null;
    super.dispose();
  }
}
