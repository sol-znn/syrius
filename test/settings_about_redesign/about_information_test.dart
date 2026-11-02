import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:zenon_syrius_wallet_flutter/embedded_node/node_library.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/help_widgets/about_information.dart';

LoadedNodeLibrary _loaded({
  int processId = 42,
  String? tag = 'v2.4.6',
  bool bundled = false,
}) => LoadedNodeLibrary(
  path: 'fixture-library',
  kind: bundled ? NodeLibraryKind.bundled : NodeLibraryKind.override,
  pid: processId,
  loadedAt: DateTime.utc(2026),
  manifest: bundled
      ? null
      : NodeLibraryManifest(
          source: 'example/node',
          asset: 'fixture-library',
          sha256: 'a' * 64,
          tag: tag,
          installedAt: DateTime.utc(2026),
        ),
);

void main() {
  test('version and build preserve the actual PackageInfo strings', () {
    final AboutInformation information = AboutInformation.fromSources(
      package: PackageInfo(
        appName: 'Fixture wallet',
        packageName: 'example.wallet',
        version: '9.8.7-rc.2',
        buildNumber: '00042',
      ),
      loaded: null,
      processId: 42,
    );
    expect(information.version, '9.8.7-rc.2');
    expect(information.buildNumber, '00042');
    expect(information.build, '00042');
    expect(information.embeddedNodeVersion, isNull);
  });

  test('only a current-process loaded manifest contributes a node tag', () {
    for (final (LoadedNodeLibrary?, String?) variant
        in <(LoadedNodeLibrary?, String?)>[
          (_loaded(), 'v2.4.6'),
          (_loaded(processId: 43), null),
          (_loaded(bundled: true), null),
          (_loaded(tag: null), null),
          (null, null),
        ]) {
      final AboutInformation information = AboutInformation.fromSources(
        package: null,
        loaded: variant.$1,
        processId: 42,
      );
      expect(information.embeddedNodeVersion, variant.$2);
      expect(information.version, isNull);
      expect(information.buildNumber, isNull);
    }
  });

  test(
    'defined metadata is preserved without inventing missing build parts',
    () {
      final Map<AboutField, String> details = <AboutField, String>{
        AboutField.commit: 'abcdef1234567890',
        AboutField.commitDate: '2026-10-23',
        AboutField.branch: '',
      };
      final AboutInformation information = AboutInformation(details: details);
      details[AboutField.commit] = 'changed-source';
      expect(information.build, 'abcdef12 · 2026-10-23');
      expect(information.details[AboutField.commit], 'abcdef1234567890');
      expect(information.details.clear, throwsUnsupportedError);
      expect(AboutInformation().build, isEmpty);
      expect(AboutInformation(buildNumber: '  ').build, isEmpty);
    },
  );
}
