import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_initialization.dart';

WalletInitializationTarget? _target(String? node, {bool creating = true}) =>
    WalletInitializationTarget.fromPreference(
      node: node,
      creating: creating,
      embeddedNode: 'Fixture embedded',
      embeddedUrl: 'ws://127.0.0.1:45998',
    );

void main() {
  test('first-profile creation admits absence without inventing a node', () {
    final WalletInitializationTarget? target = _target(null);
    expect(target, isNotNull);
    expect(target!.url, isNull);
    expect(_target(null, creating: false), isNull);
  });

  for (final String node in <String>[
    'ws://127.0.0.1:45998',
    'wss://node.example:35998',
    'Fixture embedded',
  ]) {
    test('selected target retains its existing connection route: $node', () {
      final WalletInitializationTarget? target = _target(node);
      expect(
        target!.url,
        node == 'Fixture embedded' ? 'ws://127.0.0.1:45998' : node,
      );
      expect(_target(node, creating: false)!.url, target.url);
    });
  }

  for (final String node in <String>[
    '',
    ' ',
    'https://node.example',
    'ws:',
    'node.example:35998',
  ]) {
    test('damaged saved target never becomes an offline default: $node', () {
      expect(_target(node), isNull);
      expect(_target(node, creating: false), isNull);
    });
  }
}
