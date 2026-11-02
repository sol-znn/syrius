import 'package:flutter_vector_icons/flutter_vector_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_colors.dart';

/// A retained wallet event with optional producer-supplied chain metadata.
class WalletNotification {
  /// Creates an event while retaining nullable fields from legacy storage.
  WalletNotification({
    required this.title,
    required this.timestamp,
    required this.details,
    required this.type,
    this.id,
    this.eventKind,
    this.walletScope,
    this.chainId,
    this.transactionHash,
  });

  /// The event's display title, if the original producer supplied one.
  final String? title;

  /// The original event time in milliseconds since the Unix epoch.
  final int? timestamp;

  /// The original event details, without inferred identifiers.
  final String? details;

  /// The producer-selected display category.
  final NotificationType? type;

  /// The legacy producer identifier, separate from the storage key.
  final int? id;

  /// Explicit producer identity. Legacy text is never parsed to infer a kind.
  final String? eventKind;

  /// The stable chain and wallet anchor, independent of address selection.
  final String? walletScope;

  /// The original event's chain, when the producer knows it.
  final int? chainId;

  /// The exact originally published hash, when supplied by the producer.
  final String? transactionHash;

  /// Returns the category colour used by legacy notification surfaces.
  Color getColor() {
    switch (type) {
      case NotificationType.error:
        return AppColors.errorColor;
      case NotificationType.stakingDeactivated:
        return AppColors.alertNotification;
      default:
        return AppColors.znnColor;
    }
  }

  /// Returns the category icon used by legacy notification surfaces.
  Widget getIcon() {
    switch (type) {
      case NotificationType.stakingDeactivated:
        return _getCircledIcon(
          MaterialCommunityIcons.alert_circle_outline,
          iconColor: Colors.grey,
        );
      case NotificationType.error:
        return const Icon(
          MaterialCommunityIcons.alert_circle_outline,
          size: 20,
          color: AppColors.errorColor,
        );
      case NotificationType.paymentSent:
        return _getCircledIcon(MaterialCommunityIcons.arrow_top_right);
      case NotificationType.paymentReceived:
        return _getCircledIcon(MaterialCommunityIcons.arrow_bottom_right);
      case NotificationType.rewardReceived:
        return _getCircledIcon(MaterialCommunityIcons.arrow_bottom_left);
      case NotificationType.autoLockIntervalChanged:
        return _getCircledIcon(Icons.lock_clock);
      case NotificationType.copiedToClipboard:
        return _getCircledIcon(Icons.content_copy);
      case NotificationType.autoEraseNumAttemptsChanged:
        return _getCircledIcon(Icons.delete);
      case NotificationType.generatingPlasma:
        return _getCircledIcon(Icons.access_time, iconColor: Colors.orange);
      case NotificationType.burnToken:
        return _getCircledIcon(Icons.whatshot);
      case NotificationType.addedTokenFavourite:
        return _getCircledIcon(Icons.star_rounded);
      case NotificationType.removedTokenFavourite:
        return _getCircledIcon(Icons.star_border_rounded);
      case NotificationType.changedNode:
        return _getCircledIcon(Icons.link);
      case NotificationType.delete:
        return _getCircledIcon(Icons.delete_forever);
      case NotificationType.confirm:
        return _getCircledIcon(
          Icons.remove_red_eye,
          iconColor: AppColors.alertNotification,
        );
      default:
        return _getCircledIcon(MaterialCommunityIcons.arrow_top_right);
    }
  }

  Widget _getCircledIcon(
    IconData iconData, {
    Color iconColor = AppColors.znnColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        border: Border.all(
          color: iconColor,
        ),
        borderRadius: BorderRadius.circular(
          50,
        ),
      ),
      child: Icon(
        iconData,
        color: iconColor,
        size: 10,
      ),
    );
  }
}
