import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _registered = false;

/// Registers the authentic bundled font texts once, before About is opened.
void registerBundledFontLicences() {
  if (_registered) return;
  _registered = true;
  final AssetBundle bundle = rootBundle;
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const <String>['Space Grotesk'],
      await bundle.loadString('assets/fonts/OFL-SpaceGrotesk.txt'),
    );
    yield LicenseEntryWithLineBreaks(
      const <String>['JetBrains Mono'],
      await bundle.loadString('assets/fonts/OFL-JetBrainsMono.txt'),
    );
    yield LicenseEntryWithLineBreaks(
      const <String>['Noto Sans Arabic', 'Noto Sans Devanagari'],
      await bundle.loadString('assets/fonts/OFL-NotoSans.txt'),
    );
  });
}
