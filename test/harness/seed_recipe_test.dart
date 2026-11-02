import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../harness/app/fixtures/seed_policy.dart';
import '../../harness/seed/seed_recipe.dart';

String _script(String body, {String id = 'stake'}) =>
    '# seed: $id\n'
    '# prerequisite: isolated-chain-321-checkpoint\n$body\n';
String get _valid => _script(
  'goto staking\nassert --key create_stake_submit_button\n'
  'publish --key create_stake_submit_button\nassert --key staking_stakes_count',
);

void main() {
  test(
    'all six small authored source recipes contain one exact publication '
    'and a final assertion',
    () {
      for (final String id in seedRecipeIds) {
        final SeedRecipe plan = SeedRecipe.parse(
          id,
          File('harness/seed/$id.txt').readAsStringSync(),
        );
        expect(
          plan.lines.where((List<String> words) => words.first == 'publish'),
          hasLength(1),
        );
        expect(plan.lines.last.first, 'assert');
      }
    },
  );
  test('a complete recipe is validated before any UI command is admitted', () {
    expect(SeedRecipe.parse('stake', _valid).lines, hasLength(4));
    expect(
      () => SeedRecipe.parse('stake', '$_valid\nstart --fresh'),
      throwsA(isA<SeedRefused>()),
    );
  });
  test('CRLF source retains the same explicit prerequisite', () {
    expect(
      SeedRecipe.parse('stake', _valid.replaceAll('\n', '\r\n')).lines,
      hasLength(4),
    );
  });
  test(
    'credentials, lifecycle, nested scripts and arbitrary routes are refused',
    () {
      for (final String command in <String>[
        'unlock synthetic',
        'import --mnemonic synthetic',
        'run nested.txt',
        'node ws://example.test',
        'chain 1',
        'goto settings',
        'key enter',
      ]) {
        expect(
          () => SeedRecipe.parse(
            'stake',
            _valid.replaceFirst('goto staking', command),
          ),
          throwsA(isA<SeedRefused>()),
        );
      }
    },
  );
  test(
    'force, raw coordinates, stale refs and instance overrides cannot publish',
    () {
      for (final String command in <String>[
        'tap @1,2',
        'tap 12',
        'tap --key button --force',
        'tap --key button --instance other',
        'type --key field 1 --submit',
      ]) {
        expect(
          () => SeedRecipe.parse(
            'stake',
            _valid.replaceFirst('goto staking', command),
          ),
          throwsA(isA<SeedRefused>()),
        );
      }
    },
  );
  test('wait limits are positive and capped at thirty seconds', () {
    for (final String timeout in <String>['0', '-1', '31', 'many']) {
      expect(
        () => SeedRecipe.parse(
          'stake',
          _valid.replaceFirst(
            'goto staking',
            'wait --key ready --timeout $timeout',
          ),
        ),
        throwsA(isA<SeedRefused>()),
      );
    }
  });
  test(
    'publication selector, count and commands after publication are fixed',
    () {
      expect(
        () => SeedRecipe.parse(
          'stake',
          _valid.replaceFirst(
            'publish --key create_stake_submit_button',
            'publish --key send_confirmation_accept',
          ),
        ),
        throwsA(isA<SeedRefused>()),
      );
      expect(
        () => SeedRecipe.parse(
          'stake',
          _valid.replaceFirst(
            'assert --key staking_stakes_count',
            'publish --key create_stake_submit_button\nassert --key ready',
          ),
        ),
        throwsA(isA<SeedRefused>()),
      );
      expect(
        () => SeedRecipe.parse(
          'stake',
          _valid.replaceFirst(
            'assert --key staking_stakes_count',
            'type --key field 1\nassert --key ready',
          ),
        ),
        throwsA(isA<SeedRefused>()),
      );
    },
  );
  test('ordinary preparation taps cannot target a publication or an alias', () {
    for (final (String, String) sample in <(String, String)>[
      ('stake', 'tap --key create_stake_submit_button'),
      ('fuse', 'tap --key fuse_plasma_submit_button'),
      ('deposit', 'tap --key swap_create_deposit'),
      ('project', 'tap Submit --kind button --exact'),
      ('fund-address', 'tap --key send_confirmation_accept'),
      ('stake', 'tap --type PrimaryPill'),
      ('stake', 'tap Submit'),
      ('stake', 'tap --key token_create_continue'),
    ]) {
      final String publication = seedPublishSelector(sample.$1).join(' ');
      expect(
        () => SeedRecipe.parse(
          sample.$1,
          _script(
            '${sample.$2}\npublish $publication\nassert --key ready',
            id: sample.$1,
          ),
        ),
        throwsA(
          isA<SeedRefused>().having(
            (SeedRefused error) => error.code,
            'code',
            'seed-preparation-selector-refused',
          ),
        ),
      );
    }
  });
  test(
    'the reused token control can only prepare an active original '
    'nonissue frame',
    () {
      expect(
        seedPreparationTarget('token', <String>[
          '--key',
          'token_create_continue',
        ]),
        <String, Object>{'key': 'token_create_continue', 'exact': true},
      );
      for (final String key in <String>[
        'token_create_details',
        'token_create_supply',
        'token_create_options',
      ]) {
        expect(
          () => requireSeedTokenPreparation(
            frameKey: key,
            active: true,
            busy: false,
          ),
          returnsNormally,
        );
      }
      for (final (String?, bool, bool) frame in <(String?, bool, bool)>[
        ('token_create_issue', true, false),
        (null, true, false),
        ('token_create_details', false, false),
        ('token_create_supply', true, true),
      ]) {
        expect(
          () => requireSeedTokenPreparation(
            frameKey: frame.$1,
            active: frame.$2,
            busy: frame.$3,
          ),
          throwsA(
            isA<SeedRefused>().having(
              (SeedRefused error) => error.code,
              'code',
              'token-publication-requires-guarded-publish',
            ),
          ),
        );
      }
    },
  );
  test('substitution only supplies an exact captured address value', () {
    final SeedRecipe plan = SeedRecipe.parse('stake', _valid);
    expect(
      plan.resolve(
        <String>['type', r'${secondaryAddress}'],
        <String, String>{r'${secondaryAddress}': 'captured-recipient'},
      ),
      <String>['type', 'captured-recipient'],
    );
    expect(
      () => plan.resolve(<String>[
        'type',
        r'${counterparty}',
      ], <String, String>{}),
      throwsA(isA<SeedRefused>()),
    );
    expect(
      () => SeedRecipe.parse(
        'stake',
        _valid.replaceFirst('goto staking', r'type --key field ${unknown}'),
      ),
      throwsA(isA<SeedRefused>()),
    );
  });
  test(
    'missing checkpoint declaration and oversized scripts refuse '
    'before execution',
    () {
      expect(
        () => SeedRecipe.parse(
          'stake',
          _valid.replaceFirst('isolated-chain-321-checkpoint', 'ready'),
        ),
        throwsA(isA<SeedRefused>()),
      );
      expect(
        () => SeedRecipe.parse('stake', List<String>.filled(8193, 'x').join()),
        throwsA(isA<SeedRefused>()),
      );
    },
  );
}
