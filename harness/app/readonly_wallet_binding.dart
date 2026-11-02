import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_transition.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_file.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'native_window_owner.dart';
import 'readonly_wallet_admission.dart';

/// Observes the genuinely opened index-one lab wallet without acquiring it.
/// No address, profile path, SDK query or native handle enters the receipt.
Future<ReadonlyWalletAdmission> bindReadonlyNativeWallet({
  required NativeWindowOwner window,
  required RenderView Function() readView,
}) {
  final WalletFile? file = kWalletFile;
  final String? path = kWalletPath;
  final Zenon? sdk = app.zenon;
  final SharedPrefsService? preferences = app.sharedPrefsService;
  final NavigatorState? navigator = app.globalNavigatorKey.currentState;
  final Element? root = WidgetsBinding.instance.rootElement;
  final List<String?> members = List<String?>.of(kDefaultAddressList);
  if (file == null || sdk == null || preferences == null || path == null ||
      navigator == null || root == null || members.length < 2 ||
      members.length > 128 || members.any((String? value) => value == null) ||
      !Hive.isBoxOpen(kKeyStoreBox) || !Hive.isBoxOpen(kAddressesBox) ||
      !Hive.isBoxOpen(kSharedPrefsBox)) {
    throw const ReadonlyWalletAdmissionRefused();
  }
  final Box<dynamic> pointer = Hive.box<dynamic>(kKeyStoreBox);
  final Box<dynamic> addresses = Hive.box<dynamic>(kAddressesBox);
  final Box<dynamic> prefs = Hive.box<dynamic>(kSharedPrefsBox);
  final WsClient socket = sdk.wsClient;
  final LedgerApi ledgerSource = sdk.ledger;
  final StatsApi statsSource = sdk.stats;
  final EmbeddedApi embeddedSource = sdk.embedded;
  final HtlcApi htlcSource = embeddedSource.htlc;
  final SubscribeApi subscribeSource = sdk.subscribe;
  final RenderView view = readView();
  final ui.FlutterView flutterView = view.flutterView;
  final int revision = WalletContextRevision.value;
  final NativeWindowStartupReceipt? startup = window.startup().receipt;
  if (startup == null) throw const ReadonlyWalletAdmissionRefused();

  bool owns(Box<dynamic> box) => box.isOpen && Hive.isBoxOpen(box.name) &&
      identical(Hive.box<dynamic>(box.name), box);
  bool current() =>
      identical(kWalletFile, file) && kWalletPath == path &&
      file.walletPath == path && !file.isOpen && !file.isHardwareWallet &&
      kWalletInitCompleted && !NodeTransitions.pending &&
      WalletContextRevision.value == revision &&
      listEquals(kDefaultAddressList, members) &&
      kSelectedAddress == members[1] &&
      owns(pointer) && pointer.length == 1 && pointer.get(0) == path &&
      owns(addresses) && listEquals(addresses.values.toList(), members) &&
      owns(prefs) && prefs.get(kDefaultAddressKey) == members[1] &&
      prefs.get(kChainIdKey, defaultValue: kChainIdDefaultValue) == 321 &&
      prefs.get(kSelectedNodeKey) == 'ws://127.0.0.1:45998' &&
      prefs.get(kAutoReceiveKey, defaultValue: kAutoReceiveDefaultValue) ==
          false &&
      getChainIdentifier() == 321 && kNodeChainId == 321 &&
      kCurrentNode == 'ws://127.0.0.1:45998' &&
      identical(app.sharedPrefsService, preferences) &&
      identical(app.zenon, sdk) && app.sl.isRegistered<Zenon>() &&
      identical(app.sl<Zenon>(), sdk) && identical(sdk.wsClient, socket) &&
      socket.url == 'ws://127.0.0.1:45998' &&
      socket.status() == WebsocketStatus.running && !socket.isClosed() &&
      identical(sdk.ledger, ledgerSource) &&
      identical(ledgerSource.client, socket) &&
      identical(sdk.stats, statsSource) &&
      identical(statsSource.client, socket) &&
      identical(sdk.embedded, embeddedSource) &&
      identical(embeddedSource.client, socket) &&
      identical(embeddedSource.htlc, htlcSource) &&
      identical(htlcSource.client, socket) &&
      identical(sdk.subscribe, subscribeSource) &&
      identical(subscribeSource.client, socket) &&
      root.mounted && identical(WidgetsBinding.instance.rootElement, root) &&
      navigator.mounted &&
      identical(app.globalNavigatorKey.currentState, navigator) &&
      view.attached && identical(readView(), view) &&
      identical(view.flutterView, flutterView) && window.isCurrent(startup);

  return ReadonlyWalletAdmission.seal(
    ownersCurrent: current,
    observeFrame: () async {
      final NativeWindowCall<NativeWindowFrameReceipt> frame =
          window.requestFrame();
      if (frame.original == null) {
        throw const ReadonlyWalletAdmissionRefused();
      }
      final NativeWindowFrameReceipt receipt = await frame.completion;
      if (!identical(receipt.startup, startup) ||
          !identical(frame.receipt, receipt)) {
        throw const ReadonlyWalletAdmissionRefused();
      }
    },
  );
}
