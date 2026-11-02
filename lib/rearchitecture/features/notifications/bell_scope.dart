/// The derivation-order anchor keeps an address switch in the same wallet.
/// A caller with no anchor keeps the bell private instead of sharing a key.
String? bellScopeForWallet(int chainId, Iterable<String> addresses) {
  if (addresses.isEmpty || addresses.first.isEmpty) return null;
  return '$chainId:${addresses.first}';
}
