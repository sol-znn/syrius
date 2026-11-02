import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/receive/receive_header_controller.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The receive request of the Transfer page: a QR code for an address, an
/// asset and an amount.
class ReceiveCard extends StatelessWidget {
  /// Creates a new instance.
  const ReceiveCard({
    this.embedded = false,
    this.headerController,
    this.isCurrent,
    super.key,
  });

  /// Omits the standalone panel when Transfer supplies the shared card.
  final bool embedded;

  /// Transfer's optional compact picker. Standalone forms keep their picker.
  final ReceiveHeaderController? headerController;

  /// Whether the embedding Transfer mode still belongs to this form.
  final bool Function()? isCurrent;

  @override
  Widget build(BuildContext context) {
    final Widget body = BlocBuilder<AllTokensBloc, AllTokensState>(
      builder: (_, AllTokensState state) => switch (state) {
        AllTokensFailure(:final SyriusException exception) => ReceiveError(
          error: exception,
        ),
        AllTokensInitial() => const ReceiveInitial(),
        AllTokensPopulated(:final List<Token> data) => ReceivePopulated(
          key: const Key('receive_form_ready'),
          assets: data,
          headerController: headerController,
          isCurrent: isCurrent,
        ),
      },
    );
    if (embedded) return body;
    return Panel(
      title: context.l10n.receive,
      actions: <Widget>[
        RefreshButton(
          onPressed: () {
            context.read<AllTokensBloc>().add(const AllTokensRequested());
          },
        ),
      ],
      child: body,
    );
  }
}
