import '../app/fixtures/seed_policy.dart';
import '../bin/screen_capture.dart' show scriptWords;

/// These are UI scripts, not shell scripts. There is no shell expansion.
final class SeedRecipe {
  SeedRecipe._(this.id, this.lines);
  factory SeedRecipe.parse(String id, String text) {
    if (!seedRecipeIds.contains(id) ||
        text.length > 8192 ||
        text.split('\n').length > 96 ||
        !text
            .split('\n')
            .map((String line) => line.trim())
            .contains('# seed: $id') ||
        !text
            .split('\n')
            .map((String line) => line.trim())
            .contains('# prerequisite: isolated-chain-321-checkpoint')) {
      throw const SeedRefused('seed-script-prerequisite-missing');
    }
    final List<List<String>> lines = <List<String>>[];
    int publications = 0;
    for (final String raw in text.split('\n')) {
      final String line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final List<String> words = scriptWords(line);
      if (words.isEmpty ||
          !<String>{
            'goto',
            'tap',
            'type',
            'key',
            'wait',
            'assert',
            'publish',
          }.contains(words.first) ||
          words.any(
            (String word) =>
                word.startsWith('@') ||
                RegExp(r'^#?\d+$').hasMatch(word) && words.indexOf(word) == 1,
          ) ||
          words.any(
            (String word) => <String>{
              '--force',
              '--submit',
              '--append',
              '--instance',
              '--double',
              '--long',
              '--right',
              '--gone',
            }.contains(word),
          ) ||
          words.any(
            (String word) =>
                word.startsWith('--') &&
                !<String>{
                  '--key',
                  '--type',
                  '--kind',
                  '--nth',
                  '--exact',
                  '--timeout',
                }.contains(word),
          )) {
        throw const SeedRefused('seed-script-command-refused');
      }
      if (words.first == 'goto' &&
          (words.length != 2 ||
              !<String>{
                'staking',
                'plasma',
                'tokens',
                'p2pSwap',
                'accelerator',
                'transfer',
              }.contains(words[1]))) {
        throw const SeedRefused('seed-script-route-refused');
      }
      if (words.first == 'key' && (words.length != 2 || words[1] != 'escape')) {
        throw const SeedRefused('seed-script-key-refused');
      }
      if (words.first == 'tap') {
        seedPreparationTarget(id, words.sublist(1));
      }
      if (words.contains('--timeout')) {
        final int at = words.indexOf('--timeout');
        final int? seconds = at + 1 < words.length
            ? int.tryParse(words[at + 1])
            : null;
        if (seconds == null || seconds < 1 || seconds > 30) {
          throw const SeedRefused('bounded-seed-wait-required');
        }
      }
      for (final String word in words) {
        if (word.contains(r'$') &&
            !<String>{
              r'${secondaryAddress}',
              r'${counterparty}',
            }.contains(word)) {
          throw const SeedRefused('seed-script-substitution-refused');
        }
      }
      if (words.first == 'publish') {
        publications++;
        if (words.skip(1).join(' ') != seedPublishSelector(id).join(' ')) {
          throw const SeedRefused('seed-publication-selector-refused');
        }
      }
      if (publications > 0 &&
          !<String>{'publish', 'wait', 'assert'}.contains(words.first)) {
        throw const SeedRefused('seed-script-after-publication-refused');
      }
      lines.add(List<String>.unmodifiable(words));
    }
    if (publications != 1 || lines.isEmpty || lines.last.first != 'assert') {
      throw const SeedRefused('one-seed-publication-required');
    }
    return SeedRecipe._(id, List<List<String>>.unmodifiable(lines));
  }
  final String id;
  final List<List<String>> lines;

  List<String> resolve(List<String> words, Map<String, String> values) =>
      List<String>.unmodifiable(
        words.map((String word) {
          if (!word.contains(r'$')) return word;
          final String? value = values[word];
          if (value == null || value.isEmpty) {
            throw const SeedRefused('seed-recipe-prerequisite-missing');
          }
          return value;
        }),
      );
}

List<String> seedPublishSelector(String recipe) => switch (recipe) {
  'stake' => <String>['--key', 'create_stake_submit_button'],
  'fuse' => <String>['--key', 'fuse_plasma_submit_button'],
  'token' => <String>['--key', 'token_create_continue'],
  'deposit' => <String>['--key', 'swap_create_deposit'],
  'project' => <String>['Submit', '--kind', 'button', '--exact'],
  'fund-address' => <String>['--key', 'send_confirmation_accept'],
  _ => throw const SeedRefused('unknown-recipe'),
};

/// Fixed preparation controls have no publication callback. Token Continue
/// additionally requires its actual original preparation frame at pointer time.
Map<String, Object> seedPreparationTarget(String recipe, List<String> words) {
  final Set<String> allowed = switch (recipe) {
    'stake' => const <String>{
      '--key staking_stake_button',
      '--key create_stake_months_6',
    },
    'fuse' => const <String>{'--key plasma_open_fuse'},
    'token' => const <String>{
      '--key tokens_create',
      '--key token_create_continue',
    },
    'deposit' => const <String>{
      '--key p2p_start_swap',
      '--key p2p_warning_continue',
      '--key swap_action_details_toggle',
    },
    'project' => const <String>{
      '--key acc_create_project',
      'Continue --kind button --exact',
    },
    'fund-address' => const <String>{
      '--key transfer_mode_send',
      '--key send_token_field',
      'ZNN --kind button --exact',
      '--key send_submit_button',
    },
    _ => throw const SeedRefused('unknown-recipe'),
  };
  if (!allowed.contains(words.join(' '))) {
    throw const SeedRefused('seed-preparation-selector-refused');
  }
  return words.first == '--key'
      ? <String, Object>{'key': words[1], 'exact': true}
      : <String, Object>{'text': words.first, 'kind': 'button', 'exact': true};
}

void requireSeedTokenPreparation({
  required String? frameKey,
  required bool active,
  required bool busy,
}) {
  const Set<String> frames = <String>{
    'token_create_details',
    'token_create_supply',
    'token_create_options',
  };
  if (!active || busy || !frames.contains(frameKey)) {
    throw const SeedRefused('token-publication-requires-guarded-publish');
  }
}
