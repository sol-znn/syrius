import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/pow_generating_status_bloc.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

void main() {
  late PowGeneratingStatusBloc bloc;

  setUp(() => bloc = PowGeneratingStatusBloc());
  tearDown(() => bloc.dispose());

  test(
    'initial and newly claimed work are idle without an SDK start',
    () async {
      expect(bloc.value.phase, PowGenerationPhase.idle);
      expect(bloc.value.work, isNull);
      final PowWorkToken work = bloc.claimWork();
      expect(bloc.ownsWork(work), isTrue);
      expect((await bloc.stream.first).phase, PowGenerationPhase.idle);
      expect(bloc.value.isGenerating, isFalse);
    },
  );

  test('release replays idle without inventing SDK completion', () async {
    final PowWorkToken work = bloc.claimWork();
    final Future<void> observed = expectLater(
      bloc.stream.take(3).map((PowGenerationState state) => state.phase),
      emitsInOrder(<PowGenerationPhase>[
        PowGenerationPhase.idle,
        PowGenerationPhase.generating,
        PowGenerationPhase.idle,
      ]),
    );
    expect(bloc.update(work, PowStatus.generating), isTrue);
    bloc.release(work);
    await observed;
    expect(bloc.ownsWork(work), isFalse);
    expect((await bloc.stream.first).phase, PowGenerationPhase.idle);
    expect(bloc.update(work, PowStatus.done), isFalse);
  });

  test(
    'only actual done completes an owner and duplicates cannot restart it',
    () {
      final PowWorkToken work = bloc.claimWork();
      expect(bloc.update(work, PowStatus.generating), isTrue);
      expect(bloc.update(work, PowStatus.generating), isFalse);
      expect(bloc.update(work, PowStatus.done), isTrue);
      expect(bloc.value.phase, PowGenerationPhase.completed);
      expect(bloc.value.work, same(work));
      expect(bloc.update(work, PowStatus.done), isFalse);
      expect(bloc.update(work, PowStatus.generating), isFalse);
      bloc.release(work);
      expect(bloc.value.phase, PowGenerationPhase.idle);
    },
  );

  test(
    'a done-only SDK callback remains factual without an invented start',
    () {
      final PowWorkToken work = bloc.claimWork();
      expect(bloc.update(work, PowStatus.done), isTrue);
      expect(bloc.value.phase, PowGenerationPhase.completed);
      expect(bloc.value.isGenerating, isFalse);
    },
  );

  test('old callbacks and release cannot replace or clear fresh work', () {
    final PowWorkToken old = bloc.claimWork();
    bloc.update(old, PowStatus.generating);
    final PowWorkToken current = bloc.claimWork();
    expect(bloc.value.phase, PowGenerationPhase.idle);
    bloc.update(current, PowStatus.generating);
    expect(bloc.update(old, PowStatus.done), isFalse);
    expect(bloc.update(old, PowStatus.generating), isFalse);
    bloc.release(old);
    expect(bloc.value.work, same(current));
    expect(bloc.value.isGenerating, isTrue);
    expect(bloc.ownsWork(current), isTrue);
  });

  test('invalidation permanently revokes a token through later claims', () {
    final PowWorkToken old = bloc.claimWork();
    bloc
      ..update(old, PowStatus.generating)
      ..invalidate();
    expect(bloc.value.phase, PowGenerationPhase.idle);
    expect(bloc.update(old, PowStatus.generating), isFalse);
    final PowWorkToken current = bloc.claimWork();
    bloc
      ..update(current, PowStatus.generating)
      ..release(old);
    expect(bloc.update(old, PowStatus.done), isFalse);
    expect(bloc.value.work, same(current));
  });

  test('a token from another source has no authority over this display', () {
    final PowGeneratingStatusBloc other = PowGeneratingStatusBloc();
    addTearDown(other.dispose);
    final PowWorkToken foreign = other.claimWork();
    final PowWorkToken current = bloc.claimWork();
    bloc.update(current, PowStatus.generating);
    expect(bloc.update(foreign, PowStatus.done), isFalse);
    bloc.release(foreign);
    expect(bloc.value.work, same(current));
  });

  test(
    'disposal forgets work and leaves all later display calls inert',
    () async {
      final PowWorkToken work = bloc.claimWork();
      bloc.update(work, PowStatus.generating);
      final Future<void> closed = bloc.stream.drain<void>();
      bloc.dispose();
      await closed;
      expect(bloc.value.phase, PowGenerationPhase.idle);
      final PowWorkToken later = bloc.claimWork();
      expect(bloc.ownsWork(later), isFalse);
      expect(bloc.update(work, PowStatus.done), isFalse);
      expect(bloc.update(later, PowStatus.generating), isFalse);
      expect(() => bloc.release(work), returnsNormally);
      expect(bloc.invalidate, returnsNormally);
      expect(bloc.dispose, returnsNormally);
    },
  );
}
