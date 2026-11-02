import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/model/send_intent.dart';
import 'package:zenon_syrius_wallet_flutter/utils/extensions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

void main() {
  Token token() => Token.fromJson(kZnnCoin.toJson());
  SendIntent intent(Token asset) => SendIntent.capture(
    fromAddress: emptyAddress.toString(),
    recipient: emptyAddress.toString(),
    amount: '90071992.54740993',
    token: asset,
  );

  test('a mutable SDK token cannot change the confirmed transfer', () {
    final Token asset = token();
    final SendIntent original = intent(asset);
    asset
      ..symbol = 'CHANGED'
      ..decimals = 0
      ..tokenStandard = kQsrCoin.tokenStandard;
    final SendTransactionInitiate event = original.toEvent();
    expect(event.amount, BigInt.parse('9007199254740993'));
    expect(event.token.symbol, 'ZNN');
    expect(event.token.decimals, 8);
    expect(event.token.tokenStandard, kZnnCoin.tokenStandard);
    expect(original.displayAmount, '90071992.54740993');
    expect(event.requestId, same(original.requestId));
    event.token.decimals = 3;
    expect(original.toEvent().token.decimals, 8);
    expect(original.decimals, 8);
  });

  test('changes to any confirmed draft value revoke its match', () {
    final Token asset = token();
    final SendIntent original = intent(asset);
    bool matches({String? sender, String? recipient, String? amount}) =>
        original.matches(
          fromAddress: sender ?? original.fromAddress,
          recipient: recipient ?? original.recipientInput,
          amount: amount ?? original.amountInput,
          token: asset,
        );
    expect(matches(), isTrue);
    expect(matches(sender: 'changed'), isFalse);
    expect(matches(recipient: '${original.recipientInput} '), isFalse);
    expect(matches(amount: '90071992.547409930'), isFalse);
    asset.symbol = 'OTHER';
    expect(matches(), isFalse);
  });

  test('invalid addresses and lossy amounts have no confirmation intent', () {
    expect(
      () => SendIntent.capture(
        fromAddress: emptyAddress.toString(),
        recipient: 'invalid',
        amount: '1',
        token: token(),
      ),
      throwsFormatException,
    );
    expect(
      () => SendIntent.capture(
        fromAddress: emptyAddress.toString(),
        recipient: emptyAddress.toString(),
        amount: '1.000000001',
        token: token(),
      ),
      throwsFormatException,
    );
  });

  test('exact range endpoints and high precision remain representable', () {
    expect(parseSendAmount(kBigP255m1.addDecimals(8), 8), kBigP255m1);
    expect(
      parseSendAmount((kBigP255m1 + BigInt.one).addDecimals(8), 8),
      isNull,
    );
    expect(parseSendAmount('0.${'0' * 254}1', 255), BigInt.one);
    expect(parseSendAmount('1', 255), isNull);
    expect(parseSendAmount('9' * 10000, 8), isNull);
  });

  test('plain positive decimal syntax refuses coercion and truncation', () {
    for (final String text in <String>[
      '',
      '0',
      '-1',
      '+1',
      '1e2',
      'NaN',
      '1,2',
      ' 1',
      '1 ',
      '1\n',
      '.',
      '0.000000001',
      '1.000000001',
    ]) {
      expect(parseSendAmount(text, 8), isNull, reason: text);
    }
    expect(parseSendAmount('.1', 8), BigInt.from(10000000));
    expect(parseSendAmount('001.50', 8), BigInt.from(150000000));
    expect(parseSendAmount('1.', 0), BigInt.one);
    expect(parseSendAmount('1', -1), isNull);
    expect(parseSendAmount('1', 256), isNull);
  });
}
