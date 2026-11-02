import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Refuses RPC metadata that cannot safely describe an ABI uint256 token.
void requireValidTokenMetadata(Token token) {
  if (token.decimals < 0 ||
      token.decimals > 255 ||
      token.totalSupply.isNegative ||
      token.maxSupply.isNegative ||
      token.totalSupply.bitLength > 256 ||
      token.maxSupply.bitLength > 256 ||
      (token.isMintable && token.maxSupply == BigInt.zero) ||
      (token.maxSupply > BigInt.zero && token.totalSupply > token.maxSupply)) {
    throw const FormatException('Token numeric metadata unavailable');
  }
}
