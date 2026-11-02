import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/create_token_stepper/model/token_create_publisher.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'support.dart';

void main() {
  AccountBlockTemplate block([int chain = 321]) => AccountBlockTemplate(
    blockType: BlockTypeEnum.userSend.index,
  )..chainIdentifier = chain;

  test(
    'forwards the original Future and exact accepted result through close',
    () async {
      final TokenCreateFixture fixture = TokenCreateFixture();
      addTearDown(fixture.dispose);
      await fixture.preflight.refresh();
      final TokenCreateTransport transport = TokenCreateTransport();
      final TokenCreatePublisher publisher = TokenCreatePublisher(
        publisher: transport,
        preflight: fixture.preflight,
      );
      expect(publisher.canStartNewAttempt, isTrue);
      expect(publisher.isUncertain, isFalse);
      final Future<AccountBlockTemplate> original = publisher
          .createAccountBlock(
            block(),
            'Fixture issue',
            address: emptyAddress,
          );
      expect(original, same(transport.response.future));
      expect(transport.calls.single.predicate!(), isTrue);
      fixture.preflight.closePresentation();
      expect(transport.calls.single.predicate!(), isFalse);
      final AccountBlockTemplate accepted = block();
      transport.response.complete(accepted);
      expect(await original, same(accepted));
      expect(transport.calls, hasLength(1));
    },
  );

  test(
    'composes caller authority and the original fresh read ticket',
    () async {
      final TokenCreateFixture fixture = TokenCreateFixture();
      addTearDown(fixture.dispose);
      await fixture.preflight.refresh();
      final TokenCreateTransport transport = TokenCreateTransport();
      final TokenCreatePublisher publisher = TokenCreatePublisher(
        publisher: transport,
        preflight: fixture.preflight,
      );
      bool caller = true;
      final Future<AccountBlockTemplate> original = publisher
          .createAccountBlock(
            block(),
            'Fixture issue',
            canPublish: () => caller,
          );
      final bool Function() predicate = transport.calls.single.predicate!;
      caller = false;
      expect(predicate(), isFalse);
      caller = true;
      expect(predicate(), isTrue);
      await fixture.preflight.refresh();
      expect(predicate(), isFalse);
      final AccountBlockTemplate accepted = block();
      transport.response.complete(accepted);
      expect(await original, same(accepted));
    },
  );

  test(
    'unknown balance, foreign owner and chain refuse before transport',
    () async {
      final TokenCreateFixture fixture = TokenCreateFixture();
      addTearDown(fixture.dispose);
      final TokenCreateTransport transport = TokenCreateTransport();
      final TokenCreatePublisher publisher = TokenCreatePublisher(
        publisher: transport,
        preflight: fixture.preflight,
      );
      await expectLater(
        publisher.createAccountBlock(block(), 'Fixture'),
        throwsA(anything),
      );
      await fixture.preflight.refresh();
      await expectLater(
        publisher.createAccountBlock(block(1), 'Fixture'),
        throwsA(anything),
      );
      await expectLater(
        publisher.createAccountBlock(
          block(),
          'Fixture',
          address: Address.parse('z1qq6eg8n43g032hanpsfp02qcdmv7zfj3y2lt5d'),
        ),
        throwsA(anything),
      );
      expect(transport.calls, isEmpty);
    },
  );

  test(
    'original failure identity is preserved without a replacement attempt',
    () async {
      final TokenCreateFixture fixture = TokenCreateFixture();
      addTearDown(fixture.dispose);
      await fixture.preflight.refresh();
      final TokenCreateTransport transport = TokenCreateTransport();
      final TokenCreatePublisher publisher = TokenCreatePublisher(
        publisher: transport,
        preflight: fixture.preflight,
      );
      final Future<AccountBlockTemplate> original = publisher
          .createAccountBlock(block(), 'Fixture');
      final StateError error = StateError('Original fixture failure');
      final Future<void> expectation = expectLater(
        original,
        throwsA(same(error)),
      );
      fixture.revoke();
      transport.response.completeError(error);
      await expectation;
      expect(transport.calls, hasLength(1));
    },
  );
}
