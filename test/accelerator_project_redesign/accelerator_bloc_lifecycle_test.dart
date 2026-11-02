import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/accelerator/vote_project_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_controller.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'support.dart';

class _ThrowingObserver extends VoteProjectBloc {
  _ThrowingObserver({required super.source, required super.controller});
  @override
  void addEvent(AccountBlockTemplate? event) =>
      throw StateError('synthetic display failure');
  @override
  FutureOr<Null> addError(Object error, StackTrace stackTrace) =>
      throw StateError('synthetic observer failure');
}

void main() {
  test(
    'disposed BLoC retains original Future without stale events or new sender',
    () async {
      final AcceleratorActionController actions = AcceleratorActionController();
      final ActionSource source = ActionSource()
        ..project = actionProject(status: AcceleratorProjectStatus.voting);
      final VoteProjectBloc bloc = VoteProjectBloc(
        source: source,
        controller: actions,
      );
      final List<AccountBlockTemplate?> seen = <AccountBlockTemplate?>[];
      final Completer<void> closed = Completer<void>();
      final StreamSubscription<AccountBlockTemplate?> subscription = bloc.stream
          .listen(seen.add, onDone: closed.complete);
      final Completer<AccountBlockTemplate> sender =
          Completer<AccountBlockTemplate>();
      final Completer<void> entered = Completer<void>();
      source.sender = (_, _) {
        entered.complete();
        return sender.future;
      };
      final Future<AcceleratorActionOutcome> original = bloc.voteProject(
        Hash.parse(listHash(1)),
        AcceleratorProjectVote.yes,
        pillarName: 'test-pillar',
      );
      await entered.future;
      bloc.dispose();
      final AccountBlockTemplate block = actionBlock(888);
      sender.complete(block);
      final AcceleratorActionOutcome result = await original;
      await closed.future;
      await subscription.cancel();
      expect(result.state, AcceleratorActionState.submitted);
      expect(identical(result.blocks.single, block), isTrue);
      expect(seen, <AccountBlockTemplate?>[null]);
      final VoteProjectBloc reopened = VoteProjectBloc(
        source: source,
        controller: actions,
      );
      final AcceleratorActionOutcome retained = await reopened.voteProject(
        Hash.parse(listHash(1)),
        AcceleratorProjectVote.yes,
        pillarName: 'test-pillar',
      );
      reopened.dispose();
      expect(identical(retained, result), isTrue);
      expect(source.publications, 1);
    },
  );

  test(
    'failing BLoC observers do not replace the original sender failure',
    () async {
      final ActionSource source = ActionSource()
        ..project = actionProject(status: AcceleratorProjectStatus.voting);
      final StateError original = StateError('original synthetic send outcome');
      source.sender = (_, _) async => throw original;
      final _ThrowingObserver bloc = _ThrowingObserver(
        source: source,
        controller: AcceleratorActionController(),
      );
      final AcceleratorActionOutcome result = await bloc.voteProject(
        Hash.parse(listHash(1)),
        AcceleratorProjectVote.yes,
        pillarName: 'test-pillar',
      );
      bloc.dispose();
      expect(result.state, AcceleratorActionState.uncertain);
      expect(identical(result.error, original), isTrue);
      expect(source.publications, 1);
    },
  );
}
