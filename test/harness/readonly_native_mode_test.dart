import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/utils/original_publications.dart';

import '../../harness/app/presentation_mode.dart';
import '../../harness/app/readonly_native_commands.dart';
import '../../harness/app/readonly_native_mode.dart';
import '../../harness/app/readonly_sdk_admission.dart';
import '../../harness/bin/harness.dart' as cli;

class _PrivateFailure implements Exception {
  @override
  String toString() => throw StateError('The private formatter must not run');
}

class _UnusedInstance extends cli.Instance {
  _UnusedInstance(super.name);

  int accesses = 0;

  @override
  String get home {
    accesses++;
    throw StateError('The refused launch must not inspect a profile');
  }

  @override
  Future<bool> alive() async {
    accesses++;
    throw StateError('The refused launch must not contact an instance');
  }
}

Map<String, dynamic> _ready() => <String, dynamic>{
  'pid': 44,
  'harnessMode': 'readonly-native',
  'booted': true,
  'readOnly': true,
  'readonlyAdmission': <String, dynamic>{
    'schema': 1,
    'scope': 'readonly_native_sdk_admission',
    'status': 'CURRENT',
    'publicationAdmissionPaused': true,
    'automaticReceiveDisabled': true,
  },
};

Map<String, dynamic> _wallet() => <String, dynamic>{
  ..._ready(),
  'readonlyWallet': <String, dynamic>{
    'schema': 1, 'scope': 'readonly_native_wallet_admission',
    'status': 'CURRENT',
    'chain': 321, 'selectedIndex': 1, 'nativeFrameObserved': true,
  },
};

void main() {
  test('opened-wallet admission requires its own exact current receipt', () {
    expect(harnessReadonlyNativeWalletMatches(_wallet(), 44), isTrue);
    expect(harnessReadonlyNativeWalletMatches(_ready(), 44), isFalse);
  });

  test('a wallet receipt cannot borrow another process or ordinary mode', () {
    expect(harnessReadonlyNativeWalletMatches(_wallet(), 45), isFalse);
    expect(harnessReadonlyNativeWalletMatches(_wallet(), null), isFalse);
    final Map<String, dynamic> ordinary = _wallet()..['harnessMode'] = 'wallet';
    expect(harnessReadonlyNativeWalletMatches(ordinary, 44), isFalse);
  });

  test('expanded coerced pending or non-native wallet proofs are refused', () {
    for (final Map<String, Object?> change in <Map<String, Object?>>[
      <String, Object?>{'schema': true},
      <String, Object?>{'scope': 'wallet_page_tour'},
      <String, Object?>{'status': 'PENDING'},
      <String, Object?>{'chain': 321.0},
      <String, Object?>{'selectedIndex': true},
      <String, Object?>{'nativeFrameObserved': false},
      <String, Object?>{'extra': true},
    ]) {
      final Map<String, dynamic> observed = _wallet();
      (observed['readonlyWallet'] as Map<String, dynamic>).addAll(change);
      expect(harnessReadonlyNativeWalletMatches(observed, 44), isFalse);
    }
  });

  test('a wallet proof cannot replace missing current SDK admission', () {
    for (final Object? admission in <Object?>[
      null, <String, Object?>{'status': 'CURRENT'},
    ]) {
      final Map<String, dynamic> observed = _wallet()
        ..['readonlyAdmission'] = admission;
      expect(harnessReadonlyNativeWalletMatches(observed, 44), isFalse);
    }
  });

  test('absent inspection preserves ordinary and presentation startup', () {
    for (final bool windows in <bool>[false, true]) {
      for (final String? presentation in <String?>[null, 'welcome']) {
        expect(
          harnessReadonlyNativeRequested(
            const <String, String>{},
            windows: windows,
            presentation: presentation,
          ),
          isFalse,
        );
      }
    }
  });

  test('only explicit Windows CI inspection is admitted', () {
    expect(
      harnessReadonlyNativeRequested(
        const <String, String>{
          harnessReadonlyNativeEnvironment: 'true',
          'GITHUB_ACTIONS': 'true',
        },
        windows: true,
        presentation: null,
      ),
      isTrue,
    );
  });

  test('supplied unknown values cannot become ordinary startup', () {
    for (final String value in <String>['', 'false', 'TRUE', '1']) {
      expect(
        () => harnessReadonlyNativeRequested(
          <String, String>{
            harnessReadonlyNativeEnvironment: value,
            'GITHUB_ACTIONS': 'true',
          },
          windows: true,
          presentation: null,
        ),
        throwsA(isA<ReadonlyNativeModeRefused>()),
      );
    }
  });

  test('platform CI and presentation boundaries stay independent', () {
    for (final (bool, String?, String?) scope
        in <(bool, String?, String?)>[
          (false, 'true', null),
          (true, null, null),
          (true, 'false', null),
          (true, 'true', 'welcome'),
          (true, 'true', 'import'),
        ]) {
      expect(
        () => harnessReadonlyNativeRequested(
          <String, String>{
            harnessReadonlyNativeEnvironment: 'true',
            if (scope.$2 != null) 'GITHUB_ACTIONS': scope.$2!,
          },
          windows: scope.$1,
          presentation: scope.$3,
        ),
        throwsA(isA<ReadonlyNativeModeRefused>()),
      );
    }
  });

  test('ordinary launcher removes inherited inspection in either case', () {
    final Map<String, String> parent = <String, String>{
      harnessReadonlyNativeEnvironment: 'true',
      'syrius_ci_readonly_inspection': 'true',
      'GITHUB_ACTIONS': 'true',
    };
    final Map<String, String> launched = harnessLaunchEnvironment(
      parent,
      profileHome: 'fixture-home',
      appData: 'fixture-roaming',
      localAppData: 'fixture-local',
      temporary: 'fixture-temporary',
      port: 12345,
      token: 'fixture-token',
    );
    expect(launched.containsKey(harnessReadonlyNativeEnvironment), isFalse);
    expect(launched.containsKey('syrius_ci_readonly_inspection'), isFalse);
    expect(parent[harnessReadonlyNativeEnvironment], 'true');
    expect(
      harnessLaunchMatches(<String, dynamic>{
        'harnessMode': 'readonly-native',
        'pid': 44,
      }),
      isFalse,
    );
  });

  test('finite transport codes never format unknown private errors', () {
    expect(
      readonlyNativeRefusalCode(const ReadonlyNativeCommandRefused()),
      'READONLY_NATIVE_COMMAND_REFUSED',
    );
    expect(
      readonlyNativeRefusalCode(const ReadonlySdkAdmissionRefused()),
      'READONLY_NATIVE_SDK_REFUSED',
    );
    expect(
      readonlyNativeRefusalCode(const OriginalPublicationRefused()),
      'READONLY_NATIVE_PUBLICATION_REFUSED',
    );
    expect(readonlyNativeRefusalCode(_PrivateFailure()), isNull);
  });

  test('programmatic inspection admits only an explicit unused CI scope', () {
    requireReadonlyNativeLaunch(
      const <String, String>{'GITHUB_ACTIONS': 'true'},
      windows: true,
      instance: 'ci-inspect-0123456789abcdef01234567',
      fresh: false,
      presentation: null,
    );
  });

  test('invalid inspection scope cannot authorize profile access or deletion',
      () {
    for (final (bool, String?, String, bool, String?) scope
        in <(bool, String?, String, bool, String?)>[
          (false, 'true', 'ci-inspect-0123456789abcdef01234567', false, null),
          (true, null, 'ci-inspect-0123456789abcdef01234567', false, null),
          (true, 'false', 'ci-inspect-0123456789abcdef01234567', false, null),
          (true, 'true', 'default', false, null),
          (true, 'true', 'ci-wallet-0123456789abcdef01234567', false, null),
          (true, 'true', 'ci-inspect-0123456789ABCDEF01234567', false, null),
          (true, 'true', 'ci-inspect-0123456789abcdef01234567', true, null),
          (
            true, 'true', 'ci-inspect-0123456789abcdef01234567',
            false, 'welcome',
          ),
        ]) {
      expect(
        () => requireReadonlyNativeLaunch(
          <String, String>{if (scope.$2 != null) 'GITHUB_ACTIONS': scope.$2!},
          windows: scope.$1,
          instance: scope.$3,
          fresh: scope.$4,
          presentation: scope.$5,
        ),
        throwsA(isA<ReadonlyNativeModeRefused>()),
      );
    }
  });

  test('only explicit launch selection supplies one inspection environment',
      () {
    final Map<String, String> parent = <String, String>{
      'GITHUB_ACTIONS': 'true',
      harnessReadonlyNativeEnvironment: 'inherited-value',
      'syrius_ci_readonly_inspection': 'another-inherited-value',
    };
    final Map<String, String> launched = harnessLaunchEnvironment(
      parent,
      profileHome: 'fixture-home',
      appData: 'fixture-roaming',
      localAppData: 'fixture-local',
      temporary: 'fixture-temporary',
      port: 12345,
      token: 'fixture-token',
      readonlyNative: true,
      windows: true,
    );
    expect(launched[harnessReadonlyNativeEnvironment], 'true');
    expect(launched.containsKey('syrius_ci_readonly_inspection'), isFalse);
    expect(parent[harnessReadonlyNativeEnvironment], 'inherited-value');
    expect(parent['syrius_ci_readonly_inspection'], 'another-inherited-value');
  });

  test('inspection environment refuses a wrong platform CI or preview', () {
    for (final (bool, String?, String?) scope
        in <(bool, String?, String?)>[
          (false, 'true', null),
          (true, null, null),
          (true, 'false', null),
          (true, 'true', 'welcome'),
        ]) {
      expect(
        () => harnessLaunchEnvironment(
          <String, String>{if (scope.$2 != null) 'GITHUB_ACTIONS': scope.$2!},
          profileHome: 'fixture-home',
          appData: 'fixture-roaming',
          localAppData: 'fixture-local',
          temporary: 'fixture-temporary',
          port: 12345,
          token: 'fixture-token',
          readonlyNative: true,
          windows: scope.$1,
          presentation: scope.$3,
        ),
        throwsA(isA<ReadonlyNativeModeRefused>()),
      );
    }
  });

  test('inspection launch binds only a ready original process SDK receipt', () {
    expect(harnessLaunchMatches(_ready(), readonlyNative: true,
        expectedPid: 44), isTrue);
    expect(harnessLaunchMatches(_ready(), readonlyNative: true), isFalse);
    expect(harnessLaunchMatches(_ready(), readonlyNative: true,
        expectedPid: 45), isFalse);
    expect(harnessLaunchMatches(_ready(), readonlyNative: true,
        expectedPid: 44, presentation: 'welcome'), isFalse);
    for (final MapEntry<String, Object> changed in <String, Object>{
      'pid': 44.0,
      'harnessMode': 'wallet',
      'booted': false,
      'readOnly': false,
    }.entries) {
      expect(harnessLaunchMatches(<String, dynamic>{
        ..._ready(), changed.key: changed.value,
      }, readonlyNative: true, expectedPid: 44), isFalse);
    }
  });

  test('pending malformed or expanded SDK receipts cannot qualify launch', () {
    final Map<String, dynamic> original =
        _ready()['readonlyAdmission'] as Map<String, dynamic>;
    for (final Map<String, dynamic> admission in <Map<String, dynamic>>[
      <String, dynamic>{},
      <String, dynamic>{...original, 'schema': 1.0},
      <String, dynamic>{...original, 'scope': 'wallet'},
      <String, dynamic>{...original, 'status': 'PENDING'},
      <String, dynamic>{...original, 'publicationAdmissionPaused': false},
      <String, dynamic>{...original, 'automaticReceiveDisabled': false},
      <String, dynamic>{...original, 'additionalAcceptance': true},
    ]) {
      expect(harnessLaunchMatches(<String, dynamic>{
        ..._ready(), 'readonlyAdmission': admission,
      }, readonlyNative: true, expectedPid: 44), isFalse);
    }
  });

  test('actual launcher refuses unsafe scope before observing any profile',
      () async {
    for (final String name in <String>[
      'default', 'ci-wallet-0123456789abcdef01234567',
      'ci-inspect-0123456789abcdef01234567',
    ]) {
      final _UnusedInstance instance = _UnusedInstance(name);
      await expectLater(
        cli.start(instance, cli.Args(<String>['--fresh']),
            readonlyNative: true),
        throwsA(isA<cli.Fail>()),
      );
      expect(instance.accesses, 0);
    }
  });
}
