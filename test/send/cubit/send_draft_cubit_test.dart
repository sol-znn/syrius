import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/cubit/send_draft_cubit.dart';

void main() {
  group('SendDraftCubit', () {
    test('starts empty', () async {
      final SendDraftCubit cubit = SendDraftCubit();
      expect(cubit.state, const SendDraft());
      expect(cubit.state.isEmpty, isTrue);
      await cubit.close();
    });

    blocTest<SendDraftCubit, SendDraft>(
      'save keeps the four values of the form',
      build: SendDraftCubit.new,
      act: (SendDraftCubit cubit) => cubit.save(
        fromAddress: 'z1from',
        tokenStandard: 'zts1znn',
        recipient: 'z1to',
        amount: '1.5',
      ),
      expect: () => <SendDraft>[
        const SendDraft(
          fromAddress: 'z1from',
          tokenStandard: 'zts1znn',
          recipient: 'z1to',
          amount: '1.5',
        ),
      ],
      verify: (SendDraftCubit cubit) => expect(cubit.state.isEmpty, isFalse),
    );

    blocTest<SendDraftCubit, SendDraft>(
      'saving the same values again emits nothing',
      build: SendDraftCubit.new,
      seed: () => const SendDraft(
        fromAddress: 'z1from',
        tokenStandard: 'zts1znn',
        recipient: 'z1to',
        amount: '1.5',
      ),
      act: (SendDraftCubit cubit) => cubit.save(
        fromAddress: 'z1from',
        tokenStandard: 'zts1znn',
        recipient: 'z1to',
        amount: '1.5',
      ),
      expect: () => <SendDraft>[],
    );

    blocTest<SendDraftCubit, SendDraft>(
      'clear forgets a draft, as a send and a lock both must',
      build: SendDraftCubit.new,
      seed: () => const SendDraft(
        fromAddress: 'z1from',
        tokenStandard: 'zts1znn',
        recipient: 'z1to',
        amount: '1.5',
      ),
      act: (SendDraftCubit cubit) => cubit.clear(),
      expect: () => <SendDraft>[const SendDraft()],
    );

    blocTest<SendDraftCubit, SendDraft>(
      'recipient selection preserves the exact amount, sender and token',
      build: SendDraftCubit.new,
      seed: () => const SendDraft(
        fromAddress: 'z1from',
        tokenStandard: 'zts1znn',
        recipient: 'old',
        amount: '1.50000001',
      ),
      act: (SendDraftCubit cubit) => cubit.selectRecipient('exact address'),
      expect: () => <SendDraft>[
        const SendDraft(
          fromAddress: 'z1from',
          tokenStandard: 'zts1znn',
          recipient: 'exact address',
          amount: '1.50000001',
        ),
      ],
    );

    for (final bool changeOwner in <bool>[false, true]) {
      blocTest<SendDraftCubit, SendDraft>(
        'token entry clears another ${changeOwner ? 'owner' : 'asset'} amount',
        build: SendDraftCubit.new,
        seed: () => const SendDraft(
          fromAddress: 'original owner',
          tokenStandard: 'original asset',
          recipient: 'original recipient',
          amount: '9007199254740993.00000001',
        ),
        act: (SendDraftCubit cubit) => cubit.selectToken(
          fromAddress: changeOwner ? 'current owner' : 'original owner',
          tokenStandard: changeOwner ? 'original asset' : 'current asset',
        ),
        expect: () => <SendDraft>[
          SendDraft(
            fromAddress: changeOwner ? 'current owner' : 'original owner',
            tokenStandard: changeOwner ? 'original asset' : 'current asset',
            recipient: 'original recipient',
          ),
        ],
      );
    }

    test(
      'returning to the exact asset preserves the unfinished draft',
      () async {
        final SendDraftCubit cubit = SendDraftCubit()
          ..save(
            fromAddress: 'original owner',
            tokenStandard: 'original asset',
            recipient: 'original recipient',
            amount: '9007199254740993.00000001',
          );
        final SendDraft original = cubit.state;
        cubit.selectToken(
          fromAddress: 'original owner',
          tokenStandard: 'original asset',
        );
        expect(identical(cubit.state, original), isTrue);
        await cubit.close();
        cubit.selectToken(
          fromAddress: 'late owner',
          tokenStandard: 'late asset',
        );
        expect(identical(cubit.state, original), isTrue);
      },
    );

    test('old acceptance clears only the unchanged original draft', () async {
      final SendDraftCubit cubit = SendDraftCubit()
        ..selectRecipient('original');
      final SendDraft original = cubit.state;
      cubit.selectRecipient('new draft');
      expect(cubit.clearIfUnchanged(original), isFalse);
      expect(cubit.state.recipient, 'new draft');
      cubit.selectRecipient('original');
      expect(cubit.state, original);
      expect(cubit.clearIfUnchanged(original), isFalse);
      expect(cubit.state.recipient, 'original');
      expect(cubit.clearIfUnchanged(cubit.state), isTrue);
      expect(cubit.state.isEmpty, isTrue);
      await cubit.close();
      expect(cubit.clearIfUnchanged(const SendDraft()), isFalse);
    });

    blocTest<SendDraftCubit, SendDraft>(
      'recipient selection before mounting carries no invented sender or asset',
      build: SendDraftCubit.new,
      act: (SendDraftCubit cubit) => cubit.selectRecipient('exact address'),
      expect: () => <SendDraft>[
        const SendDraft(recipient: 'exact address'),
      ],
    );
  });
}
