import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Adapts existing owner forms to the shared sender and their original account.
class NodeOwnerPublisher extends AccountBlockUtils {
  /// [verifyOwner] performs a fresh ownership read before each explicit action.
  NodeOwnerPublisher({
    required this.sender,
    required this.context,
    required this.verifyOwner,
    this.isCurrent,
  });

  /// Shared with Transfer and collection so two surfaces cannot overlap.
  final SendTransactionBloc sender;

  /// Captured before any question or form yields.
  final WalletActionContext context;

  /// Never trusts a cached owner record as publication authority.
  final Future<bool> Function() verifyOwner;

  /// The original form and completed read can revoke preparation before send.
  final bool Function()? isCurrent;

  bool get _current => context.isCurrent && (isCurrent?.call() ?? true);

  void _requireCurrent() {
    if (!_current) {
      throw FailureException(message: currentL10n.publicationSessionChanged);
    }
  }

  /// The original result survives form disposal and optional UI failures.
  SendRequestResult? lastResult;

  @override
  Future<AccountBlockTemplate> createAccountBlock(
    AccountBlockTemplate transactionParams,
    String purposeOfGeneratingPlasma, {
    Address? address,
    bool waitForRequiredPlasma = false,
    bool Function()? canPublish,
  }) async {
    // No busy, validity or diagnostic callback may rewrite the original action.
    final AccountBlockTemplate block = AccountBlockTemplate.fromJson(
      transactionParams.toJson(),
    );
    _requireCurrent();
    if (address != null && address.toString() != context.ownerAddress) {
      throw FailureException(message: currentL10n.publicationSessionChanged);
    }
    final Object owner = Object();
    if (!sender.tryReserve(owner)) throw FailureException();
    try {
      final bool verified = await verifyOwner();
      _requireCurrent();
      if (!verified) {
        throw FailureException(message: currentL10n.publicationSessionChanged);
      }
      final SendRequestHandle? request = sender.trySubmitOwned(
        owner: owner,
        requestId: Object(),
        block: block,
        fromAddress: context.ownerAddress,
        reasonForGeneratingPlasma: purposeOfGeneratingPlasma,
        origin: SendTransactionOrigin.contract,
        canStart: () => _current && (canPublish?.call() ?? true),
        canPublish: () => _current && (canPublish?.call() ?? true),
      );
      if (request == null) throw FailureException();
      final SendRequestResult result = await request.result;
      lastResult = result;
      if (result.accepted) return result.block!;
      final Object? error = result.error;
      throw error is SyriusException ? error : FailureException();
    } finally {
      // A running original keeps its reservation until its own result settles.
      sender.releaseReservation(owner);
    }
  }
}
