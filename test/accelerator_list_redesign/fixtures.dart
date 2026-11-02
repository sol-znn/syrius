import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_list_binding.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

const int listClock = 2000000;

String listHash(int value) => value.toRadixString(16).padLeft(64, '0');

Project listProject(
  int value, {
  String? owner,
  String? name,
  AcceleratorProjectStatus status = AcceleratorProjectStatus.voting,
  int created = listClock - 100,
  List<int> phases = const <int>[],
  AcceleratorProjectStatus phaseStatus = AcceleratorProjectStatus.voting,
}) => Project.fromJson(<String, dynamic>{
  'id': listHash(value),
  'owner': owner ?? emptyAddress.toString(),
  'name': name ?? 'Project $value',
  'description': 'A synthetic project',
  'url': 'https://example.test/project',
  'znnFundsNeeded': '500000000000',
  'qsrFundsNeeded': '0',
  'creationTimestamp': created,
  'lastUpdateTimestamp': created,
  'status': status.index,
  'phaseIds': phases.map(listHash).toList(),
  'votes': <String, dynamic>{
    'id': listHash(value),
    'yes': 2,
    'no': 1,
    'total': 4,
  },
  'phases': <Map<String, dynamic>>[
    for (final int phase in phases)
      <String, dynamic>{
        'phase': <String, dynamic>{
          'id': listHash(phase),
          'projectID': listHash(value),
          'name': 'Phase $phase',
          'description': 'A synthetic phase',
          'url': 'https://example.test/proof',
          'znnFundsNeeded': '100000000',
          'qsrFundsNeeded': '0',
          'creationTimestamp': created,
          'acceptedTimestamp': 0,
          'status': phaseStatus.index,
        },
        'votes': <String, dynamic>{
          'id': listHash(phase),
          'yes': 3,
          'no': 2,
          'total': 6,
        },
      },
  ],
});

ProjectList listPage(List<Project> projects, {int? count}) =>
    ProjectList.fromJson(
      <String, dynamic>{
        'count': count ?? projects.length,
        'list': projects
            .map(
              (Project project) => <String, dynamic>{
                'id': project.id.toString(),
                'owner': project.owner.toString(),
                'name': project.name,
                'description': project.description,
                'url': project.url,
                'znnFundsNeeded': project.znnFundsNeeded.toString(),
                'qsrFundsNeeded': project.qsrFundsNeeded.toString(),
                'creationTimestamp': project.creationTimestamp,
                'lastUpdateTimestamp': project.lastUpdateTimestamp,
                'status': project.statusInt,
                'phaseIds': project.phaseIds
                    .map((Hash id) => id.toString())
                    .toList(),
                'votes': <String, dynamic>{
                  'id': project.id.toString(),
                  'yes': project.voteBreakdown.yes,
                  'no': project.voteBreakdown.no,
                  'total': project.voteBreakdown.total,
                },
                'phases': <Map<String, dynamic>>[
                  for (final Phase phase in project.phases)
                    <String, dynamic>{
                      'phase': <String, dynamic>{
                        'id': phase.id.toString(),
                        'projectID': phase.projectId.toString(),
                        'name': phase.name,
                        'description': phase.description,
                        'url': phase.url,
                        'znnFundsNeeded': phase.znnFundsNeeded.toString(),
                        'qsrFundsNeeded': phase.qsrFundsNeeded.toString(),
                        'creationTimestamp': phase.creationTimestamp,
                        'acceptedTimestamp': phase.acceptedTimestamp,
                        'status': phase.statusInt,
                      },
                      'votes': <String, dynamic>{
                        'id': phase.id.toString(),
                        'yes': phase.voteBreakdown.yes,
                        'no': phase.voteBreakdown.no,
                        'total': phase.voteBreakdown.total,
                      },
                    },
                ],
              },
            )
            .toList(),
      },
    );

class ListPillar extends Mock implements PillarInfo {}

class ListAccount extends Mock implements AccountInfo {}

class ListBalance extends Mock implements BalanceInfoListItem {}

class ListToken extends Mock implements Token {}

class ListVote extends Mock implements PillarVote {}

PillarInfo listPillar({String name = 'test-pillar', Address? owner}) {
  final ListPillar pillar = ListPillar();
  when(() => pillar.name).thenReturn(name);
  when(() => pillar.ownerAddress).thenReturn(owner ?? emptyAddress);
  return pillar;
}

PillarVote listVote(int id, {String name = 'test-pillar', int vote = 0}) {
  final ListVote result = ListVote();
  when(() => result.id).thenReturn(Hash.parse(listHash(id)));
  when(() => result.name).thenReturn(name);
  when(() => result.vote).thenReturn(vote);
  return result;
}

BalanceInfoListItem listBalance(TokenStandard standard, BigInt? balance) {
  final ListToken token = ListToken();
  when(() => token.tokenStandard).thenReturn(standard);
  when(() => token.decimals).thenReturn(coinDecimals);
  final ListBalance entry = ListBalance();
  when(() => entry.token).thenReturn(token);
  when(() => entry.balance).thenReturn(balance);
  return entry;
}

AccountInfo listAccount({
  List<BalanceInfoListItem>? entries,
  bool unknown = false,
}) {
  final ListAccount account = ListAccount();
  when(() => account.address).thenReturn(acceleratorAddress.toString());
  when(() => account.blockCount).thenReturn(1);
  when(
    () => account.balanceInfoList,
  ).thenReturn(unknown ? null : entries ?? <BalanceInfoListItem>[]);
  return account;
}

AcceleratorListBinding listBinding({
  Set<String>? members,
  bool Function()? current,
  Future<ProjectList> Function(int, int)? pages,
  Future<List<PillarInfo>> Function()? pillars,
  Future<AccountInfo> Function()? fund,
  Future<List<PillarVote?>> Function(String, List<String>)? votes,
}) => AcceleratorListBinding(
  ownerAddress: emptyAddress.toString(),
  walletAddresses: members ?? <String>{emptyAddress.toString()},
  stillCurrent: current ?? () => true,
  readProjects: pages ?? (int page, int size) async => listPage(<Project>[]),
  readPillars: pillars ?? () async => <PillarInfo>[],
  readFund: fund ?? () async => listAccount(),
  readVotes:
      votes ??
      (String name, List<String> ids) async =>
          List<PillarVote?>.filled(ids.length, null),
  readProject: (String id) async => listProject(1),
);
