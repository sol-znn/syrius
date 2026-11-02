import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:zenon_syrius_wallet_flutter/embedded_node/node_library.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/metadata.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Local facts shown by About. No field asks the connected node for data.
enum AboutField {
  /// The kind of the currently selected wallet file.
  walletType,

  /// The Zenon SDK version shipped with the application.
  sdk,

  /// Build metadata supplied by the release process.
  branch,

  /// The full defined source commit.
  commit,

  /// The defined source commit message.
  commitMessage,

  /// The defined source commit date, without an inferred build date.
  commitDate,

  /// The defined source repository URL.
  origin,

  /// Local platform details, shown only inside This computer.
  hostname,

  /// The local address already known to the application.
  localIp,

  /// The actual operating-system name.
  operatingSystem,

  /// The actual operating-system version text.
  operatingSystemVersion,

  /// The platform's available processor count.
  processors,

  /// Existing application folders, never included in reports or logs.
  zenonData,

  /// The existing application cache folder.
  cache,

  /// The existing wallet folder.
  wallet,
}

/// An immutable display snapshot; absent facts remain absent until rendered.
class AboutInformation {
  /// Creates a snapshot without reaching a platform, wallet or filesystem.
  AboutInformation({
    this.version,
    this.buildNumber,
    this.embeddedNodeVersion,
    Map<AboutField, String> details = const <AboutField, String>{},
  }) : details = Map<AboutField, String>.unmodifiable(details);

  /// Uses only a record belonging to this process, never an installed tag.
  factory AboutInformation.fromSources({
    required PackageInfo? package,
    required LoadedNodeLibrary? loaded,
    required int processId,
    Map<AboutField, String> details = const <AboutField, String>{},
  }) => AboutInformation(
    version: package?.version,
    buildNumber: package?.buildNumber,
    embeddedNodeVersion: loaded?.pid == processId
        ? loaded?.manifest?.tag
        : null,
    details: details,
  );

  /// The installed application's version, preserving its actual text.
  final String? version;

  /// The installed application's build number, preserving leading zeros.
  final String? buildNumber;

  /// A tag recorded for the native library loaded in this process.
  final String? embeddedNodeVersion;

  /// Captured local and defined build facts.
  final Map<AboutField, String> details;

  /// A short build value; the full values remain in This computer.
  String get build {
    final String commit = details[AboutField.commit] ?? '';
    return <String>[
      if (_hasText(buildNumber)) buildNumber!,
      if (_hasText(commit))
        if (commit.length > 8) commit.substring(0, 8) else commit,
      if (_hasText(details[AboutField.commitDate]))
        details[AboutField.commitDate]!,
    ].join(' · ');
  }
}

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

String _readLocal(String Function() read) {
  try {
    return read();
  } on Object {
    return '';
  }
}

/// Reads existing local sources, without starting or probing a native node.
Future<AboutInformation> readAboutInformation() async {
  final Map<AboutField, String> details = <AboutField, String>{
    AboutField.walletType: kWalletFile?.walletType ?? '',
    AboutField.sdk: znnSdkVersion,
    AboutField.branch: gitBranchName,
    AboutField.commit: gitCommitHash,
    AboutField.commitMessage: gitCommitMessage,
    AboutField.commitDate: gitCommitDate,
    AboutField.origin: gitOriginUrl,
    AboutField.hostname: _readLocal(() => Platform.localHostname),
    AboutField.localIp: kLocalIpAddress ?? '',
    AboutField.operatingSystem: _readLocal(() => Platform.operatingSystem),
    AboutField.operatingSystemVersion: _readLocal(
      () => Platform.operatingSystemVersion,
    ),
    AboutField.processors: _readLocal(
      Platform.numberOfProcessors.toString,
    ),
    AboutField.zenonData: _readLocal(() => znnDefaultPaths.main.absolute.path),
    AboutField.cache: _readLocal(() => znnDefaultPaths.cache.absolute.path),
    AboutField.wallet: _readLocal(() => znnDefaultPaths.wallet.absolute.path),
  };
  LoadedNodeLibrary? loaded;
  try {
    loaded = NodeLibrary.forThisInstall().loadedInThisProcess();
  } on Object {
    // A missing or unreadable record cannot establish the loaded version.
  }
  PackageInfo? package;
  try {
    package = await PackageInfo.fromPlatform();
  } on Object {
    // A platform metadata failure is an unknown version, not a release guess.
  }
  return AboutInformation.fromSources(
    package: package,
    loaded: loaded,
    processId: pid,
    details: details,
  );
}
