import '../app/fixtures/seed_policy.dart';
import '../wallet_address_context.dart';

/// A single owned session; receipts observe originals and never admit a retry.
final class RestoredSeedWorkflow {
  RestoredSeedWorkflow({
    required this.original,
    required this.observe,
    required this.prepareAddress,
    required this.recipe,
    required this.parentAlive,
  });

  final WalletAddressContext original;
  final Future<WalletAddressContext> Function() observe;
  final Future<WalletAddressContext> Function(WalletAddressContext)
      prepareAddress;
  final Future<Map<String, dynamic>> Function(String, Future<void> Function())
      recipe;
  final bool Function() parentAlive;
  bool _attempted = false;

  Future<Map<String, Object>> run(String counterparty) async {
    if (_attempted) throw const SeedRefused('restored-seed-session-held');
    _attempted = true;
    void alive() {
      if (!parentAlive()) {
        throw const SeedRefused('restored-seed-parent-unavailable');
      }
    }
    alive();
    final WalletAddressContext before = await observe();
    alive();
    if (!before.same(original) || !before.consistent ||
        before.members.length != 2 ||
        before.selected != before.members[1] || counterparty.isEmpty ||
        counterparty.length > 128 || before.members.contains(counterparty)) {
      throw const SeedRefused('restored-seed-membership-required');
    }
    final WalletAddressContext prepared = await prepareAddress(before);
    alive();
    if (!prepared.derivedFrom(before) || prepared.members.length != 3 ||
        prepared.members.contains(counterparty)) {
      throw const SeedRefused('restored-seed-derivation-refused');
    }
    Future<void> current() async {
      alive();
      final WalletAddressContext now = await observe();
      alive();
      if (!now.same(prepared)) {
        throw const SeedRefused('restored-seed-owner-changed');
      }
    }
    final List<Map<String, String>> receipts = <Map<String, String>>[];
    final Set<String> hashes = <String>{};
    for (final String id in seedRecipeIds) {
      await current();
      final Map<String, dynamic> result = await recipe(id, current);
      await current();
      final Object? hash = result['hash'];
      if (result['ok'] != true || result['confirmed'] != true ||
          result['recipe'] != id || hash is! String || !seedHash(hash) ||
          !hashes.add(hash)) {
        throw const SeedRefused('restored-seed-exact-receipt-required');
      }
      receipts.add(<String, String>{'recipe': id, 'hash': hash});
    }
    await current();
    return <String, Object>{
      'schema': 1, 'scope': 'private_restored_seed_receipts', 'chain': 321,
      'members': 3, 'selected_index': 1, 'derived_once': true,
      'owner_stable': true, 'receipts': receipts,
    };
  }
}
