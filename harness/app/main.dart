// Default startup runs the real app beside the agent. An explicit presentation
// mode selects an independent read-only host before any wallet owner starts.
// Build it with `harness/h build`, never ship it.

import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;
import 'package:window_manager/window_manager.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/utils/motion_binding.dart';

import 'agent.dart';
import 'client_window.dart';
import 'native_window_owner.dart';
import 'presentation_host.dart';
import 'presentation_mode.dart';
import 'readonly_native_mode.dart';
import 'readonly_sdk_binding.dart';

const String _protocolKey = r'HKCU\Software\Classes\syrius';

int _debugLoopVisits = 0;

// The debug controller invokes only this marker. Its state distinguishes a
// reload from a restart without creating a wallet or changing application data.
@pragma('vm:entry-point')
int harnessDebugLoopMarker() {
  if (Platform.environment['SYRIUS_WINDOWS_DEBUG_PROFILE'] == null ||
      Platform.environment['GITHUB_ACTIONS'] != 'true') {
    throw StateError('debug marker requires the isolated CI profile');
  }
  return _debugLoopVisits += 1; // SYRIUS_DEBUG_BREAKPOINT
}

Future<void> main() async {
  final Map<String, String> env = Platform.environment;
  final String? home = env['SYRIUS_HARNESS_HOME'];
  final String? appData = env['AppData'];
  final int? port = int.tryParse(env['SYRIUS_HARNESS_PORT'] ?? '');
  final String? token = env['SYRIUS_HARNESS_TOKEN'];

  // The SDK keeps wallets under %AppData%\znn. Started by hand, this binary
  // would open the machine's real wallets with a remote control attached, so
  // it runs only when the launcher has pointed AppData into a harness home.
  if (home == null ||
      appData == null ||
      port == null ||
      token == null ||
      !path.isWithin(path.canonicalize(home), path.canonicalize(appData))) {
    stderr.writeln(
      'syrius harness: refusing to start outside a harness home. '
      'Use `harness/h start`.',
    );
    exit(64);
  }

  final String? presentation = env[harnessPresentationEnvironment];
  if (presentation != null &&
      !harnessPresentationSurfaces.contains(presentation)) {
    stderr.writeln('syrius harness: unsupported presentation surface');
    exit(64);
  }

  final bool readonlyNative;
  try {
    readonlyNative = harnessReadonlyNativeRequested(
      env,
      windows: Platform.isWindows,
      presentation: presentation,
    );
  } on ReadonlyNativeModeRefused {
    stderr.writeln('syrius harness: native inspection requires Windows CI');
    exit(64);
  }
  // The agent needs a binding before app.main() runs, and the first binding
  // created is the one the process keeps. A plain one here would switch the
  // app's own off, and the harness would then drive a wallet whose animations
  // shorten under reduced motion while the shipped one's do not.
  MotionBinding.ensureInitialized();
  if (readonlyNative) HarnessAgent.instance.reserveReadonlyNative();

  if (presentation != null) {
    final HarnessPresentationController controller =
        HarnessPresentationController(surface: presentation);
    final GlobalKey host = GlobalKey();
    HarnessAgent.instance.usePresentation(
      controller: controller,
      context: () => host.currentContext,
      isCurrent: () {
        final BuildContext? context = host.currentContext;
        return context != null &&
            context.mounted &&
            context.widget is HarnessPresentationHost &&
            identical(
              (context.widget as HarnessPresentationHost).controller,
              controller,
            );
      },
    );
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(false);
    await HarnessAgent.start(port: port, token: token);
    runApp(_PresentationRoot(controller: controller, host: host));
    await windowManager.waitUntilReadyToShow();
    await windowManager.setTitle('Syrius presentation fixture');
    await windowManager.setMinimumSize(const Size(1200, 600));
    await windowManager.setSize(const Size(1280, 780));
    await windowManager.show();
    await windowManager.focus();
    await WidgetsBinding.instance.endOfFrame;
    HarnessAgent.instance.booted = true;
    return;
  }
  if (Platform.isWindows) {
    HarnessAgent.instance.useNativeEntry(window: NativeWindowOwner.process());
    await configureHarnessWindowTracking();
  }
  await HarnessAgent.start(port: port, token: token);

  // app.main() registers this executable as the handler of syrius:// links.
  // Put back whatever was there, so the installed wallet keeps its links.
  final String? previous = _readProtocolCommand();
  try {
    await app.main();
  } finally {
    _restoreProtocolCommand(previous);
  }
  if (readonlyNative) {
    HarnessAgent.instance.attachReadonlyNative(await sealReadonlyNativeSdk());
  }
  HarnessAgent.instance.booted = true;
}

class _PresentationRoot extends StatefulWidget {
  const _PresentationRoot({required this.controller, required this.host});

  final HarnessPresentationController controller;
  final GlobalKey host;

  @override
  State<_PresentationRoot> createState() => _PresentationRootState();
}

class _PresentationRootState extends State<_PresentationRoot> {
  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HarnessPresentationHost(
    key: widget.host,
    controller: widget.controller,
  );
}

String? _readProtocolCommand() {
  if (!Platform.isWindows) return null;
  final ProcessResult r = Process.runSync('reg', <String>[
    'query',
    '$_protocolKey\\shell\\open\\command',
    '/ve',
  ]);
  if (r.exitCode != 0) return null;
  final RegExpMatch? m = RegExp(
    r'REG_SZ\s+(.*)$',
    multiLine: true,
  ).firstMatch(r.stdout as String);
  return m?.group(1)?.trim();
}

void _restoreProtocolCommand(String? previous) {
  if (!Platform.isWindows) return;
  if (previous == null) {
    Process.runSync('reg', <String>['delete', _protocolKey, '/f']);
  } else {
    Process.runSync('reg', <String>[
      'add',
      '$_protocolKey\\shell\\open\\command',
      '/ve',
      '/d',
      previous,
      '/f',
    ]);
  }
}
