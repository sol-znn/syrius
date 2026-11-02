import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/services/accelerator_project_cache.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_controller.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../accelerator_list_redesign/fixtures.dart';
export '../accelerator_list_redesign/fixtures.dart';

class _Block extends Mock implements AccountBlockTemplate {}

AccountBlockTemplate actionBlock(int id) {
  final _Block block = _Block();
  when(() => block.hash).thenReturn(Hash.parse(listHash(id)));
  return block;
}

Project actionProject({
  AcceleratorProjectStatus status = AcceleratorProjectStatus.active,
  List<int> phases = const <int>[],
  AcceleratorProjectStatus phaseStatus = AcceleratorProjectStatus.voting,
  BigInt? budget,
  String? owner,
  String? name,
}) {
  final Project project = listProject(
    1,
    status: status,
    phases: phases,
    phaseStatus: phaseStatus,
    owner: owner,
    name: name,
  );
  final Map<String, dynamic> json = AcceleratorProjectCache.projectToJson(
    project,
  );
  if (budget != null) json['znnFundsNeeded'] = budget.toString();
  return Project.fromJson(json);
}

/// No production binding, wallet file, signer, profile, network or storage.
class ActionSource implements AcceleratorActionSource {
  ActionSource({Object? scope, String? owner})
    : scopeKey = scope ?? ('synthetic-wallet', emptyAddress.toString(), 1),
      ownerAddress = owner ?? emptyAddress.toString();
  @override
  final Object scopeKey;
  @override
  final String ownerAddress;
  bool current = true;
  bool _revoked = false;
  @override
  bool get isCurrent => !_revoked && !(_revoked = !current);
  @override
  BigInt get maximumZnn => BigInt.from(1000000000000000);
  @override
  BigInt get maximumQsr => BigInt.from(10000000000000000);
  bool metadataValid = true;
  @override
  bool validMetadata(AcceleratorActionRequest request) => metadataValid;
  Project project = actionProject();
  List<PillarInfo> pillars = <PillarInfo>[listPillar()];
  AcceleratorActionBalance balance = AcceleratorActionBalance(
    BigInt.from(1000000000000),
    BigInt.from(1000000000000),
  );
  final List<AcceleratorActionRequest> builders = <AcceleratorActionRequest>[];
  final List<String> projectReads = <String>[];
  final List<String> confirmedReads = <String>[];
  final List<(String, List<String>)> voteReads = <(String, List<String>)>[];
  int ownerReads = 0;
  int balanceReads = 0;
  int publications = 0;
  bool confirmed = false;
  Future<Project> Function(String)? projectReader;
  Future<List<PillarInfo>> Function()? ownerReader;
  Future<AcceleratorActionBalance> Function()? balanceReader;
  Future<List<PillarVote?>> Function(String, List<String>)? voteReader;
  Future<AccountBlockTemplate> Function(AccountBlockTemplate, bool Function())?
  sender;

  @override
  List<AccountBlockTemplate> build(AcceleratorActionRequest request) {
    builders.add(request);
    final int count = request.kind == AcceleratorActionKind.donate
        ? (request.znn > BigInt.zero ? 1 : 0) +
              (request.qsr > BigInt.zero ? 1 : 0)
        : 1;
    return List<AccountBlockTemplate>.generate(
      count,
      (int i) => actionBlock(100 + i),
    );
  }

  @override
  Future<Project> readProject(String id) {
    projectReads.add(id);
    return projectReader?.call(id) ?? Future<Project>.value(project);
  }

  @override
  Future<List<PillarInfo>> readPillars() {
    ownerReads++;
    return ownerReader?.call() ?? Future<List<PillarInfo>>.value(pillars);
  }

  @override
  Future<AcceleratorActionBalance> readBalance() {
    balanceReads++;
    return balanceReader?.call() ??
        Future<AcceleratorActionBalance>.value(balance);
  }

  @override
  Future<List<PillarVote?>> readVotes(String name, List<String> ids) {
    voteReads.add((name, List<String>.of(ids)));
    return voteReader?.call(name, ids) ??
        Future<List<PillarVote?>>.value(
          List<PillarVote?>.filled(ids.length, null),
        );
  }

  @override
  Future<bool> readConfirmed(String hash) async {
    confirmedReads.add(hash);
    return confirmed;
  }

  @override
  Future<AccountBlockTemplate> publish(
    AccountBlockTemplate template,
    AcceleratorActionKind kind, {
    required bool Function() canPublish,
  }) {
    publications++;
    if (!canPublish()) throw const AcceleratorActionRefused();
    return sender?.call(template, canPublish) ??
        Future<AccountBlockTemplate>.value(actionBlock(900 + publications));
  }
}

AcceleratorActionRequest voteRequest({
  int? phase,
  AcceleratorProjectVote choice = AcceleratorProjectVote.yes,
}) => AcceleratorActionRequest(
  kind: AcceleratorActionKind.vote,
  projectId: listHash(1),
  phaseId: phase == null ? null : listHash(phase),
  pillarName: 'test-pillar',
  vote: choice,
);

AcceleratorActionRequest phaseRequest({
  bool update = false,
  List<int> phases = const <int>[],
  int? phase,
  int znn = 100000000,
}) => AcceleratorActionRequest(
  kind: update
      ? AcceleratorActionKind.updatePhase
      : AcceleratorActionKind.createPhase,
  projectId: listHash(1),
  phaseId: phase == null ? null : listHash(phase),
  phaseIds: phases.map(listHash).toList(),
  name: 'New phase',
  description: 'New phase proof',
  url: 'https://example.test/proof',
  znn: BigInt.from(znn),
  qsr: BigInt.zero,
);
