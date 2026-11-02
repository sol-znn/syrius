import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/services/i_web3wallet_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/default_address_notifier.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';

import '../../harness/wallet_address_context.dart';
import '../settings_addresses_redesign/support.dart';

class _Web3 extends Mock implements IWeb3WalletService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String? originalSelection;
  late _Web3 web3;
  late SelectedAddressNotifier source;
  SelectedAddressContextListener? subscription;

  setUp(() {
    originalSelection = kSelectedAddress;
    kSelectedAddress = fixtureAddress(1);
    web3 = _Web3();
    when(() => web3.emitAddressChangeEvent(any())).thenAnswer((_) async {});
    app.sl.pushNewScope(scopeName: 'isolated-selection-revision');
    app.sl.registerSingleton<IWeb3WalletService>(web3);
    source = SelectedAddressNotifier();
  });

  tearDown(() async {
    subscription?.close();
    subscription = null;
    source.dispose();
    await Future<void>.delayed(Duration.zero);
    await app.sl.popScope();
    kSelectedAddress = originalSelection;
  });

  test('real selection keeps one original generation '
      'through shell invalidation',
      () {
    final int before = WalletContextRevision.value;
    final List<String> members = <String>[
      fixtureAddress(1), fixtureAddress(2),
    ];
    final WalletAddressContext original = WalletAddressContext.parse(
      <String, dynamic>{'members': members, 'selected': members[0],
        'saved': members[0], 'revision': before, 'owner': 1},
    );
    int invalidations = 0;
    subscription = SelectedAddressContextListener(source: source,
      onChanged: ({required bool contextAlreadyInvalidated}) {
        // The real shell performs this same optional context revocation
        // before invalidating its already owned collection controllers.
        if (!contextAlreadyInvalidated) WalletContextRevision.invalidate();
        invalidations++;
      },
    );
    source.changeSelectedAddress(members[1]);
    final WalletAddressContext selected = WalletAddressContext.parse(
      <String, dynamic>{'members': members, 'selected': kSelectedAddress,
        'saved': members[1], 'revision': WalletContextRevision.value,
        'owner': 1},
    );
    expect(kSelectedAddress, members[1]);
    expect(invalidations, 1);
    expect(WalletContextRevision.value, before + 1);
    expect(selected.selectedFrom(original, 1), isTrue);
  });

  test('shell sees prior revocation and detaches without owning the notifier',
      () {
    final int before = WalletContextRevision.value;
    final List<int> observed = <int>[];
    subscription = SelectedAddressContextListener(source: source,
      onChanged: ({required bool contextAlreadyInvalidated}) {
        observed.add(WalletContextRevision.value);
        if (!contextAlreadyInvalidated) WalletContextRevision.invalidate();
      },
    );
    source.changeSelectedAddress(kSelectedAddress);
    expect(observed, isEmpty);
    expect(WalletContextRevision.value, before);
    source.changeSelectedAddress(fixtureAddress(2));
    expect(observed, <int>[before + 1]);
    expect(WalletContextRevision.value, observed.single);
    subscription!
      ..close()
      ..close();
    source.changeSelectedAddress(fixtureAddress(1));
    expect(observed, hasLength(1));
    expect(WalletContextRevision.value, before + 2);
  });
}
