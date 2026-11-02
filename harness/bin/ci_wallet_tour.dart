// Manual hosted regression only. Private input travels over the gated stdin.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../lab_send_failure.dart';
import '../wallet_recipe_failure.dart' show walletRecipePublicDiagnostic;
import 'build_output.dart';
import 'harness.dart' as cli;
import 'wallet_recipe.dart' show WalletRecipeRefused;

Future<void> main() async {
  final StreamIterator<String> input = StreamIterator<String>(
    stdin.transform(utf8.decoder).transform(const LineSplitter()),
  );
  String stage = 'admission';
  try {
    final Map<String, String> env = Platform.environment;
    final String name = env['SYRIUS_CI_WALLET_INSTANCE'] ?? '';
    if (!Platform.isWindows || env['GITHUB_ACTIONS'] != 'true' ||
        env['SYRIUS_CI_WALLET_TOUR'] != 'true' ||
        !RegExp(r'^ci-wallet-[a-f0-9]{24}$').hasMatch(name) ||
        !await input.moveNext() || input.current != 'START') {
      throw StateError('admission');
    }
    Future<void> marker(String text) async {
      stdout.writeln(text);
      await stdout.flush();
    }
    await marker('CI_WALLET_STAGE:gate');
    final String? check = env['SYRIUS_CI_WALLET_CHECK'];
    if (check == 'gate') {
      await marker('CI_WALLET_GATE_PASSED');
      return;
    }
    if (check == 'sdk') {
      final Process sdk = await Process.start(
        'flutter', <String>['--version', '--machine'], runInShell: true,
      );
      if (await finishIsolatedBuild(sdk) != 0) {
        throw StateError('SDK check');
      }
      stdout.writeln();
      await marker('CI_WALLET_SDK_PASSED');
      return;
    }
    if (check != null) throw StateError('unsupported check');
    final cli.Instance instance = cli.Instance(name);
    stage = 'unused_destinations';
    if (FileSystemEntity.typeSync(instance.home, followLinks: false) !=
            FileSystemEntityType.notFound ||
        FileSystemEntity.typeSync('${cli.stateRoot}/app', followLinks: false) !=
            FileSystemEntityType.notFound) {
      throw StateError('unused destinations required');
    }
    stage = 'build';
    await marker('CI_WALLET_STAGE:build');
    await cli.build(cli.Args(<String>[
      '--mode', 'release', '--no-pub', '--metadata',
      '${cli.repo}/.dart_tool/git_metadata.json',
    ]), isolatedInput: true);
    stage = 'start';
    await marker('CI_WALLET_STAGE:start');
    await cli.start(
      instance, cli.Args(<String>['--fresh', '--mode', 'release']),
    );
    stdout.writeln('CI_WALLET_READY');
    await stdout.flush();
    // The parent binds the original native handle and the owned lab first.
    stage = 'input';
    if (!await input.moveNext() || input.current.length > 4096) {
      throw StateError('private input unavailable');
    }
    final Object? decoded = jsonDecode(input.current);
    if (decoded is! Map<String, dynamic> || decoded.length != 4 ||
        decoded['chain'] != '321' ||
        decoded['node'] != 'ws://127.0.0.1:45998' ||
        decoded['mnemonic'] is! String || decoded['password'] is! String) {
      throw StateError('private input refused');
    }
    // Keyed onboarding needs the same client area as the later screen tour.
    stage = 'window';
    await cli.run(instance, 'window', cli.Args(<String>[
      'show', '--width', '1280', '--height', '780',
    ]));
    stage = 'onboarding';
    await cli.importWallet(instance, cli.Args(<String>[
      '--chain', decoded['chain'] as String,
      '--node', decoded['node'] as String,
      '--mnemonic', decoded['mnemonic'] as String,
      '--password', decoded['password'] as String,
    ]));
    stage = 'signing_policy';
    final Map<String, dynamic> state = await cli.stateOf(instance);
    if (state['node'] != 'ws://127.0.0.1:45998' || state['chainId'] != 321 ||
        state['signingChainId'] != 321 || state['savedSigningChainId'] != 321 ||
        state['walletUnlocked'] != true ||
        state['walletInitCompleted'] != true ||
        state['embeddedNode'] != false) {
      throw StateError('wallet policy unconfirmed');
    }
    stage = 'onboarding_logs';
    final Map<String, dynamic> logs = await cli.call(
      instance,
      <String, Object?>{
        'cmd': 'logs', 'since': 0, 'limit': 500,
        'levels': <String>['SEVERE', 'SHOUT', 'FLUTTER'],
      },
    );
    if (logs['logs'] is! List || (logs['logs'] as List<dynamic>).isNotEmpty) {
      throw StateError('onboarding errors');
    }
    stage = 'address_selection';
    final Map<String, Object> selection = await cli.walletRecipe(instance)
        .selectLabAddress();
    await marker('SYRIUS_LAB_ADDRESS:${jsonEncode(selection)}');
    stage = 'lab_send';
    final Map<String, dynamic> sent = await instance.send(<String, Object>{
      'cmd': 'lab-send', 'profile': name,
      'ws': 'ws://127.0.0.1:45998', 'http': 'http://127.0.0.1:45997',
    });
    if (sent['ok'] != true) {
      final Object? detail = sent['detail'];
      throw LabSendDiagnosticFailure(detail is Map ? detail['labSend'] : null);
    }
    const Map<String, Object> expectedSend = <String, Object>{
      'schema': 1, 'scope': 'original_lab_ui_send', 'chain': 321,
      'from_index': 1, 'to_index': 0, 'amount': '100000000', 'token': 'ZNN',
      'original_request': true, 'confirmed': true,
    };
    final Object? receipt = sent['receipt'];
    if (receipt is! Map<String, dynamic> ||
        receipt.length != expectedSend.length ||
        !expectedSend.entries.every((MapEntry<String, Object> entry) =>
            receipt[entry.key] == entry.value &&
            receipt[entry.key].runtimeType == entry.value.runtimeType)) {
      throw LabSendDiagnosticFailure(<String, String>{
        'phase': 'receipt', 'reason': 'receipt-shape-refused',
      });
    }
    await marker('SYRIUS_LAB_SEND:${jsonEncode(expectedSend)}');
    stage = 'tour';
    await cli.tour(instance, cli.Args(<String>[]));
    stdout.writeln('CI_WALLET_DONE');
    await stdout.flush();
    stage = 'finish';
    if (!await input.moveNext() || input.current != 'FINISH') {
      throw StateError('closure unconfirmed');
    }
  } on Object catch (error) {
    // The parent retains the actual exit and complete bounded output.
    // Neither exception text nor private UI replies are printed.
    if (stage == 'admission') {
      stdout.writeln('CI_WALLET_ERROR');
    } else {
      final String? code = error is WalletRecipeRefused &&
              RegExp(r'^wallet-recipe-[a-z-]{1,80}$').hasMatch(error.code)
          ? error.code
          : null;
      final Map<String, Object>? diagnostic = error is LabSendDiagnosticFailure
          ? error.diagnostic
          : error is WalletRecipeRefused
          ? walletRecipePublicDiagnostic(error.diagnostic)
          : error is cli.WalletTourFailure
          ? error.diagnostic
          : null;
      stdout.writeln('CI_WALLET_ERROR:${jsonEncode(<String, Object?>{
        'stage': stage, 'code': code, 'diagnostic': ?diagnostic,
      })}');
    }
    exitCode = 1;
  } finally {
    await input.cancel();
  }
}
