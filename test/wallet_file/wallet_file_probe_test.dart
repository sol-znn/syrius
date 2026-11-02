import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_file.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_file_probe.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

Map<String, dynamic> _envelope() => <String, dynamic>{
  walletTypeKey: keyStoreWalletType,
  'version': 1,
  'crypto': <String, dynamic>{
    'argon2Params': <String, dynamic>{'salt': '0x01'},
    'cipherData': '0x02',
    'cipherName': 'aes-256-gcm',
    'kdf': 'argon2.IDKey',
    'nonce': '0x03',
  },
};

List<int> _bytes(Map<String, dynamic> value) => utf8.encode(jsonEncode(value));

void main() {
  test('a structural envelope does not imply successful authentication', () {
    // These one-byte placeholders cannot authenticate a real encrypted seed.
    expect(isKeyStoreWalletBytes(_bytes(_envelope())), isTrue);
    expect(
      isKeyStoreWalletBytes(_bytes(_envelope()..remove(walletTypeKey))),
      isTrue,
    );
  });

  for (final String type in <String>['ledger', 'unsupported']) {
    test('another wallet type is refused: $type', () {
      expect(
        isKeyStoreWalletBytes(_bytes(_envelope()..[walletTypeKey] = type)),
        isFalse,
      );
    });
  }

  for (final String absent in <String>['salt', 'nonce', 'cipherData']) {
    test('empty or absent $absent cannot identify an encrypted envelope', () {
      for (final bool empty in <bool>[false, true]) {
        final Map<String, dynamic> envelope = _envelope();
        final Map<String, dynamic> crypto =
            envelope['crypto'] as Map<String, dynamic>;
        final Map<String, dynamic> target = absent == 'salt'
            ? crypto['argon2Params'] as Map<String, dynamic>
            : crypto;
        if (empty) {
          target[absent] = '0x';
        } else {
          target.remove(absent);
        }
        expect(isKeyStoreWalletBytes(_bytes(envelope)), isFalse);
      }
    });
  }

  test('malformed encoding and non-envelopes are refused without throwing', () {
    for (final List<int> bytes in <List<int>>[
      <int>[],
      <int>[0xff, 0xfe],
      utf8.encode('not json'),
      utf8.encode('[]'),
      utf8.encode('null'),
      utf8.encode('{}'),
      _bytes(_envelope()..remove('crypto')),
      _bytes(_envelope()..['crypto'] = <dynamic>[]),
    ]) {
      expect(isKeyStoreWalletBytes(bytes), isFalse);
    }
  });

  test('the exact byte limit is accepted and one extra byte is refused', () {
    final List<int> content = _bytes(_envelope());
    final List<int> atLimit = <int>[
      ...content,
      ...List<int>.filled(maxWalletFileProbeBytes - content.length, 0x20),
    ];
    expect(isKeyStoreWalletBytes(atLimit), isTrue);
    expect(isKeyStoreWalletBytes(<int>[...atLimit, 0x20]), isFalse);
  });

  test('any name is valid and oversized or missing files are refused', () {
    final Directory scratch = Directory.systemTemp.createTempSync('probe-');
    try {
      final File input = File('${scratch.path}/renamed.backup')
        ..writeAsBytesSync(_bytes(_envelope()));
      expect(isKeyStoreWalletFile(input.path), isTrue);
      input.writeAsBytesSync(
        List<int>.filled(maxWalletFileProbeBytes + 1, 0x20),
      );
      expect(isKeyStoreWalletFile(input.path), isFalse);
      expect(isKeyStoreWalletFile('${scratch.path}/missing'), isFalse);
      expect(isKeyStoreWalletFile(scratch.path), isFalse);
    } finally {
      scratch.deleteSync(recursive: true);
    }
  });

  test('wallet save completes its owned write before success', () async {
    final Directory scratch = Directory.systemTemp.createTempSync('save-');
    try {
      final File target = File('${scratch.path}/envelope');
      const String password = 'synthetic fixture only';
      final List<int> data = <int>[4, 8, 15];
      await WalletFile.write(
        target.path,
        password,
        data,
        metadata: <String, dynamic>{walletTypeKey: keyStoreWalletType},
      );
      final EncryptedFile saved = EncryptedFile.fromJson(
        jsonDecode(target.readAsStringSync()) as Map<String, dynamic>,
      );
      expect(await saved.decrypt(password), data);
      expect(WalletFile.isKeyStoreFile(target.path), isTrue);
    } finally {
      scratch.deleteSync(recursive: true);
    }
  });

  test('wallet save reports its original file write failure', () async {
    final Directory scratch = Directory.systemTemp.createTempSync('save-');
    try {
      await expectLater(
        WalletFile.write(
          '${scratch.path}/absent/envelope',
          'synthetic fixture only',
          <int>[4, 8, 15],
        ),
        throwsA(isA<FileSystemException>()),
      );
    } finally {
      scratch.deleteSync(recursive: true);
    }
  });
}
