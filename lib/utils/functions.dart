import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_file.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// A signed message and the public key used for verification.
class Signature {
  /// Retains the existing hexadecimal signature and public key.
  Signature(this.signature, this.publicKey);

  /// The hexadecimal signature of the original message.
  String signature;

  /// The hexadecimal public key for verifying [signature].
  String publicKey;
}

/// The bytes a text message is signed as, and verified against: its UTF-8
/// encoding. One function, so the web channel, the Sign panel and the Verify
/// panel cannot disagree about what was signed.
///
/// Throws a [FormatException] for a message of exactly 32 bytes: that is the
/// size of an account block hash, and signing it would sign a transaction
/// under the name of a message.
List<int> messageBytesToSign(String message) {
  final List<int> bytes = utf8.encode(message);
  if (bytes.length == 32) {
    // Shown under the message field of the Sign and Verify panels. A web page
    // never gets this text: the dapp bridge refuses such a message itself, in
    // its own fixed words, before it asks for a signature.
    throw FormatException(currentL10n.signMessage32BytesError);
  }
  return bytes;
}

/// Signs [message] as text with the selected address. See
/// [messageBytesToSign].
Future<Signature> walletSignMessage(String message) =>
    walletSign(messageBytesToSign(message));

/// Keeps original failures in memory without exposing their private text.
class WalletSignFailure implements Exception {
  const WalletSignFailure._({
    required this.primaryError,
    required this.primaryStackTrace,
    this.closeError,
    this.closeStackTrace,
    this.settledResult,
  });

  /// The original operation error, or close error if the operation succeeded.
  final Object primaryError;

  /// The stack belonging to [primaryError].
  final StackTrace primaryStackTrace;

  /// The original release failure, including when another error came first.
  final Object? closeError;

  /// The stack belonging to [closeError].
  final StackTrace? closeStackTrace;

  /// The settled original result, retained only as private failure evidence.
  /// This grants no permission to deliver it or obtain another signature.
  final ({String publicKey, String signature})? settledResult;

  @override
  String toString() => 'Wallet signing failed.';
}

/// Signs one immutable message with the originally selected wallet account.
Future<Signature> walletSign(List<int> message) async {
  final WalletFile? originalFile = kWalletFile;
  final String? originalAddress = kSelectedAddress;
  final List<String?> originalAddresses = kDefaultAddressList;
  final int originalIndex = originalAddresses.indexOf(originalAddress);
  final WalletActionContext? context = originalAddress == null
      ? null
      : WalletActionContext.capture(originalAddress);
  Object? primaryError;
  StackTrace? primaryStack;
  Object? closeError;
  StackTrace? closeStack;
  ({String publicKey, String signature})? settledResult;
  bool acquired = false;

  void requireOriginal() {
    if (originalFile == null ||
        originalAddress == null ||
        originalIndex < 0 ||
        originalAddresses.lastIndexOf(originalAddress) != originalIndex ||
        !identical(originalFile, kWalletFile) ||
        !identical(originalAddresses, kDefaultAddressList) ||
        originalFile.walletPath != kWalletPath ||
        context == null ||
        !context.isCurrent) {
      throw StateError('Wallet signing context changed.');
    }
  }

  try {
    requireOriginal();
    final List<int> originalMessage = List<int>.unmodifiable(
      Uint8List.fromList(message),
    );
    final Wallet wallet = await originalFile!.open();
    acquired = true;
    requireOriginal();
    final WalletAccount account = await wallet.getAccount(originalIndex);
    requireOriginal();
    final List<int> observedPublicKey = await account.getPublicKey();
    requireOriginal();
    final List<int> publicKey = List<int>.unmodifiable(observedPublicKey);
    if (Address.fromPublicKey(publicKey).toString() != originalAddress) {
      throw StateError('Wallet signing account changed.');
    }
    final List<int> signature = await account.sign(originalMessage);
    settledResult = (
      publicKey: BytesUtils.bytesToHex(publicKey),
      signature: BytesUtils.bytesToHex(signature),
    );
    requireOriginal();
  } on Object catch (error, stackTrace) {
    primaryError = error;
    primaryStack = stackTrace;
  }

  // A failed open releases its own mutex and gives this call no acquisition.
  if (acquired) {
    try {
      await originalFile!.close();
    } on Object catch (error, stackTrace) {
      closeError = error;
      closeStack = stackTrace;
    }
  }

  if (primaryError == null && closeError == null) {
    try {
      requireOriginal();
    } on Object catch (error, stackTrace) {
      primaryError = error;
      primaryStack = stackTrace;
    }
  }
  if (primaryError != null || closeError != null) {
    final WalletSignFailure failure = WalletSignFailure._(
      primaryError: primaryError ?? closeError!,
      primaryStackTrace: primaryStack ?? closeStack!,
      closeError: closeError,
      closeStackTrace: closeStack,
      settledResult: settledResult,
    );
    Error.throwWithStackTrace(failure, failure.primaryStackTrace);
  }
  final ({String publicKey, String signature}) original = settledResult!;
  return Signature(original.signature, original.publicKey);
}

/// Decodes a bundled JSON asset from [filePath].
Future<dynamic> loadJsonFromAssets(String filePath) async {
  final String jsonString = await rootBundle.loadString(filePath);
  return jsonDecode(jsonString);
}
