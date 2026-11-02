import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../../helpers/hydrated_bloc.dart';

class MockZenon extends Mock implements Zenon {}

class MockWsClient extends Mock implements WsClient {}

class MockEmbedded extends Mock implements EmbeddedApi {}

class MockPillar extends Mock implements PillarApi {}

class MockPillarInfoList extends Mock implements PillarInfoList {}

class MockPillarInfo extends Mock implements PillarInfo {}

void main() {
  initHydratedStorage();

  group('ActivePillarsCubit', () {
    late MockZenon mockZenon;
    late MockWsClient mockWsClient;
    late MockEmbedded mockEmbedded;
    late MockPillar mockPillar;
    late MockPillarInfoList mockPillarInfoList;
    late ActivePillarsCubit cubit;

    setUp(() {
      mockZenon = MockZenon();
      mockWsClient = MockWsClient();
      mockEmbedded = MockEmbedded();
      mockPillar = MockPillar();
      mockPillarInfoList = MockPillarInfoList();

      when(() => mockZenon.wsClient).thenReturn(mockWsClient);
      when(() => mockWsClient.isClosed()).thenReturn(false);
      when(() => mockZenon.embedded).thenReturn(mockEmbedded);
      when(() => mockEmbedded.pillar).thenReturn(mockPillar);
      when(
        () => mockPillarInfoList.list,
      ).thenReturn(<PillarInfo>[MockPillarInfo(), MockPillarInfo()]);
      when(() => mockPillarInfoList.count).thenReturn(97);
      when(
        () => mockPillar.getAll(),
      ).thenAnswer((_) async => mockPillarInfoList);

      cubit = ActivePillarsCubit(zenon: mockZenon);
    });

    test('initial status is initial', () {
      expect(cubit.state.status, TimerStatus.initial);
    });

    blocTest<ActivePillarsCubit, ActivePillarsState>(
      'uses the response total rather than the returned page length',
      build: () => cubit,
      act: (ActivePillarsCubit cubit) => cubit.fetchDataPeriodically(),
      verify: (_) {
        verify(() => mockPillar.getAll()).called(1);
      },
      expect: () => <ActivePillarsState>[
        const ActivePillarsState(status: TimerStatus.loading),
        const ActivePillarsState(status: TimerStatus.success, data: 97),
      ],
    );

    blocTest<ActivePillarsCubit, ActivePillarsState>(
      'an empty page does not erase a known response total',
      setUp: () {
        when(() => mockPillarInfoList.list).thenReturn(<PillarInfo>[]);
      },
      build: () => cubit,
      act: (ActivePillarsCubit cubit) => cubit.fetchDataPeriodically(),
      expect: () => <ActivePillarsState>[
        const ActivePillarsState(status: TimerStatus.loading),
        const ActivePillarsState(status: TimerStatus.success, data: 97),
      ],
    );

    blocTest<ActivePillarsCubit, ActivePillarsState>(
      'preserves an actual zero total',
      setUp: () {
        when(() => mockPillarInfoList.count).thenReturn(0);
      },
      build: () => cubit,
      act: (ActivePillarsCubit cubit) => cubit.fetchDataPeriodically(),
      expect: () => <ActivePillarsState>[
        const ActivePillarsState(status: TimerStatus.loading),
        const ActivePillarsState(status: TimerStatus.success, data: 0),
      ],
    );

    blocTest<ActivePillarsCubit, ActivePillarsState>(
      'emits loading then failure when api throws',
      setUp: () {
        when(() => mockPillar.getAll()).thenThrow(FailureException());
      },
      build: () => cubit,
      act: (ActivePillarsCubit cubit) => cubit.fetchDataPeriodically(),
      expect: () => <Matcher>[
        isA<ActivePillarsState>().having(
          (ActivePillarsState s) => s.status,
          'status',
          TimerStatus.loading,
        ),
        isA<ActivePillarsState>().having(
          (ActivePillarsState s) => s.status,
          'status',
          TimerStatus.failure,
        ),
      ],
    );
  });
}
