import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/import_wallet/import_draft.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_file_probe.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart'
    show keyStoreWalletType, walletTypeKey;

// These synthetic labels are not a usable mnemonic or wallet credential.
List<String> _words(int count) =>
    List<String>.generate(count, (int index) => 'fixture-$index');

void main() {
  for (final int count in <int>[12, 24]) {
    test(
      '$count words require membership and the checksum of the same snapshot',
      () {
        final List<String> words = _words(count);
        List<String>? checked;
        final ImportSeedDraft draft = ImportSeedDraft(
          words.join(' '),
          expectedWords: count,
          isValidWord: words.contains,
          validateMnemonic: (List<String> value) {
            checked = value;
            return true;
          },
        );
        expect(draft.valid, isTrue);
        expect(identical(checked, draft.words), isTrue);
        expect(draft.seed, words.join(' '));
        expect(() => draft.words[0] = 'replacement', throwsUnsupportedError);
      },
    );
  }

  test(
    'whitespace and case normalize before membership and checksum checks',
    () {
      final List<String> words = _words(12);
      final ImportSeedDraft draft = ImportSeedDraft(
        '  ${words.join('  \n').toUpperCase()}  ',
        expectedWords: 12,
        isValidWord: words.contains,
        validateMnemonic: (List<String> value) =>
            value.join(' ') == words.join(' '),
      );
      expect(draft.valid, isTrue);
      expect(draft.words, words);
    },
  );

  test(
    'short, long and unsupported seed counts cannot reach checksum admission',
    () {
      for (final int count in <int>[0, 11, 13, 23, 25]) {
        int checksums = 0;
        final ImportSeedDraft draft = ImportSeedDraft(
          _words(count).join(' '),
          expectedWords: 12,
          isValidWord: (_) => true,
          validateMnemonic: (_) {
            checksums++;
            return true;
          },
        );
        expect(draft.valid, isFalse);
        expect(checksums, 0);
      }
      expect(
        ImportSeedDraft(
          _words(13).join(' '),
          expectedWords: 13,
          isValidWord: (_) => true,
          validateMnemonic: (_) => true,
        ).valid,
        isFalse,
      );
    },
  );

  test(
    'a nonmember and a failed checksum each refuse an exact-length seed',
    () {
      final String text = _words(12).join(' ');
      expect(
        ImportSeedDraft(
          text,
          expectedWords: 12,
          isValidWord: (_) => false,
          validateMnemonic: (_) => true,
        ).valid,
        isFalse,
      );
      expect(
        ImportSeedDraft(
          text,
          expectedWords: 12,
          isValidWord: (_) => true,
          validateMnemonic: (_) => false,
        ).valid,
        isFalse,
      );
    },
  );

  test(
    'the content probe accepts only structural envelopes within its byte cap',
    () {
      // Inert one-byte fields identify shape and cannot authenticate a wallet.
      final Map<String, Object> envelope = <String, Object>{
        walletTypeKey: keyStoreWalletType,
        'version': 1,
        'crypto': <String, Object>{
          'argon2Params': <String, String>{'salt': '0x01'},
          'cipherData': '0x02',
          'nonce': '0x03',
          'cipherName': 'aes-256-gcm',
          'kdf': 'argon2.IDKey',
        },
      };
      final List<int> encoded = utf8.encode(jsonEncode(envelope));
      expect(isKeyStoreWalletBytes(encoded), isTrue);
      final List<int> atLimit = <int>[
        ...encoded,
        ...List<int>.filled(maxWalletFileProbeBytes - encoded.length, 0x20),
      ];
      expect(isKeyStoreWalletBytes(atLimit), isTrue);
      expect(isKeyStoreWalletBytes(<int>[...atLimit, 0x20]), isFalse);
      expect(isKeyStoreWalletBytes(utf8.encode('{}')), isFalse);
      expect(isKeyStoreWalletBytes(<int>[0xff]), isFalse);
    },
  );
}
