import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'harness.dart' as cli;
import 'readonly_inspection_session.dart';

/// Source-defined steps disclose no command arguments or error text.
enum ReadonlyViewportStep {
  admission,
  destination,
  initialHome,
  railState,
  themeState,
  windowState,
  prepareRail,
  minimumHome,
  minimumResize,
  minimumTheme,
  minimumReady,
  minimumCapture,
  minimumPixels,
  minimumWrite,
  arabicPage,
  arabicDisplay,
  arabicMenu,
  arabicOpen,
  arabicOptionReady,
  arabicChoice,
  arabicLocale,
  arabicHome,
  arabicLayout,
  arabicResize,
  arabicTheme,
  arabicReady,
  arabicCapture,
  arabicPixels,
  arabicWrite,
  englishPage,
  englishDisplay,
  englishMenu,
  englishOpen,
  englishOptionReady,
  englishChoice,
  englishLocale,
  englishHome,
  restoreTheme,
  restoreWindow,
  restoreRail,
  finalHome,
  complete,
}

const String _output = '.harness/ci-viewport-observations';
const int _pixelCap = 4 * 1024 * 1024;

class _ViewportInstance extends cli.Instance {
  _ViewportInstance(this._session) : super('readonly-viewport-probe');

  final ReadonlyInspectionSession _session;

  @override
  Map<String, dynamic> read() =>
      throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.process);

  @override
  Future<Map<String, dynamic>> send(
    Map<String, Object?> command, {
    Duration timeout = const Duration(seconds: 30),
  }) => _session.send(command, timeout > const Duration(seconds: 30)
      ? const Duration(seconds: 30) : timeout);
}

/// Observes two layouts through real UI input on one original bound session.
/// These files are V04 observations and are never 94-screen catalog aliases.
Future<Map<String, Object>> captureReadonlyViewportProbe({
  required Directory repository,
  required ReadonlyInspectionSession session,
  void Function(ReadonlyViewportStep step)? onStep,
}) async {
  void enter(ReadonlyViewportStep step) => onStep?.call(step);
  enter(ReadonlyViewportStep.admission);
  Never refuse() => throw const ReadonlyInspectionRefused(
    ReadonlyInspectionReason.reply,
  );
  if (!session.walletBound) {
    throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.binding);
  }
  enter(ReadonlyViewportStep.destination);
  final Directory output = Directory('${repository.path}/$_output');
  void parents() {
    if (FileSystemEntity.typeSync(repository.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      refuse();
    }
    for (final String path in <String>[
      '${repository.path}/.harness', output.path,
    ]) {
      final FileSystemEntityType type = FileSystemEntity.typeSync(
        path, followLinks: false,
      );
      if (type != FileSystemEntityType.directory &&
          type != FileSystemEntityType.notFound) {
        refuse();
      }
    }
  }
  parents();
  if (FileSystemEntity.typeSync(output.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    refuse();
  }

  final _ViewportInstance instance = _ViewportInstance(session);
  Future<Map<String, dynamic>> call(Map<String, Object?> value) =>
      cli.call(instance, value);
  Future<void> home(String locale, String direction) async {
    final Map<String, dynamic> state = await cli.stateOf(instance);
    if (state['walletUnlocked'] != true ||
        state['walletInitCompleted'] != true ||
        state['tab'] != 'dashboard' || state['locale'] != locale ||
        state['direction'] != direction) {
      refuse();
    }
  }
  enter(ReadonlyViewportStep.initialHome);
  await home('en', 'ltr');
  enter(ReadonlyViewportStep.railState);
  final bool originalRail = await session.railExpanded();
  enter(ReadonlyViewportStep.themeState);
  final Map<String, dynamic> originalTheme = await call(
    <String, Object?>{'cmd': 'theme'},
  );
  enter(ReadonlyViewportStep.windowState);
  final Map<String, dynamic> originalWindow = await call(
    <String, Object?>{'cmd': 'window'},
  );
  enter(ReadonlyViewportStep.prepareRail);
  await session.prepareScreenHome();

  Future<void> language(String name, String locale, String direction) async {
    final bool arabic = locale == 'ar';
    enter(arabic ? ReadonlyViewportStep.arabicPage
        : ReadonlyViewportStep.englishPage);
    await cli.goto(instance, 'settings');
    enter(arabic ? ReadonlyViewportStep.arabicDisplay
        : ReadonlyViewportStep.englishDisplay);
    await call(<String, Object?>{'cmd': 'tap', 'key': 'settings_display'});
    enter(arabic ? ReadonlyViewportStep.arabicMenu
        : ReadonlyViewportStep.englishMenu);
    await call(<String, Object?>{
      'cmd': 'wait', 'key': 'display_language_menu', 'timeoutMs': 5000,
    });
    enter(arabic ? ReadonlyViewportStep.arabicOpen
        : ReadonlyViewportStep.englishOpen);
    await call(<String, Object?>{
      'cmd': 'tap', 'key': 'display_language_menu',
    });
    enter(arabic ? ReadonlyViewportStep.arabicOptionReady
        : ReadonlyViewportStep.englishOptionReady);
    await call(<String, Object?>{
      'cmd': 'wait', 'text': name, 'exact': true, 'timeoutMs': 5000,
    });
    enter(arabic ? ReadonlyViewportStep.arabicChoice
        : ReadonlyViewportStep.englishChoice);
    await call(<String, Object?>{
      'cmd': 'tap', 'text': name, 'exact': true,
    });
    enter(arabic ? ReadonlyViewportStep.arabicLocale
        : ReadonlyViewportStep.englishLocale);
    await cli.until(instance, (Map<String, dynamic> state) =>
        state['locale'] == locale && state['direction'] == direction,
        'viewport locale', seconds: 5);
    enter(arabic ? ReadonlyViewportStep.arabicHome
        : ReadonlyViewportStep.englishHome);
    await cli.goto(instance, 'dashboard');
    await home(locale, direction);
  }

  int bytes = 0;
  final List<Map<String, Object>> captures = <Map<String, Object>>[];
  Future<void> shot({
    required String name,
    required String theme,
    required int width,
    required int height,
    required String locale,
    required String direction,
  }) async {
    final bool minimum = width == 1200;
    void point(ReadonlyViewportStep small, ReadonlyViewportStep arabic) =>
        enter(minimum ? small : arabic);
    point(ReadonlyViewportStep.minimumHome, ReadonlyViewportStep.arabicLayout);
    await home(locale, direction);
    point(ReadonlyViewportStep.minimumResize,
        ReadonlyViewportStep.arabicResize);
    final Map<String, dynamic> window = await call(<String, Object?>{
      'cmd': 'window', 'do': 'show', 'width': width, 'height': height,
    });
    if (window['clientMatched'] != true) refuse();
    point(ReadonlyViewportStep.minimumTheme,
        ReadonlyViewportStep.arabicTheme);
    final Map<String, dynamic> themed = await call(<String, Object?>{
      'cmd': 'theme', 'mode': theme,
    });
    if (themed['mode'] != theme || themed['brightness'] != theme) refuse();
    point(ReadonlyViewportStep.minimumReady,
        ReadonlyViewportStep.arabicReady);
    await call(<String, Object?>{
      'cmd': 'wait', 'key': 'home_hero', 'timeoutMs': 5000,
    });
    point(ReadonlyViewportStep.minimumCapture,
        ReadonlyViewportStep.arabicCapture);
    final Map<String, dynamic> result = await call(<String, Object?>{
      'cmd': 'shot', 'width': width, 'height': height, 'theme': theme,
      'expect': <String, Object>{'key': 'home_hero', 'exact': true},
    });
    point(ReadonlyViewportStep.minimumPixels,
        ReadonlyViewportStep.arabicPixels);
    final Object? client = result['client'];
    final Object? encoded = result['png'];
    if (result['asserted'] != true || result['scale'] != 1 ||
        result['width'] != width || result['height'] != height ||
        result['theme'] != theme || client is! List || client.length != 2 ||
        client[0] != width || client[1] != height ||
        encoded is! String || encoded.length > 6 * 1024 * 1024) {
      refuse();
    }
    final Uint8List pixels = base64Decode(encoded);
    const List<int> signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    if (pixels.length < 33 || pixels.length > _pixelCap ||
        !signature.asMap().entries.every((MapEntry<int, int> value) =>
            pixels[value.key] == value.value) ||
        ByteData.sublistView(pixels).getUint32(8) != 13 ||
        ascii.decode(pixels.sublist(12, 16), allowInvalid: true) != 'IHDR' ||
        ByteData.sublistView(pixels).getUint32(16) != width ||
        ByteData.sublistView(pixels).getUint32(20) != height) {
      refuse();
    }
    bytes += pixels.length;
    if (bytes > _pixelCap) refuse();
    await home(locale, direction);
    point(ReadonlyViewportStep.minimumWrite,
        ReadonlyViewportStep.arabicWrite);
    parents();
    output.createSync(recursive: true);
    final File image = File('${output.path}/$name');
    if (FileSystemEntity.typeSync(image.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      refuse();
    }
    // A fresh cooperative directory is owned by this probe only.
    image..createSync(exclusive: true)
        ..writeAsBytesSync(pixels, flush: true);
    captures.add(<String, Object>{
      'file': name, 'theme': theme, 'width': width, 'height': height,
      'locale': locale, 'direction': direction, 'scale': 1,
      'bytes': pixels.length,
    });
  }

  for (final String theme in <String>['dark', 'light']) {
    await shot(name: 'v04-home-minimum-$theme.png', theme: theme,
        width: 1200, height: 600, locale: 'en', direction: 'ltr');
  }
  // The existing language menu's native label, represented in ASCII source.
  await language('\u0627\u0644\u0639\u0631\u0628\u064a\u0629',
      'ar', 'rtl');
  for (final String theme in <String>['dark', 'light']) {
    await shot(name: 'v04-home-arabic-$theme.png', theme: theme,
        width: 1280, height: 780, locale: 'ar', direction: 'rtl');
  }
  // A failure propagates before further UI input; no capture is replayed.
  await language('English', 'en', 'ltr');
  enter(ReadonlyViewportStep.restoreTheme);
  final Map<String, dynamic> themed = await call(<String, Object?>{
    'cmd': 'theme', 'restore': originalTheme,
  });
  for (final String key in <String>['mode', 'brightness', 'savedMode']) {
    if (themed[key] != originalTheme[key]) refuse();
  }
  enter(ReadonlyViewportStep.restoreWindow);
  final Map<String, dynamic> restored = await call(<String, Object?>{
    'cmd': 'window', 'restoreState': originalWindow,
  });
  if (restored['restored'] != true) refuse();
  enter(ReadonlyViewportStep.restoreRail);
  await session.restoreScreenRail(expanded: originalRail);
  enter(ReadonlyViewportStep.finalHome);
  await home('en', 'ltr');
  enter(ReadonlyViewportStep.complete);
  return <String, Object>{
    'schema': 1, 'scope': 'readonly_native_viewport_observation',
    'captures': captures, 'rendered_locale_restored': true,
    'theme_window_and_rail_restored': true,
    'locale_preference_restoration_qualified': false,
    'atomic_frame_qualified': false, 'visual_matches': 0,
  };
}
