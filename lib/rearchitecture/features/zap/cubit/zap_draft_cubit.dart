import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Why an entered native-coin amount cannot be used as an exact amount.
enum ZapAmountIssue {
  /// No amount has been entered.
  empty,

  /// The text is not a nonnegative, plain decimal in Latin digits.
  invalid,

  /// A native coin has eight decimal places, and this text has more.
  precision,

  /// The amount exceeds the SDK's existing token-supply bound.
  range,
}

typedef _ParsedAmount = ({BigInt? units, ZapAmountIssue? issue});

/// A local Zap composition, separate from recipient discovery and sending.
///
/// The text is retained as typed. In particular, a refused amount is never
/// rounded or changed into a different amount that could later be sent.
class ZapDraft extends Equatable {
  /// Starts with the mockup's coin amounts and the localized default message.
  const ZapDraft({this.znn = '1', this.qsr = '10', this.message});

  /// Both native coins have this protocol precision.
  static const int decimals = 8;

  /// The limit is on UTF-8 bytes, not characters or grapheme clusters.
  static const int messageLimit = 140;

  /// The SDK's kBigP255m1 token-supply bound, kept without an SDK dependency.
  static final BigInt maximumBaseUnits = (BigInt.one << 255) - BigInt.one;

  /// The ZNN amount, as entered.
  final String znn;

  /// The QSR amount, as entered. Zero omits this coin from a future Zap.
  final String qsr;

  /// Null selects the localized default; an empty string is an empty message.
  final String? message;

  /// Whether the ZNN text needs correction.
  ZapAmountIssue? get znnIssue => _parse(znn).issue;

  /// Whether the QSR text needs correction.
  ZapAmountIssue? get qsrIssue => _parse(qsr).issue;

  /// The exact ZNN amount, or null while its text cannot be used.
  BigInt? get znnBaseUnits => _parse(znn).units;

  /// The exact QSR amount, or null while its text cannot be used.
  BigInt? get qsrBaseUnits => _parse(qsr).units;

  /// Planned blocks from valid amounts, including zero when both are zero.
  ///
  /// This is a composition fact, never a count of submitted or confirmed
  /// blocks. Invalid text has no count.
  int? get blockCount {
    final BigInt? znnAmount = znnBaseUnits;
    final BigInt? qsrAmount = qsrBaseUnits;
    if (znnAmount == null || qsrAmount == null) {
      return null;
    }
    return (znnAmount > BigInt.zero ? 1 : 0) +
        (qsrAmount > BigInt.zero ? 1 : 0);
  }

  /// How many bytes the message in this locale would carry.
  int messageBytes(String defaultMessage) =>
      utf8.encode(message ?? defaultMessage).length;

  /// Whether the composition has exact amounts and a message within the limit.
  ///
  /// A valid draft still has no recipient or permission to send. The Zap
  /// service remains behind its missing-feature seam.
  bool isValid(String defaultMessage) =>
      (blockCount ?? 0) > 0 && messageBytes(defaultMessage) <= messageLimit;

  static final RegExp _decimal = RegExp(
    r'^(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$',
  );

  static _ParsedAmount _parse(String value) {
    if (value.isEmpty) {
      return (units: null, issue: ZapAmountIssue.empty);
    }
    final int point = value.indexOf('.');
    final int wholeEnd = point < 0 ? value.length : point;
    int wholeStart = 0;
    while (wholeStart < wholeEnd && value.codeUnitAt(wholeStart) == 48) {
      wholeStart++;
    }
    // Discard leading zeros and reject obvious overflow before regex or
    // integer parsing. Even a very long paste produces no oversized BigInt.
    if (wholeEnd - wholeStart > maximumBaseUnits.toString().length - decimals) {
      return (units: null, issue: ZapAmountIssue.range);
    }
    final Match? match = _decimal.matchAsPrefix(value);
    if (match == null || match.end != value.length) {
      return (units: null, issue: ZapAmountIssue.invalid);
    }
    if (point >= 0 && value.length - point - 1 > decimals) {
      return (units: null, issue: ZapAmountIssue.precision);
    }
    final String whole = value.substring(wholeStart, wholeEnd);
    final String fraction = point < 0 ? '' : value.substring(point + 1);
    // The existing general conversion truncates excess decimals. Validate
    // first and build base units directly so a draft can never lose money.
    final BigInt units = BigInt.parse(
      '${whole.isEmpty ? '0' : whole}${fraction.padRight(decimals, '0')}',
    );
    return units > maximumBaseUnits
        ? (units: null, issue: ZapAmountIssue.range)
        : (units: units, issue: null);
  }

  @override
  List<Object?> get props => <Object?>[znn, qsr, message];
}

/// Retains a composition in memory for the current unlocked wallet session.
///
/// The shell owns this cubit, clears it on lock and closes it at teardown.
/// It has no recipient, wallet, storage, SDK or network dependency.
class ZapDraftCubit extends Cubit<ZapDraft> {
  /// Creates a composition holder, optionally with already retained text.
  ZapDraftCubit({ZapDraft initial = const ZapDraft()}) : super(initial);

  /// Records the fields without normalizing, publishing or clearing them.
  void save({
    required String znn,
    required String qsr,
    required String message,
  }) => emit(ZapDraft(znn: znn, qsr: qsr, message: message));

  /// Restores the defaults, including resolving the message from localization.
  void clear() => emit(const ZapDraft());
}
