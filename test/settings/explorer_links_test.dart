import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/utils/explorer_links.dart';

void main() {
  final String hash = ''.padLeft(64, 'a');
  test('configured chain links preserve exact hashes', () {
    expect(
      ExplorerLinks.transaction(hash, chainId: 1)?.toString(),
      'https://explorer.zenon.network/transaction/$hash',
    );
    expect(
      ExplorerLinks.momentum(hash, chainId: 1)?.toString(),
      'https://explorer.zenon.network/momentum/$hash',
    );
  });
  test(
    'unknown chains and malformed identifiers do not open mainnet links',
    () {
      for (final int? chain in <int?>[null, 0, 2, 321]) {
        expect(ExplorerLinks.transaction(hash, chainId: chain), isNull);
        expect(ExplorerLinks.momentum(hash, chainId: chain), isNull);
      }
      for (final String invalid in <String>['', '../account', '$hash/other']) {
        expect(ExplorerLinks.transaction(invalid, chainId: 1), isNull);
      }
    },
  );
}
