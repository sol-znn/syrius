import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/utils/address_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/file_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/functions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/locale_notifier.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_file.dart';
import 'package:zenon_syrius_wallet_flutter/utils/widget_utils.dart';
import 'package:znn_ledger_dart/znn_ledger_dart.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The texts the helpers under `lib/utils` and the two workers showed before
/// they were moved into `app_en.arb`, written out here so that a change of a
/// single character fails.

PlasmaInfo _plasma(int current) => PlasmaInfo(
  currentPlasma: current,
  maxPlasma: current,
  qsrAmount: BigInt.zero,
);

void main() {
  late Directory dir;

  String pathOf(String name) => '${dir.path}${Platform.pathSeparator}$name';

  /// A wallet file that says it is of [walletType].
  Future<String> walletFileOfType(String name, String walletType) async {
    final EncryptedFile encrypted = await EncryptedFile.encrypt(
      List<int>.filled(32, 7),
      'password',
      metadata: <String, dynamic>{walletTypeKey: walletType},
    );
    final String path = pathOf(name);
    File(path).writeAsStringSync(json.encode(encrypted));
    return path;
  }

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('utils_l10n');
    Hive.init(pathOf('hive'));
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  setUp(() {
    // The language is the one of the notifier made last.
    LocaleNotifier(AppLanguage.english);
  });

  group('helpers, in English', () {
    test('WidgetUtils.getPlasmaToolTipMessage', () {
      expect(
        WidgetUtils.getPlasmaToolTipMessage(_plasma(kPillarPlasmaAmountNeeded)),
        'High Plasma',
      );
      expect(
        WidgetUtils.getPlasmaToolTipMessage(
          _plasma(kIssueTokenPlasmaAmountNeeded),
        ),
        'Average Plasma',
      );
      expect(
        WidgetUtils.getPlasmaToolTipMessage(_plasma(minPlasmaAmount.toInt())),
        'Low Plasma',
      );
      expect(
        WidgetUtils.getPlasmaToolTipMessage(_plasma(0)),
        'Insufficient Plasma',
      );
    });

    test('messageBytesToSign', () {
      expect(messageBytesToSign('a' * 31), hasLength(31));
      expect(
        () => messageBytesToSign('a' * 32),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            'A 32 byte message is refused. Pad it',
          ),
        ),
      );
    });

    test('text signing encodes Unicode as UTF-8', () {
      expect(
        messageBytesToSign('A\u00e9\u{1f680}'),
        <int>[0x41, 0xc3, 0xa9, 0xf0, 0x9f, 0x9a, 0x80],
      );
    });

    test('text signing refuses 32 encoded bytes before wallet acquisition', () {
      for (final String message in <String>[
        '\u00e9' * 16,
        '\u{1f680}' * 8,
        '${'a' * 30}\u00e9',
      ]) {
        expect(utf8.encode(message), hasLength(32));
        expect(message.codeUnits.length, isNot(32));
        expect(
          () => walletSignMessage(message),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('text signing preserves the neighboring Unicode byte lengths', () {
      expect(
        messageBytesToSign('${'\u00e9' * 15}a'),
        hasLength(31),
      );
      expect(
        messageBytesToSign('${'\u00e9' * 16}a'),
        hasLength(33),
      );
    });

    test('FileUtils.deleteFile and deleteDirectory', () async {
      final String missing = pathOf('none');
      await expectLater(
        FileUtils.deleteFile(missing),
        throwsA('There is no file at the following path: $missing'),
      );
      await expectLater(
        FileUtils.deleteDirectory(missing),
        throwsA('There is no directory at the following path: $missing'),
      );
    });

    test('WalletFile.read', () async {
      final String missing = pathOf('no-wallet');
      await expectLater(
        WalletFile.read(missing),
        throwsA(
          isA<WalletException>().having(
            (WalletException e) => e.message,
            'message',
            'Given wallet path does not exist ($missing)',
          ),
        ),
      );
    });

    test('WalletFile.decrypt and its two kinds', () async {
      Matcher notSupported(String walletType) => throwsA(
        isA<WalletException>().having(
          (WalletException e) => e.message,
          'message',
          'Wallet type ($walletType) is not supported',
        ),
      );

      await expectLater(
        WalletFile.decrypt(
          await walletFileOfType('unknown', 'trezor'),
          'password',
        ),
        notSupported('trezor'),
      );
      await expectLater(
        KeyStoreWalletFile.decrypt(
          await walletFileOfType('ledger', ledgerWalletType),
          'password',
        ),
        notSupported(ledgerWalletType),
      );
      await expectLater(
        LedgerWalletFile.decrypt(
          await walletFileOfType('keystore', keyStoreWalletType),
          'password',
        ),
        notSupported(keyStoreWalletType),
      );
    });

    test('the titles that were constants', () {
      expect(kIncorrectPasswordNotificationTitle, 'Incorrect password');
      expect(kUnlockFailedNotificationTitle, 'Unlock failed');
      // An identifier, saved as the selected node: the same in any language.
      expect(kEmbeddedNode, 'Embedded Node');
    });

    test('ZenonAddressUtils.setAddressLabels', () async {
      final String first = emptyAddress.toString();
      final String second = plasmaAddress.toString();
      kDefaultAddressList = <String?>[first, second];
      addTearDown(() {
        kDefaultAddressList = <String?>[];
        kAddressLabelMap = <String, String>{};
      });

      await ZenonAddressUtils.setAddressLabels();

      expect(kAddressLabelMap, <String, String>{
        first: 'Address 1',
        second: 'Address 2',
      });
    });
  });

  group('messages with no function a test can call, in English', () {
    late AppLocalizations l10n;

    setUp(() => l10n = currentL10n);

    test('node and account-block notifications', () {
      expect(
        l10n.nodeSyncingNotificationTitle,
        'The node is still syncing with the network. Please wait until the '
        'loading circle turns green before sending any transactions',
      );
      expect(
        l10n.nodeSyncingNotificationDetails,
        'The information displayed in the wallet does not reflect the most '
        'recent network state. Operations should not be performed, as they '
        'will likely become invalid by the time the node is fully synced',
      );
      expect(
        l10n.accountBlockPublishedNotificationTitle,
        'Account-block published',
      );
      expect(
        l10n.accountBlockPublishedNotificationDetails('User send'),
        'Account-block type: User send',
      );
      expect(
        l10n.accountBlockReviewSendNotificationTitle,
        'Sending transaction, please review the transaction on your hardware '
        'device',
      );
      expect(
        l10n.accountBlockReviewReceiveNotificationTitle,
        'Receiving transaction, please review the transaction on your '
        'hardware device',
      );
      expect(
        l10n.accountBlockReviewNotificationDetails('User receive'),
        'Review account-block type: User receive',
      );
      expect(
        l10n.embeddedNodeStoppingNotificationTitle,
        'Waiting for Embedded Node to stop',
      );
      expect(
        l10n.embeddedNodeStoppingNotificationDetails,
        'The app will close after the Embedded Node has been stopped',
      );
      expect(
        l10n.nodeLocalTimeDiscrepancyError,
        'Local time discrepancy detected.',
      );
    });

    test('address, link and clipboard', () {
      expect(
        l10n.addressAddConfirmNotificationTitle,
        'Adding address, please confirm the address on your hardware device',
      );
      expect(
        l10n.addressAddConfirmNotificationDetails(3),
        'Confirm address for account index: 3',
      );
      // A position, not a count: no plural, and no digit grouping.
      expect(l10n.addressDefaultLabel(1), 'Address 1');
      expect(l10n.addressDefaultLabel(1000), 'Address 1000');
      expect(
        l10n.addressGenerateFailedNotificationTitle,
        'Error while generating new address',
      );
      expect(
        l10n.openUrlFailedNotificationTitle('https://zenon.network'),
        'Error while trying to open https://zenon.network',
      );
      expect(
        l10n.openUrlFailedNotificationDetails('https://zenon.network'),
        'Something went wrong while trying to open https://zenon.network',
      );
      expect(l10n.copied, 'Copied');
      expect(
        l10n.clipboardPasteError,
        'The clipboard data could not be obtained',
      );
      expect(
        l10n.clipboardPasteFailedNotificationTitle,
        'Something went wrong while getting the clipboard data',
      );
      expect(
        l10n.walletFileLedgerNotFoundError,
        'Cannot find the hardware device, please connect/unlock the device '
        'on which the wallet is initialized',
      );
    });

    test('the two workers and completing a swap', () {
      expect(
        l10n.autoReceiveFailedNotificationTitle,
        'Receive transaction failed',
      );
      expect(
        l10n.autoReceiveFailedNotificationDetails('boom'),
        'Failed to receive the transaction: boom',
      );
      expect(
        l10n.transactionReceivedNotificationTitle('Address 1'),
        'Transaction received on Address 1',
      );
      expect(
        l10n.transactionReceivedNotificationDetails('$emptyHash'),
        'Transaction hash: $emptyHash',
      );
      expect(l10n.autoUnlockInvalidSwapError, 'Invalid swap');
      expect(
        l10n.autoUnlockAddressNotInWalletError,
        'Swap address not in default addresses. Please add the address in '
        'the addresses list.',
      );
      expect(l10n.autoUnlockFailedNotificationTitle, 'Failed to complete swap');
      expect(
        l10n.autoUnlockFailedNotificationDetails('boom'),
        'Failed to complete the swap: boom',
      );
      expect(
        l10n.completeSwapExpiresTooSoonError,
        'The swap will expire too soon for a safe swap.',
      );
      expect(
        l10n.completeSwapSecretTooLargeError,
        'The swap secret size exceeds the maximum allowed size.',
      );
    });
  });
}
