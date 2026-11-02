import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/original_publications.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart' show Zenon;

import '../../harness/app/readonly_sdk_admission.dart';
import '../../harness/app/readonly_sdk_binding.dart';

class _Sdk extends Fake implements Zenon {}

void main() {
  Directory? root;
  final Set<Zenon> sdkOwners = Set<Zenon>.identity();
  final Set<SharedPrefsService> preferenceOwners =
      Set<SharedPrefsService>.identity();
  final List<Box<dynamic>> boxes = <Box<dynamic>>[];
  late Zenon sdk;
  late SharedPrefsService preferences;
  late Box<dynamic> box;

  setUp(() async {
    expect(app.zenon, isNull);
    expect(app.sharedPrefsService, isNull);
    expect(app.sl.isRegistered<Zenon>(), isFalse);
    expect(kWalletFile, isNull);
    expect(kWalletInitCompleted, isFalse);
    root = await Directory.systemTemp.createTemp('syrius-readonly-sdk-');
    Hive.init(root!.path);
    preferences = (await SharedPrefsService.getInstance())!;
    preferenceOwners.add(preferences);
    app.sharedPrefsService = preferences;
    box = Hive.box<dynamic>(kSharedPrefsBox);
    boxes.add(box);
    sdk = _Sdk();
    sdkOwners.add(sdk);
    app.sl.registerSingleton<Zenon>(sdk);
    app.zenon = sdk;
  });

  tearDown(() async {
    if (sdkOwners.contains(app.zenon)) app.zenon = null;
    if (preferenceOwners.contains(app.sharedPrefsService)) {
      app.sharedPrefsService = null;
    }
    if (app.sl.isRegistered<Zenon>() &&
        sdkOwners.contains(app.sl.get<Zenon>())) {
      await app.sl.unregister<Zenon>();
    }
    for (final Box<dynamic> owned in boxes.reversed) {
      if (owned.isOpen) await owned.close();
    }
    if (root case final Directory owned) {
      if (!boxes.any((Box<dynamic> value) => value.isOpen) &&
          owned.existsSync()) {
        await owned.delete(recursive: true);
      }
    }
    root = null;
    boxes.clear();
    sdkOwners.clear();
    preferenceOwners.clear();
  });

  test('the actual Hive preference is disabled before readiness', () async {
    expect(box.get(kAutoReceiveKey), isNull);
    final ReadonlySdkAdmission admission = await sealReadonlyNativeSdk();
    expect(box.get(kAutoReceiveKey), isFalse);
    expect(preferences.get(kAutoReceiveKey), isFalse);
    expect(OriginalPublications.snapshot(sdk), isEmpty);
    admission.requireCurrent();
    await preferences.put(kAutoReceiveKey, true);
    expect(admission.requireCurrent,
        throwsA(isA<ReadonlySdkAdmissionRefused>()));
    await preferences.put(kAutoReceiveKey, false);
    expect(admission.requireCurrent,
        throwsA(isA<ReadonlySdkAdmissionRefused>()));
  });

  test('a different registered SDK refuses before preference writing',
      () async {
    await app.sl.unregister<Zenon>();
    final Zenon replacement = _Sdk();
    sdkOwners.add(replacement);
    app.sl.registerSingleton<Zenon>(replacement);
    await expectLater(
      Future<ReadonlySdkAdmission>.sync(sealReadonlyNativeSdk),
      throwsA(isA<ReadonlySdkAdmissionRefused>()),
    );
    expect(box.get(kAutoReceiveKey), isNull);
    expect(preferences.get(kAutoReceiveKey,
        defaultValue: kAutoReceiveDefaultValue), isTrue);
    expect(OriginalPublications.snapshot(sdk), isEmpty);
    expect(OriginalPublications.snapshot(replacement), isEmpty);
  });

  test('reopening the real Hive box cannot inherit the old admission',
      () async {
    final ReadonlySdkAdmission admission = await sealReadonlyNativeSdk();
    final Box<dynamic> original = box;
    await original.close();
    await preferences.checkIfBoxIsOpen();
    box = Hive.box<dynamic>(kSharedPrefsBox);
    boxes.add(box);
    expect(box, isNot(same(original)));
    expect(admission.requireCurrent,
        throwsA(isA<ReadonlySdkAdmissionRefused>()));
    expect(OriginalPublications.snapshot(sdk), isEmpty);
  });

  test('a replaced preference service stays refused after restoration',
      () async {
    final ReadonlySdkAdmission admission = await sealReadonlyNativeSdk();
    final SharedPrefsService replacement = SharedPrefsService();
    preferenceOwners.add(replacement);
    app.sharedPrefsService = replacement;
    expect(admission.requireCurrent,
        throwsA(isA<ReadonlySdkAdmissionRefused>()));
    app.sharedPrefsService = preferences;
    expect(admission.requireCurrent,
        throwsA(isA<ReadonlySdkAdmissionRefused>()));
    expect(box.get(kAutoReceiveKey), isFalse);
  });

  test('a replaced process SDK stays refused after restoration', () async {
    final ReadonlySdkAdmission admission = await sealReadonlyNativeSdk();
    final Zenon replacement = _Sdk();
    sdkOwners.add(replacement);
    app.zenon = replacement;
    expect(admission.requireCurrent,
        throwsA(isA<ReadonlySdkAdmissionRefused>()));
    app.zenon = sdk;
    expect(admission.requireCurrent,
        throwsA(isA<ReadonlySdkAdmissionRefused>()));
    expect(OriginalPublications.snapshot(sdk), isEmpty);
    expect(OriginalPublications.snapshot(replacement), isEmpty);
  });
}
