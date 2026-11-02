import 'package:zenon_syrius_wallet_flutter/blocs/auto_receive_tx_worker.dart';
import 'package:zenon_syrius_wallet_flutter/utils/original_publications.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'seed_policy.dart';

enum LabQuiescencePhase {
  capture, admission, drain, current, publication, receive, journal, repeated,
}

final class LabQuiescenceRefused implements Exception {
  const LabQuiescenceRefused(this.phase);

  final LabQuiescencePhase phase;

  @override
  String toString() => 'lab-quiescence-${phase.name}-refused';
}

void _need(bool value, LabQuiescencePhase phase) {
  if (!value) throw LabQuiescenceRefused(phase);
}

/// One confirmed UI result and the original owners that must become quiet.
/// Settlement of an SDK error cannot authorize a copied wallet or chain.
final class LabQuiescence {
  LabQuiescence({
    required this.walletOwner,
    required this.sdkOwner,
    required this.worker,
    required this.environment,
    required this.originalSend,
    required String confirmedHash,
    required this._requireCurrent,
    required this._requireJournal,
  }) : _hash = confirmedHash {
    try {
      environment.requireLab();
      _requireCurrent();
      _requireJournal();
      _need(!identical(walletOwner, sdkOwner) && seedHash(_hash) &&
          _matchesSend(), LabQuiescencePhase.capture);
      final List<OriginalPublication<dynamic>> sdk =
          OriginalPublications.snapshot(sdkOwner);
      final List<OriginalPublication<dynamic>> exact = sdk.where(
        (OriginalPublication<dynamic> value) =>
            identical(value.result, originalSend),
      ).toList();
      _need(exact.length == 1 && _positive(exact.single) &&
          exact.single.acceptedHash == _hash &&
          OriginalPublications.snapshot(walletOwner).any(
            (OriginalPublication<dynamic> value) =>
                identical(value, exact.single)), LabQuiescencePhase.capture);
      _original = exact.single;
    } on Object {
      throw const LabQuiescenceRefused(LabQuiescencePhase.capture);
    }
  }

  final Object walletOwner;
  final Object sdkOwner;
  final AutoReceiveTxWorker worker;
  final SeedEnvironment environment;
  final AccountBlockTemplate originalSend;
  final String _hash;
  final void Function() _requireCurrent;
  final void Function() _requireJournal;
  late final OriginalPublication<dynamic> _original;
  bool _attempted = false;

  bool _matchesSend() => originalSend.hash.toString() == _hash &&
      originalSend.chainIdentifier == 321 &&
      originalSend.blockType == BlockTypeEnum.userSend.index &&
      originalSend.address.toString() == environment.members[1] &&
      originalSend.toAddress.toString() == environment.members[0] &&
      originalSend.tokenStandard.toString() == znnZts.toString() &&
      originalSend.amount == BigInt.from(100000000) &&
      originalSend.data.isEmpty;

  static bool _positive(OriginalPublication<dynamic> value) =>
      value.settled && value.future != null && value.error == null &&
      value.releaseError == null;

  /// Every lane closes admission before the first wait. Original operations,
  /// results and accepted hashes stay identical, including failed originals.
  Future<Map<String, Object>> drain() async {
    _need(!_attempted, LabQuiescencePhase.repeated);
    _attempted = true;
    LabQuiescencePhase phase = LabQuiescencePhase.admission;
    try {
      _requireCurrent();
      _requireJournal();
      final Future<ReceiveDrainReceipt> receiving = worker.pauseAndDrain();
      final Future<OriginalPublicationDrain> fileDraining =
          OriginalPublications.pauseAndDrain(walletOwner);
      final Future<OriginalPublicationDrain> sdkDraining =
          OriginalPublications.pauseAndDrain(sdkOwner);
      phase = LabQuiescencePhase.drain;
      final ReceiveDrainReceipt received = await receiving;
      final OriginalPublicationDrain file = await fileDraining;
      final OriginalPublicationDrain sdk = await sdkDraining;
      phase = LabQuiescencePhase.current;
      _requireCurrent();
      _need(identical(file.owner, walletOwner) &&
          identical(sdk.owner, sdkOwner) && identical(received.owner, worker) &&
          worker.isPaused && !worker.running && !worker.hasPending, phase);
      phase = LabQuiescencePhase.publication;
      _need(file.completed && sdk.completed && _matchesSend() &&
          file.operations.length <= 512 && sdk.operations.length <= 128 &&
          file.operations.every(_positive) && sdk.operations.every(_positive),
          phase);
      final Set<OriginalPublication<dynamic>> sdkOriginals =
          Set<OriginalPublication<dynamic>>.identity()..addAll(sdk.operations);
      _need(sdkOriginals.length == sdk.operations.length &&
          sdkOriginals.contains(_original) &&
          sdk.operations.every((OriginalPublication<dynamic> value) =>
            file.operations.any((OriginalPublication<dynamic> held) =>
              identical(held, value))) &&
          file.operations.every((OriginalPublication<dynamic> value) =>
            sdkOriginals.contains(value) ||
            value.result == null && value.acceptedHash == null), phase);
      phase = LabQuiescencePhase.receive;
      final List<ReceiveRecord> records = worker.originals;
      _need(received.completed && received.reads.length <= 256 &&
          records.length <= 127 &&
          records.length == received.publications.length &&
          records.asMap().entries.every((MapEntry<int, ReceiveRecord> entry) =>
            identical(entry.value, received.publications[entry.key])) &&
          received.reads.every((ReceiveReadReceipt<dynamic> value) =>
            value.completed && value.error == null), phase);
      final Set<AccountBlockTemplate> blocks =
          Set<AccountBlockTemplate>.identity();
      final Set<String> hashes = <String>{};
      for (final OriginalPublication<dynamic> operation in sdk.operations) {
        final Object? value = operation.result;
        if (value is! AccountBlockTemplate) {
          throw LabQuiescenceRefused(phase);
        }
        final AccountBlockTemplate block = value;
        final String hash = block.hash.toString();
        _need(seedHash(hash) && operation.acceptedHash == hash &&
            block.chainIdentifier == 321 &&
            environment.members.contains(block.address.toString()) &&
            blocks.add(block) && hashes.add(hash), phase);
        if (identical(operation, _original)) {
          _need(identical(block, originalSend) && hash == _hash, phase);
        } else {
          _need(block.blockType == BlockTypeEnum.userReceive.index &&
              records.where((ReceiveRecord record) =>
                record.error == null && record.chainId == 321 &&
                record.toAddress == block.address.toString() &&
                record.inboundHash == block.fromBlockHash.toString() &&
                identical(record.result?.block, block)).length == 1, phase);
        }
      }
      _need(sdk.operations.length == records.length + 1, phase);
      final Set<String> receivedHashes = records.map(
        (ReceiveRecord value) => value.inboundHash,
      ).toSet();
      // The worker retains accepted inbound holds too. Only an unknown hold
      // refuses; an empty notifier is not substituted for the actual drain.
      _need(worker.inFlight.value.every(
        (Hash hash) => receivedHashes.contains(hash.toString())), phase);
      phase = LabQuiescencePhase.journal;
      _requireJournal();
      _requireCurrent();
      return Map<String, Object>.unmodifiable(<String, Object>{
        'schema': 1, 'scope': 'owned_lab_quiescence', 'chain': 321,
        'complete': true, 'admission_closed': true,
        'original_send_confirmed': true, 'originals_positive': true,
        'file_operations': file.operations.length,
        'sdk_publications': sdk.operations.length,
        'receive_reads': received.reads.length,
        'receive_publications': records.length,
      });
    } on LabQuiescenceRefused {
      rethrow;
    } on Object {
      throw LabQuiescenceRefused(phase);
    }
  }
}
