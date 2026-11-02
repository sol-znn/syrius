import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/zap/zap.dart';
import 'package:zenon_syrius_wallet_flutter/seams/missing_services.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';

const String _defaultMessage = 'You got zapped. Have a great day, alien.';
const String _maximumAmount =
    '578960446186580977117854925043439539266349923328202820197287920039565'
    '.64819967';
const String _aboveMaximumAmount =
    '578960446186580977117854925043439539266349923328202820197287920039565'
    '.64819968';

void main() {
  test(
    'defaults are a composition, with no discovered recipient or sent block',
    () {
      const ZapDraft draft = ZapDraft();
      expect(draft.znnBaseUnits, BigInt.from(100000000));
      expect(draft.qsrBaseUnits, BigInt.from(1000000000));
      expect(draft.message, isNull);
      expect(draft.messageBytes(_defaultMessage), 40);
      expect(draft.blockCount, 2);
      expect(draft.isValid(_defaultMessage), isTrue);
    },
  );

  test('native base units stay exact above the double integer boundary', () {
    const ZapDraft draft = ZapDraft(
      znn: '9007199254740993.00000001',
      qsr: '0.00000001',
    );
    expect(draft.znnBaseUnits, BigInt.parse('900719925474099300000001'));
    expect(draft.qsrBaseUnits, BigInt.one);
    expect(draft.znnIssue, isNull);
    expect(draft.qsrIssue, isNull);
    expect(draft.isValid(_defaultMessage), isTrue);
  });

  test('decimal editing forms do not change the amount they mean', () {
    expect(
      const ZapDraft(znn: '.00000001').znnBaseUnits,
      BigInt.one,
    );
    expect(
      const ZapDraft(znn: '000001.23000000').znnBaseUnits,
      BigInt.from(123000000),
    );
    expect(
      const ZapDraft(znn: '1.').znnBaseUnits,
      BigInt.from(100000000),
    );
  });

  test('zero omits one coin and both zero amounts cannot form a Zap', () {
    const ZapDraft znnOnly = ZapDraft(qsr: '0');
    const ZapDraft qsrOnly = ZapDraft(znn: '0');
    const ZapDraft neither = ZapDraft(znn: '0.00000000', qsr: '0');
    expect(znnOnly.blockCount, 1);
    expect(qsrOnly.blockCount, 1);
    expect(znnOnly.isValid(_defaultMessage), isTrue);
    expect(qsrOnly.isValid(_defaultMessage), isTrue);
    expect(neither.blockCount, 0);
    expect(neither.isValid(_defaultMessage), isFalse);
  });

  test(
    'missing and malformed amount text never becomes zero or another value',
    () {
      for (final String amount in <String>[
        '',
        ' 1',
        '1 ',
        '1\n',
        '1\r\n',
        '1\t',
        '+1',
        '-1',
        '1e2',
        '1,5',
        'NaN',
        'Infinity',
        '٠١',
        '0x10',
        '1.2.3',
        '\u200b1',
        '.',
      ]) {
        final ZapDraft draft = ZapDraft(znn: amount);
        expect(draft.znn, amount);
        expect(draft.znnBaseUnits, isNull, reason: amount);
        expect(draft.blockCount, isNull, reason: amount);
        expect(draft.isValid(_defaultMessage), isFalse, reason: amount);
        expect(
          draft.znnIssue,
          amount.isEmpty ? ZapAmountIssue.empty : ZapAmountIssue.invalid,
          reason: amount,
        );
      }
    },
  );

  test('excess decimals are refused even when the excess digits are zero', () {
    for (final String amount in <String>[
      '1.000000001',
      '1.000000000',
      '0.000000000',
    ]) {
      final ZapDraft draft = ZapDraft(qsr: amount);
      expect(draft.qsr, amount);
      expect(draft.qsrIssue, ZapAmountIssue.precision);
      expect(draft.qsrBaseUnits, isNull);
      expect(draft.blockCount, isNull);
    }
  });

  test('SDK supply bound is exact and the next base unit is refused', () {
    const ZapDraft maximum = ZapDraft(znn: _maximumAmount, qsr: '0');
    const ZapDraft above = ZapDraft(znn: _aboveMaximumAmount, qsr: '0');
    expect(
      maximum.znnBaseUnits,
      BigInt.parse(
        '5789604461865809771178549250434395392663499233282028201972879200395'
        '6564819967',
      ),
    );
    expect(maximum.znnBaseUnits, ZapDraft.maximumBaseUnits);
    expect(maximum.isValid(_defaultMessage), isTrue);
    expect(above.znnIssue, ZapAmountIssue.range);
    expect(above.znnBaseUnits, isNull);
    expect(above.isValid(_defaultMessage), isFalse);
  });

  test(
    'obviously oversized whole digits are refused before integer parsing',
    () {
      final String huge = List<String>.filled(10000, '9').join();
      final String zeros = List<String>.filled(10000, '0').join();
      final ZapDraft overflow = ZapDraft(znn: huge);
      final ZapDraft leadingZeros = ZapDraft(znn: '${zeros}1.00000001');
      expect(overflow.znnIssue, ZapAmountIssue.range);
      expect(overflow.znnBaseUnits, isNull);
      expect(leadingZeros.znnIssue, isNull);
      expect(leadingZeros.znnBaseUnits, BigInt.from(100000001));
    },
  );

  test('the message limit counts UTF-8 bytes without truncating the text', () {
    final String ascii140 = List<String>.filled(140, 'x').join();
    final String euro46 = List<String>.filled(46, '€').join();
    final String euro47 = List<String>.filled(47, '€').join();
    final String emoji35 = List<String>.filled(35, '😀').join();
    final String emoji36 = List<String>.filled(36, '😀').join();
    expect(ZapDraft(message: ascii140).messageBytes(_defaultMessage), 140);
    expect(ZapDraft(message: '$ascii140!').isValid(_defaultMessage), isFalse);
    expect(ZapDraft(message: euro46).messageBytes(_defaultMessage), 138);
    expect(ZapDraft(message: '${euro46}ab').isValid(_defaultMessage), isTrue);
    expect(ZapDraft(message: euro47).messageBytes(_defaultMessage), 141);
    expect(ZapDraft(message: euro47).isValid(_defaultMessage), isFalse);
    expect(ZapDraft(message: euro47).message, euro47);
    expect(ZapDraft(message: emoji35).messageBytes(_defaultMessage), 140);
    expect(ZapDraft(message: emoji36).messageBytes(_defaultMessage), 144);
  });

  test('an empty custom message is distinct from the localized default', () {
    expect(const ZapDraft().messageBytes('€'), 3);
    expect(const ZapDraft(message: '').messageBytes('€'), 0);
  });

  test(
    'save retains exact text and clear restores the localized-default state',
    () async {
      final ZapDraftCubit cubit = ZapDraftCubit();
      addTearDown(cubit.close);
      const ZapDraft edited = ZapDraft(
        znn: '0001.23000000',
        qsr: '0',
        message: 'A custom message',
      );
      final Future<void> observed = expectLater(
        cubit.stream,
        emitsInOrder(<ZapDraft>[edited, const ZapDraft()]),
      );
      cubit.save(
        znn: edited.znn,
        qsr: edited.qsr,
        message: edited.message!,
      );
      expect(cubit.state, edited);
      cubit.clear();
      expect(cubit.state, const ZapDraft());
      expect(cubit.state.message, isNull);
      await observed;
    },
  );

  test(
    'a direct missing-service caller still gets an explicit refusal',
    () async {
      await expectLater(
        const UnbuiltZapService().send(),
        throwsA(
          isA<SeamNotBuilt>().having(
            (SeamNotBuilt error) => error.seam,
            'seam',
            Seam.zapSend,
          ),
        ),
      );
    },
  );
}
