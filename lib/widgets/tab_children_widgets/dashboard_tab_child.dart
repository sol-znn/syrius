import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/cubit/home_collection_controller.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/transfer/view/transfer_page.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/widgets.dart';

/// The Home tab. Since the refresh it is the balance-first home of mockup B
/// ([HomeView]); the grid of network statistics cards it used to hold is gone
/// from here, and those figures belong to the pages they describe.
class DashboardTabChild extends StatelessWidget {
  /// Creates Home with the shell's navigation callbacks.
  const DashboardTabChild({
    super.key,
    this.changePage,
    this.openTransfer,
    this.collectionOwner,
    this.collectionSession,
  });

  /// Moves to another existing wallet page.
  final void Function(Tabs)? changePage;

  /// Selects the existing session mode before moving to Transfer.
  final ValueChanged<TransferMode>? openTransfer;

  /// The shell retains collection outcomes when Home is unmounted.
  final HomeCollectionController? Function()? collectionOwner;

  /// Captures the original wallet context for an explicit batch or read.
  final HomeCollectionSession? Function()? collectionSession;

  @override
  Widget build(BuildContext context) {
    return HomeView(
      changePage: changePage ?? (_) {},
      openTransfer: openTransfer,
      collectionOwner: collectionOwner,
      collectionSession: collectionSession,
    );
  }
}
