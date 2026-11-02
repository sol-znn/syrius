import 'package:zenon_syrius_wallet_flutter/utils/original_publications.dart';

/// A native observation cannot retain its sealed original owners.
class ReadonlySdkAdmissionRefused implements Exception {
  /// The original observation stays terminally refused.
  const ReadonlySdkAdmissionRefused();
}

/// Seals the original SDK before a fresh native profile receives private input.
/// The caller must bind actual SDK, service and preference-box identities.
class ReadonlySdkAdmission {
  ReadonlySdkAdmission._(
    this._sdkOwner,
    this._ownersCurrent,
    this._automaticDisabled,
  );

  static final Expando<bool> _reserved = Expando<bool>();

  final Object _sdkOwner;
  final bool Function() _ownersCurrent;
  final bool Function() _automaticDisabled;
  bool _ready = false;
  bool _revoked = false;

  /// Pauses admission synchronously before the first preference-write await.
  /// Existing originals are refused, never canceled, retried or relabeled.
  static Future<ReadonlySdkAdmission> seal({
    required Object sdkOwner,
    required bool Function() ownersCurrent,
    required bool Function() automaticDisabled,
    required Future<void> Function() disableAutomatic,
  }) async {
    if (_reserved[sdkOwner] == true) {
      throw const ReadonlySdkAdmissionRefused();
    }
    _reserved[sdkOwner] = true;
    final ReadonlySdkAdmission admission = ReadonlySdkAdmission._(
      sdkOwner,
      ownersCurrent,
      automaticDisabled,
    );
    try {
      admission._requireOwners();
      final Future<OriginalPublicationDrain> original =
          OriginalPublications.pauseAndDrain(sdkOwner);
      admission._requireOwners();
      final OriginalPublicationDrain receipt = await original;
      admission._requireOwners();
      if (!identical(receipt.owner, sdkOwner) ||
          !receipt.completed ||
          receipt.operations.isNotEmpty) {
        admission._refuse();
      }
      await disableAutomatic();
      admission
        .._requireOwners()
        .._ready = true
        ..requireCurrent();
      return admission;
    } on Object {
      admission._revoked = true;
      rethrow;
    }
  }

  /// Checks the retained original owners before and after every native action.
  /// Owner replacement, a refused SDK attempt or automatic enablement is final.
  void requireCurrent() {
    if (!_ready) _refuse();
    _requireOwners();
    try {
      if (!_automaticDisabled()) _refuse();
      _requireOwners();
    } on Object {
      _revoked = true;
      rethrow;
    }
  }

  void _requireOwners() {
    if (_revoked) throw const ReadonlySdkAdmissionRefused();
    try {
      if (!_ownersCurrent() ||
          OriginalPublications.snapshot(_sdkOwner).isNotEmpty ||
          OriginalPublications.hasRefusedAdmission(_sdkOwner)) {
        _refuse();
      }
    } on Object {
      _revoked = true;
      rethrow;
    }
  }

  Never _refuse() {
    _revoked = true;
    throw const ReadonlySdkAdmissionRefused();
  }
}
