import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_list_binding.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_list_presenter.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'fixtures.dart';

void main() {
  late AcceleratorListPresenter presenter;

  setUp(() {
    presenter = AcceleratorListPresenter(
      pageSize: 2,
      now: () => DateTime.fromMillisecondsSinceEpoch(listClock * 1000),
    );
  });
  tearDown(() => presenter.dispose());

  test('All includes complete projects for an owner with no Pillar', () async {
    final List<Project> projects = <Project>[
      listProject(1),
      listProject(2, status: AcceleratorProjectStatus.active),
      listProject(3, status: AcceleratorProjectStatus.closed),
      listProject(4, status: AcceleratorProjectStatus.completed),
    ];
    final List<int> asked = <int>[];
    final Future<void> read = presenter.load(
      listBinding(
        pages: (int page, int size) async {
          asked.add(page);
          return listPage(
            page == 0 ? projects.take(2).toList() : projects.skip(2).toList(),
            count: 4,
          );
        },
      ),
    );
    await read;
    presenter.select(AcceleratorListFilter.all);
    expect(
      presenter.rows!.map((AcceleratorListProject row) => row.id).toSet(),
      projects.map((Project project) => project.id.toString()).toSet(),
    );
    expect(asked, <int>[0, 1]);
    expect(presenter.snapshot.needsYourVote(listClock), 0);
  });

  test('Mine retains the captured entire wallet member set', () async {
    final Set<String> members = <String>{
      emptyAddress.toString(),
      pillarAddress.toString(),
    };
    final AcceleratorListBinding source = listBinding(
      members: members,
      pages: (int page, int size) async => listPage(
        <Project>[
          listProject(1),
          listProject(2, owner: pillarAddress.toString()),
          listProject(3, owner: acceleratorAddress.toString()),
        ].skip(page * size).take(size).toList(),
        count: 3,
      ),
    );
    members
      ..clear()
      ..add(acceleratorAddress.toString());
    await presenter.load(source);
    presenter.select(AcceleratorListFilter.mine);
    expect(
      presenter.rows!.map((AcceleratorListProject row) => row.id),
      <String>[listHash(1), listHash(2)],
    );
    presenter.search(listHash(2));
    expect(presenter.rows!.single.id, listHash(2));
    presenter.search('https://example.test/project');
    expect(presenter.rows, hasLength(2));
  });

  test(
    'unstable count, incomplete tail and duplicate ids stay incomplete',
    () async {
      for (final String failure in <String>['count', 'tail', 'duplicate']) {
        await presenter.load(
          listBinding(
            pages: (int page, int size) async {
              if (page == 0) {
                return listPage(<Project>[
                  listProject(1),
                  listProject(2),
                ], count: 3);
              }
              return switch (failure) {
                'count' => listPage(<Project>[listProject(3)], count: 4),
                'tail' => listPage(<Project>[], count: 3),
                _ => listPage(<Project>[listProject(1)], count: 3),
              };
            },
          ),
        );
        expect(presenter.rows, isNull, reason: failure);
        expect(presenter.snapshot.projectsFailed, isTrue, reason: failure);
      }
    },
  );

  test('a short nonterminal page cannot skip unreturned projects', () async {
    final List<int> asked = <int>[];
    await presenter.load(
      listBinding(
        pages: (int page, int size) async {
          asked.add(page);
          return listPage(<Project>[listProject(1)], count: 3);
        },
      ),
    );
    expect(asked, <int>[0]);
    expect(presenter.rows, isNull);
    expect(presenter.snapshot.projectsFailed, isTrue);
  });

  test(
    'a complete empty list and zero fund are actual successful results',
    () async {
      await presenter.load(listBinding());
      expect(presenter.rows, isEmpty);
      expect(presenter.snapshot.projectsFailed, isFalse);
      expect(presenter.snapshot.fund.znn, BigInt.zero);
      expect(presenter.snapshot.fund.qsr, BigInt.zero);
    },
  );

  test('native balances independently preserve zero and unknown', () async {
    await presenter.load(
      listBinding(
        fund: () async => listAccount(
          entries: <BalanceInfoListItem>[
            listBalance(znnZts, BigInt.zero),
            listBalance(qsrZts, null),
          ],
        ),
      ),
    );
    expect(presenter.snapshot.fund.znn, BigInt.zero);
    expect(presenter.snapshot.fund.qsr, isNull);
    await presenter.load(
      listBinding(fund: () async => listAccount(unknown: true)),
    );
    expect(presenter.snapshot.fund.znn, isNull);
    expect(presenter.snapshot.fund.qsr, isNull);
  });

  test(
    'a Pillar failure keeps project and fund outcomes independent',
    () async {
      await presenter.load(
        listBinding(
          pages: (int _, int _) async => listPage(<Project>[listProject(1)]),
          pillars: () async => throw StateError('synthetic owner failure'),
        ),
      );
      expect(presenter.rows!.single.id, listHash(1));
      expect(presenter.snapshot.fund.znn, BigInt.zero);
      expect(presenter.snapshot.ownerLookupComplete, isFalse);
      expect(presenter.snapshot.needsYourVote(listClock), isNull);
    },
  );

  test('foreign or ambiguous owned Pillars never choose a sender', () async {
    for (final List<PillarInfo> pillars in <List<PillarInfo>>[
      <PillarInfo>[listPillar(owner: pillarAddress)],
      <PillarInfo>[listPillar(), listPillar(name: 'second')],
    ]) {
      await presenter.load(
        listBinding(
          pillars: () async => pillars,
          pages: (int _, int _) async => listPage(<Project>[listProject(1)]),
        ),
      );
      expect(presenter.snapshot.ownerLookupComplete, isFalse);
      expect(presenter.snapshot.needsYourVote(listClock), isNull);
    }
  });

  test('Your vote requires exact complete positional absence', () async {
    await presenter.load(
      listBinding(
        pages: (int _, int _) async => listPage(<Project>[
          listProject(1),
          listProject(
            2,
            status: AcceleratorProjectStatus.active,
            phases: <int>[20],
          ),
        ]),
        pillars: () async => <PillarInfo>[listPillar()],
        votes: (String name, List<String> ids) async => <PillarVote?>[
          null,
          listVote(20),
        ],
      ),
    );
    expect(presenter.snapshot.needsYourVote(listClock), 1);
    expect(
      presenter.snapshot.needsVote(presenter.rows!.first, listClock),
      isTrue,
    );
    expect(
      presenter.snapshot.needsVote(presenter.rows!.last, listClock),
      isFalse,
    );
  });

  test('short, foreign, reordered and invalid votes remain unknown', () async {
    for (final List<PillarVote?> votes in <List<PillarVote?>>[
      <PillarVote?>[],
      <PillarVote?>[listVote(2)],
      <PillarVote?>[listVote(1, name: 'other-pillar')],
      <PillarVote?>[listVote(1, vote: 99)],
    ]) {
      await presenter.load(
        listBinding(
          pages: (int _, int _) async => listPage(<Project>[listProject(1)]),
          pillars: () async => <PillarInfo>[listPillar()],
          votes: (String _, List<String> _) async => votes,
        ),
      );
      expect(presenter.snapshot.votesComplete, isFalse);
      expect(presenter.snapshot.needsYourVote(listClock), isNull);
    }
  });

  test(
    'a complete reordered response cannot prove either vote absent',
    () async {
      await presenter.load(
        listBinding(
          pages: (int _, int _) async => listPage(<Project>[
            listProject(1),
            listProject(2),
          ]),
          pillars: () async => <PillarInfo>[listPillar()],
          votes: (String _, List<String> _) async => <PillarVote?>[
            listVote(2),
            listVote(1),
          ],
        ),
      );
      expect(presenter.snapshot.votesComplete, isFalse);
      expect(presenter.snapshot.needsYourVote(listClock), isNull);
    },
  );

  test(
    'superseded original read completes without replacing new facts',
    () async {
      final Completer<ProjectList> original = Completer<ProjectList>();
      final Future<void> first = presenter.load(
        listBinding(
          pages: (int _, int _) => original.future,
        ),
      );
      await presenter.load(
        listBinding(
          pages: (int _, int _) async => listPage(<Project>[listProject(2)]),
        ),
      );
      original.complete(listPage(<Project>[listProject(1)]));
      await first;
      expect(presenter.rows!.single.id, listHash(2));
    },
  );

  test('a context round trip permanently revokes its original read', () async {
    bool current = true;
    final AcceleratorListBinding source = listBinding(current: () => current);
    expect(source.isCurrent, isTrue);
    current = false;
    expect(source.isCurrent, isFalse);
    current = true;
    expect(source.isCurrent, isFalse);
    await presenter.load(source);
    expect(presenter.rows, isNull);
  });

  test(
    'a late original failure cannot replace independent new outcomes',
    () async {
      final Completer<ProjectList> original = Completer<ProjectList>();
      final Future<void> first = presenter.load(
        listBinding(
          pages: (int _, int _) => original.future,
        ),
      );
      await presenter.load(listBinding());
      original.completeError(StateError('original synthetic failure'));
      await first;
      expect(presenter.rows, isEmpty);
      expect(presenter.snapshot.projectsFailed, isFalse);
    },
  );

  test(
    'disposal waits for no replacement and observes the original completion',
    () async {
      final AcceleratorListPresenter transient = AcceleratorListPresenter();
      final Completer<ProjectList> original = Completer<ProjectList>();
      final Future<void> read = transient.load(
        listBinding(
          pages: (int _, int _) => original.future,
        ),
      );
      int changes = 0;
      transient
        ..addListener(() => changes++)
        ..dispose();
      original.complete(listPage(<Project>[listProject(1)]));
      await read;
      expect(changes, 0);
    },
  );
}
