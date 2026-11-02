import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';

/// Links supported by the bundled explorer. Other chains have no explorer
/// configured, so their identifiers must never open a mainnet result.
abstract final class ExplorerLinks {
  /// The provider already used by the wallet.
  static String get providerHost => Uri.parse(kExplorer).host;

  /// Whether the connected chain has a configured provider.
  static bool available(int? chainId) => chainId == 1;

  static final RegExp _hash = RegExp(r'^[a-f0-9]{64}$', caseSensitive: false);

  static Uri? _link(String kind, String hash, int? chainId) =>
      available(chainId) && _hash.hasMatch(hash)
      ? Uri.parse('$kExplorer/$kind/$hash')
      : null;

  /// An account block on a supported chain, with its exact hash.
  static Uri? transaction(String hash, {required int? chainId}) =>
      _link('transaction', hash, chainId);

  /// A momentum on a supported chain, with its exact hash.
  static Uri? momentum(String hash, {required int? chainId}) =>
      _link('momentum', hash, chainId);
}
