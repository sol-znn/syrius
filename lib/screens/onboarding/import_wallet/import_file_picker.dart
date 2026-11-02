import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/entry_action_boundary.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/import_wallet/import_draft.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/import_wallet/import_file_offer.dart';

/// Adds the genuine file-drop adapter around the import presentation.
typedef ImportDropWrapper = Widget Function(Widget);

/// Entry owners mount this adapter only with their genuine current lease.
class ImportFilePicker extends StatelessWidget {
  /// Mounts platform picker and drop capabilities for the current import lease.
  const ImportFilePicker({
    required this.lease,
    required this.probe,
    required this.onSelected,
    required this.onPickerFailed,
    required this.builder,
    super.key,
  });

  /// The original route generation that may accept a picker or drop result.
  final EntryActionLease lease;

  /// The bounded content check; names and extensions confer no admission.
  final bool Function(String) probe;

  /// Receives the current admitted selection, or null when a drop is refused.
  final ValueChanged<ImportFileSelection?> onSelected;

  /// Maps picker failures to localized presentation without exception text.
  final VoidCallback onPickerFailed;

  /// Builds the view with its guarded browse action and file-drop wrapper.
  final Widget Function(BuildContext, VoidCallback, ImportDropWrapper) builder;

  @override
  Widget build(BuildContext context) {
    final ImportFileOfferSession session = ImportFileOfferSession(
      isCurrent: () => lease.isCurrent,
      probe: probe,
      onSelected: onSelected,
      onPickerFailed: onPickerFailed,
      pick: () async {
        // No extension or initial-directory filter. The bounded probe alone
        // decides content admission after the original picker completes.
        final XFile? selected = await openFile();
        return selected?.path;
      },
    );
    Widget wrap(Widget child) => DropTarget(
      onDragDone: (DropDoneDetails details) {
        if (details.files.length == 1) {
          session.offer(details.files.single.path);
        } else {
          session.refuse();
        }
      },
      child: child,
    );
    return builder(context, () {
      unawaited(session.browse());
    }, wrap);
  }
}
