import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/receive/receive_request.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

void main() {
  test('keeps every unit beyond floating point precision', () {
    expect(
      parseReceiveRequestAmount('9007199254740993.00000001', 8),
      BigInt.parse('900719925474099300000001'),
    );
    expect(parseReceiveRequestAmount('.00000001', 8), BigInt.one);
    expect(parseReceiveRequestAmount('1.', 8), BigInt.from(100000000));
    expect(parseReceiveRequestAmount('1', 0), BigInt.one);
    expect(
      parseReceiveRequestAmount('0.${''.padRight(254, '0')}1', 255),
      BigInt.one,
    );
  });

  test('enforces the exact positive request range', () {
    expect(parseReceiveRequestAmount(kBigP255m1.toString(), 0), kBigP255m1);
    expect(
      parseReceiveRequestAmount((kBigP255m1 + BigInt.one).toString(), 0),
      isNull,
    );
    expect(parseReceiveRequestAmount('1', -1), isNull);
    expect(parseReceiveRequestAmount('1', 256), isNull);
    expect(parseReceiveRequestAmount('1', 255), isNull);
    expect(parseReceiveRequestAmount('0.1', 255), isNull);
    expect(parseReceiveRequestAmount(''.padRight(100000, '9'), 8), isNull);
  });

  test('rejects invalid spelling and precision without changing a value', () {
    for (final String value in <String>[
      '',
      '0',
      '0.0',
      '-1',
      '+1',
      '01',
      '00.1',
      '1,5',
      '1e3',
      'NaN',
      'Infinity',
      '.',
      '1.2.3',
      ' 1',
      '1 ',
      '1\n',
      '1\t',
      '1.000000000',
      '0.000000001',
    ]) {
      expect(parseReceiveRequestAmount(value, 8), isNull, reason: value);
    }
    expect(parseReceiveRequestAmount('1.1', 0), isNull);
  });

  test('preserves the legacy scheme, token and base-unit payload', () {
    final String address = emptyAddress.toString();
    expect(
      receiveRequestData(address: address, token: kQsrCoin, amount: '100.5'),
      'qsr:$address?zts=${kQsrCoin.tokenStandard}&amount=10050000000',
    );
    expect(
      receiveRequestData(address: address, token: kZnnCoin, amount: ''),
      'znn:$address?zts=${kZnnCoin.tokenStandard}&amount=0',
    );
    expect(
      receiveRequestData(address: address, token: kZnnCoin, amount: '0'),
      isNull,
    );
    expect(
      receiveRequestData(
        address: address,
        token: kZnnCoin,
        amount: '1.234567891',
      ),
      isNull,
    );
    expect(
      receiveRequestData(address: '', token: kZnnCoin, amount: ''),
      isNull,
    );
  });
}
