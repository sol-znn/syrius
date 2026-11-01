// Manual hosted inspection only. The job owner gates all private input.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../wallet_recipe_failure.dart' show walletRecipePublicDiagnostic;
import 'harness.dart' as cli;
import 'readonly_inspection_session.dart';
import 'readonly_settings_catalog.dart';
import 'readonly_viewport_probe.dart';
import 'screen_capture.dart';
import 'wallet_recipe.dart';

class _InspectionInstance extends cli.Instance {
  _InspectionInstance(super.name, this._receipt) {
    _session = ReadonlyInspectionSession(
      processId: _receipt['pid'] as int,
      original: (Map<String, Object?> command, Duration timeout) =>
          super.send(command, timeout: timeout),
    );
  }

  final Map<String, dynamic> _receipt;
  late final ReadonlyInspectionSession _session;

  // Keep the exact original endpoint/token instead of adopting another file.
  @override
  Map<String, dynamic> read() => _receipt;

  @override
  Future<Map<String, dynamic>> send(
    Map<String, Object?> command, {
    Duration timeout = const Duration(seconds: 120),
  }) => _session.send(command, timeout);

  int get processId => _session.processId;

  Future<Map<String, dynamic>> bindWallet() => _session.bindWallet();

  Future<Map<String, Object>> captureSettingsDefaults({
    void Function(ScreenCaptureObservation step)? onStep,
  }) =>
      captureReadonlySettingsDefaults(
    repository: Directory(cli.repo), session: _session, onStep: onStep,
  );

  Future<Map<String, Object>> captureViewport({
    void Function(ReadonlyViewportStep step)? onStep,
  }) => captureReadonlyViewportProbe(
    repository: Directory(cli.repo), session: _session, onStep: onStep,
  );
}

_InspectionInstance _capture(cli.Instance original) {
  if (FileSystemEntity.typeSync(original.file.path, followLinks: false) !=
          FileSystemEntityType.file || original.file.lengthSync() > 4096) {
    throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.process);
  }
  final Map<String, dynamic>? value = original.read();
  if (value == null || value['pid'] is! int || (value['pid'] as int) <= 0 ||
      value['port'] is! int || (value['port'] as int) < 1024 ||
      (value['port'] as int) > 65535 || value['token'] is! String ||
      !RegExp(r'^[a-f0-9]{32}$').hasMatch(value['token'] as String) ||
      value['mode'] != 'release' ||
      value['harnessMode'] != 'readonly-native' ||
      value['presentationScreen'] != null) {
    throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.process);
  }
  return _InspectionInstance(
    original.name, Map<String, dynamic>.unmodifiable(value),
  );
}

Future<void> main() async {
  final StreamIterator<String> input = StreamIterator<String>(
    stdin.transform(utf8.decoder).transform(const LineSplitter()),
  );
  String stage = 'admission';
  ReadonlyViewportStep? lastViewportStep;
  ScreenCaptureObservation? lastSettingsStep;
  try {
    final Map<String, String> environment = Platform.environment;
    final String name = environment['SYRIUS_CI_INSPECTION_INSTANCE'] ?? '';
    if (!Platform.isWindows || environment['GITHUB_ACTIONS'] != 'true' ||
        environment['SYRIUS_CI_WALLET_INSPECTION'] != 'true' ||
        environment['SYRIUS_CI_WALLET_TOUR'] != null ||
        !RegExp(r'^ci-inspect-[a-f0-9]{24}$').hasMatch(name) ||
        !await input.moveNext() || input.current != 'START') {
      throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.process);
    }
    Future<void> marker(String value) async {
      stdout.writeln(value);
      await stdout.flush();
    }
    await marker('CI_INSPECT_STAGE:gate');
    final String? check = environment['SYRIUS_CI_INSPECTION_CHECK'];
    if (check == 'gate') {
      await marker('CI_INSPECT_GATE_PASSED');
      return;
    }
    if (check != null) {
      throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.command);
    }
    final cli.Instance launched = cli.Instance(name);
    stage = 'unused_destinations';
    if (FileSystemEntity.typeSync(launched.home, followLinks: false) !=
            FileSystemEntityType.notFound ||
        FileSystemEntity.typeSync('${cli.stateRoot}/app', followLinks: false) !=
            FileSystemEntityType.notFound) {
      throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.process);
    }
    stage = 'build';
    await marker('CI_INSPECT_STAGE:build');
    await cli.build(cli.Args(<String>[
      '--mode', 'release', '--no-pub', '--metadata',
      '${cli.repo}/.dart_tool/git_metadata.json',
    ]), isolatedInput: true);
    stage = 'start';
    await marker('CI_INSPECT_STAGE:start');
    await cli.start(launched, cli.Args(<String>['--mode', 'release']),
        readonlyNative: true);
    final _InspectionInstance instance = _capture(launched);
    await cli.call(instance, <String, Object?>{'cmd': 'ping'});
    await marker('CI_INSPECT_READY:${jsonEncode(<String, Object>{
      'schema': 1, 'scope': 'readonly_native_inspection_ready',
      'pid': instance.processId, 'port': instance.read()['port'] as int,
    })}');

    // The parent binds actual app/job handles and revalidates all five nodes.
    stage = 'input';
    if (!await input.moveNext() || input.current.length > 4096) {
      throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.process);
    }
    final Object? decoded = jsonDecode(input.current);
    if (decoded is! Map<String, dynamic> || decoded.length != 4 ||
        decoded['chain'] != '321' ||
        decoded['node'] != 'ws://127.0.0.1:45998' ||
        decoded['mnemonic'] is! String || decoded['password'] is! String) {
      throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.command);
    }
    stage = 'window';
    await cli.call(instance, <String, Object?>{
      'cmd': 'window', 'do': 'show', 'width': 1280, 'height': 780,
    });
    final WalletRecipe recipe = WalletRecipe.inspection(
      expectedPid: instance.processId,
      send: (Map<String, Object?> command, Duration timeout) =>
          instance.send(command, timeout: timeout),
    );
    stage = 'onboarding';
    await recipe.importWallet(
      chain: decoded['chain'] as String,
      node: decoded['node'] as String,
      mnemonic: decoded['mnemonic'] as String,
      password: decoded['password'] as String,
    );
    stage = 'signing_policy';
    final Map<String, dynamic> state = await cli.stateOf(instance);
    if (state['node'] != 'ws://127.0.0.1:45998' || state['chainId'] != 321 ||
        state['signingChainId'] != 321 || state['savedSigningChainId'] != 321 ||
        state['walletUnlocked'] != true ||
        state['walletInitCompleted'] != true ||
        state['embeddedNode'] != false ||
        state['locale'] != 'en' || state['direction'] != 'ltr') {
      throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.reply);
    }
    stage = 'onboarding_logs';
    final Map<String, dynamic> logs = await cli.call(instance,
      <String, Object?>{
        'cmd': 'logs', 'since': 0, 'limit': 500,
        'levels': <String>['SEVERE', 'SHOUT', 'FLUTTER'],
      },
    );
    if (logs['logs'] is! List ||
        (logs['logs'] as List<dynamic>).isNotEmpty) {
      throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.reply);
    }
    stage = 'address_selection';
    final Map<String, Object> selection = await recipe.selectLabAddress();
    await marker('SYRIUS_INSPECTION_ADDRESS:${jsonEncode(selection)}');
    stage = 'wallet_binding';
    final Map<String, dynamic> bound = await instance.bindWallet();
    await marker('SYRIUS_INSPECTION_WALLET:${jsonEncode(
      bound['readonlyWallet'],
    )}');
    for (final String theme in <String>['dark', 'light']) {
      stage = 'tour_$theme';
      final Map<String, dynamic> before = await cli.stateOf(instance);
      if (before['locale'] != 'en' || before['direction'] != 'ltr') {
        throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.reply);
      }
      await cli.call(instance,
        <String, Object?>{'cmd': 'theme', 'mode': theme},
      );
      await cli.call(instance,
        <String, Object?>{'cmd': 'stalls', 'reset': true},
      );
      await cli.tour(instance, cli.Args(<String>[
        '--dir', '${cli.stateRoot}/ci-wallet-inspection/captures/$theme',
      ]), readonlyNativePid: instance.processId,
        publish: (Map<String, Object?> report) {
          stdout.writeln('SYRIUS_INSPECTION_TOUR:${jsonEncode(
            <String, Object?>{'theme': theme, 'tour': report},
          )}');
        },
      );
      final Map<String, dynamic> after = await cli.stateOf(instance);
      if (after['locale'] != 'en' || after['direction'] != 'ltr') {
        throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.reply);
      }
      await marker('SYRIUS_INSPECTION_LOCALE:${jsonEncode(<String, Object>{
        'schema': 1, 'scope': 'readonly_native_locale_observation',
        'theme': theme, 'language': after['locale'] as String,
        'direction': after['direction'] as String,
        'stable': before['locale'] == after['locale'] &&
            before['direction'] == after['direction'],
      })}');
      final Map<String, dynamic> timings = await cli.call(instance,
        <String, Object?>{'cmd': 'stalls'},
      );
      if (timings['stalls'] is! List || timings['longestMs'] is! int) {
        throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.reply);
      }
      await marker('SYRIUS_INSPECTION_STALLS:${jsonEncode(<String, Object>{
        'schema': 1, 'scope': 'readonly_native_stalls_observation',
        'theme': theme, 'events': (timings['stalls'] as List<dynamic>).length,
        'longest_ms': timings['longestMs'] as int,
      })}');
    }
    stage = 'settings_catalog';
    final Map<String, Object> catalog =
        await instance.captureSettingsDefaults(
      onStep: (ScreenCaptureObservation value) => lastSettingsStep = value,
    );
    await marker('SYRIUS_INSPECTION_CATALOG:${jsonEncode(catalog)}');
    stage = 'viewport';
    final Map<String, Object> viewport = await instance.captureViewport(
      onStep: (ReadonlyViewportStep value) => lastViewportStep = value,
    );
    await marker('SYRIUS_INSPECTION_VIEWPORT:${jsonEncode(viewport)}');
    await marker('CI_INSPECT_DONE');
    stage = 'finish';
    if (!await input.moveNext() || input.current != 'FINISH') {
      throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.process);
    }
  } on Object catch (error) {
    if (stage == 'admission') {
      stdout.writeln('CI_INSPECT_ERROR');
    } else {
      final String? code = error is ReadonlyInspectionRefused
          ? 'inspection-${error.reason.name}'
          : error is WalletRecipeRefused &&
              RegExp(r'^wallet-recipe-[a-z-]{1,80}$').hasMatch(error.code)
          ? error.code : null;
      Map<String, Object>? diagnostic = error is WalletRecipeRefused
          ? walletRecipePublicDiagnostic(error.diagnostic)
          : error is cli.WalletTourFailure ? error.diagnostic : null;
      if (stage == 'settings_catalog') {
        diagnostic = readonlySettingsFailureDiagnostic(lastSettingsStep);
      }
      final ReadonlyViewportStep? observed = lastViewportStep;
      if (stage == 'viewport' && observed != null) {
        diagnostic = <String, Object>{
          'schema': 1, 'kind': 'readonly_viewport_failure',
          'last_entered_step': observed.name,
        };
      }
      stdout.writeln('CI_INSPECT_ERROR:${jsonEncode(<String, Object?>{
        'stage': stage, 'code': code, 'diagnostic': ?diagnostic,
      })}');
    }
    exitCode = 1;
  } finally {
    await input.cancel();
  }
}
