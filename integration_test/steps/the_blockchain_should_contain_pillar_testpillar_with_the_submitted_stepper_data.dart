// The BDD usage line intentionally mirrors the complete Gherkin step.
// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../support/devnet_pillar_observation.dart';
import '../support/devnet_test_context.dart';

/// Usage: the blockchain should contain pillar testPillar with the submitted stepper data
Future<void>
theBlockchainShouldContainPillarTestpillarWithTheSubmittedStepperData(
  WidgetTester tester,
) async {
  final DevnetTestContext context = app.sl<DevnetTestContext>();
  final DevnetPillarObservation observation =
      DevnetPillarObservation.forScenario(context);
  final AccountBlockTemplate expectedBlock = observation.originalBlock;
  const String name = DevnetTestContext.testPillarName;
  const String owner = DevnetTestContext.testPillarOwnerAddress;
  const String rewardAddress = DevnetTestContext.testPillarRewardAddress;
  const String producerAddress = DevnetTestContext.testPillarProducerAddress;
  const int momentumReward = DevnetTestContext.testPillarMomentumReward;
  const int delegationReward = DevnetTestContext.testPillarDelegationReward;

  final AccountBlock createdBlock = await observation.readBlock(tester);

  expect(createdBlock, isNotNull);
  expect(createdBlock.hash, expectedBlock.hash);
  expect(createdBlock.address, Address.parse(owner));
  expect(createdBlock.toAddress, pillarAddress);
  expect(createdBlock.tokenStandard, znnZts);
  expect(createdBlock.amount, pillarRegisterZnnAmount);

  final BlockData? blockData = AccountBlockUtils.getDecodedBlockData(
    Definitions.pillar,
    createdBlock.data,
  );
  expect(blockData, isNotNull);
  expect(blockData!.function, 'Register');
  expect(blockData.params['name'], name);
  expect(blockData.params['producerAddress'].toString(), producerAddress);
  expect(blockData.params['rewardAddress'].toString(), rewardAddress);
  expect(
    int.parse(blockData.params['giveBlockRewardPercentage'].toString()),
    momentumReward,
  );
  expect(
    int.parse(blockData.params['giveDelegateRewardPercentage'].toString()),
    delegationReward,
  );

  final PillarInfo pillarInfo = await observation.readPillar(tester);

  expect(pillarInfo, isNotNull);
  expect(pillarInfo.name, name);
  expect(pillarInfo.ownerAddress, Address.parse(owner));
  expect(pillarInfo.withdrawAddress, Address.parse(rewardAddress));
  expect(pillarInfo.producerAddress, Address.parse(producerAddress));
  expect(pillarInfo.giveMomentumRewardPercentage, momentumReward);
  expect(pillarInfo.giveDelegateRewardPercentage, delegationReward);
}
