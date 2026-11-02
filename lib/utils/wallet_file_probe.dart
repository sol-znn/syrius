import 'dart:convert';
import 'dart:io';

import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The maximum encrypted envelope inspected by the import presentation.
const int maxWalletFileProbeBytes = 1024 * 1024;

/// Recognises an encrypted key store envelope without authenticating its data.
/// A positive result never decrypts, derives a key or verifies a password.
bool isKeyStoreWalletBytes(List<int> bytes) {
  if (bytes.isEmpty || bytes.length > maxWalletFileProbeBytes) {
    return false;
  }
  try {
    final Object? decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      return false;
    }
    final EncryptedFile envelope = EncryptedFile.fromJson(decoded);
    final Object? type = envelope.metadata?[walletTypeKey];
    if (type != null && type != keyStoreWalletType) {
      return false;
    }
    return (envelope.crypto?.argon2Params?.salt?.isNotEmpty ?? false) &&
        (envelope.crypto?.nonce?.isNotEmpty ?? false) &&
        (envelope.crypto?.cipherData?.isNotEmpty ?? false);
  } on Object {
    return false;
  }
}

/// Accepts any filename while reading at most the limit plus one sentinel byte.
/// The same open handle is checked and read, including if its file grows.
bool isKeyStoreWalletFile(String filePath) {
  RandomAccessFile? opened;
  bool recognised = false;
  try {
    opened = File(filePath).openSync();
    if (opened.lengthSync() <= maxWalletFileProbeBytes) {
      recognised = isKeyStoreWalletBytes(
        opened.readSync(maxWalletFileProbeBytes + 1),
      );
    }
  } on Object {
    recognised = false;
  } finally {
    try {
      opened?.closeSync();
    } on Object {
      recognised = false;
    }
  }
  return recognised;
}
