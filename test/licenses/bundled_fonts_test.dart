import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/utils/font_licences.dart';

String _normalized(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled fonts register each authentic complete licence once', () async {
    LicenseRegistry.reset();
    registerBundledFontLicences();
    registerBundledFontLicences();
    final List<LicenseEntry> entries = await LicenseRegistry.licenses.toList();
    const List<(String, List<String>)> sources = <(String, List<String>)>[
      ('assets/fonts/OFL-SpaceGrotesk.txt', <String>['Space Grotesk']),
      ('assets/fonts/OFL-JetBrainsMono.txt', <String>['JetBrains Mono']),
      (
        'assets/fonts/OFL-NotoSans.txt',
        <String>['Noto Sans Arabic', 'Noto Sans Devanagari'],
      ),
    ];
    expect(entries, hasLength(sources.length));
    for (int index = 0; index < sources.length; index++) {
      final (String asset, List<String> packages) = sources[index];
      expect(entries[index].packages, packages);
      final String authentic = await rootBundle.loadString(asset);
      final String shown = entries[index].paragraphs
          .map((LicenseParagraph paragraph) => paragraph.text)
          .join(' ');
      expect(_normalized(shown), _normalized(authentic));
      expect(shown, contains('SIL OPEN FONT LICENSE'));
    }
    LicenseRegistry.reset();
  });
}
