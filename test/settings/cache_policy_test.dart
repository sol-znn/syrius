import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/services/contacts_store.dart';
import 'package:zenon_syrius_wallet_flutter/utils/cache_policy.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';

void main() {
  test('ordinary maintenance preserves irreplaceable user state', () {
    for (final String retained in <String>[
      kAddressesBox,
      kAddressLabelsBox,
      kFavoriteTokensBox,
      kContactsBox,
      kSharedPrefsBox,
      kNodesBox,
      kNotificationsBox,
      kRecipientAddressBox,
      kHtlcSwapsBox,
      kKeyStoreBox,
    ]) {
      expect(kOrdinaryCacheBoxesToBeDeleted, isNot(contains(retained)));
    }
  });

  test('the existing explicit reset policy remains separate', () {
    expect(
      kCacheBoxesToBeDeleted,
      containsAll(<String>[
        kAddressLabelsBox,
        kFavoriteTokensBox,
        kSharedPrefsBox,
        kNodesBox,
      ]),
    );
    expect(kCacheBoxesToBeDeleted, isNot(contains(kContactsBox)));
    expect(kCacheBoxesToBeDeleted, isNot(contains(kHtlcSwapsBox)));
  });
}
