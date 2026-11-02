import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/go_to_palette.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/services/contacts_store.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/rail.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/tabs.dart';

/// The existing flows offered by the shell's palette.
enum ShellGoToKind {
  /// A rail destination.
  page,

  /// The Send mode, without submitting.
  send,

  /// The Receive mode.
  receive,

  /// The drawn but unavailable Zap mode.
  zap,

  /// The current Nodes scope's delegation chooser.
  delegation,

  /// The cache deletion confirmation.
  deleteCache,

  /// An exact owned address to select.
  ownAddress,

  /// An exact contact to prefill in Send.
  contact,
}

/// Typed navigation data. The shell revalidates ownership at dispatch time.
class ShellGoToTarget {
  /// A page destination.
  const ShellGoToTarget.page(this.page)
    : kind = ShellGoToKind.page,
      address = null;

  /// An existing form or guarded missing action.
  const ShellGoToTarget.action(this.kind) : page = null, address = null;

  /// An exact complete address, never a displayed abbreviation.
  const ShellGoToTarget.address(this.kind, this.address) : page = null;

  /// Which existing flow to open.
  final ShellGoToKind kind;

  /// The rail destination, when applicable.
  final Tabs? page;

  /// The complete selected address, when applicable.
  final String? address;

  /// Indirect callers refuse the same missing service as pointer controls.
  Seam? get seam => kind == ShellGoToKind.zap ? Seam.zapSend : null;
}

/// Builds a snapshot without opening a service, resolving a name or sending.
List<GoToEntry<ShellGoToTarget>> buildShellGoToCatalog({
  required BuildContext context,
  required String chordName,
  required Iterable<String> addresses,
  required Map<String, String> labels,
  required Iterable<Contact> contacts,
}) {
  final List<GoToEntry<ShellGoToTarget>> entries = <GoToEntry<ShellGoToTarget>>[
    for (int i = 0; i < kRailPages.length; i++)
      GoToEntry<ShellGoToTarget>(
        id: 'page:${kRailPages[i].tab.name}',
        value: ShellGoToTarget.page(kRailPages[i].tab),
        label: kRailPages[i].localizedLabel(context),
        iconBuilder: (BuildContext context, Color color) =>
            kRailPages[i].buildIcon(context, color: color),
        shortcut: '$chordName ${i + 1}',
      ),
    for (final RailEntry entry in railWalletEntries(onLock: false))
      GoToEntry<ShellGoToTarget>(
        id: 'page:${entry.tab.name}',
        value: ShellGoToTarget.page(entry.tab),
        label: entry.localizedLabel(context),
        iconBuilder: (BuildContext context, Color color) =>
            entry.buildIcon(context, color: color),
        shortcut: entry.tab == Tabs.lock ? '$chordName L' : null,
      ),
    GoToEntry<ShellGoToTarget>(
      id: 'page:delegation',
      value: const ShellGoToTarget.page(Tabs.pillars),
      label: context.l10n.goToPaletteDelegate,
      detail: context.l10n.railNodes,
      iconBuilder: (BuildContext context, Color color) =>
          buildShellSymbol(context, 'stack', color: color),
      shortcut: '$chordName 4',
    ),
  ];
  void action(
    ShellGoToKind kind,
    String label,
    String symbol, {
    String? detail,
  }) {
    final ShellGoToTarget target = ShellGoToTarget.action(kind);
    entries.add(
      GoToEntry<ShellGoToTarget>(
        id: 'action:${kind.name}',
        value: target,
        label: label,
        category: GoToCategory.actions,
        detail: detail,
        seam: target.seam,
        iconBuilder: (BuildContext context, Color color) =>
            buildShellSymbol(context, symbol, color: color),
      ),
    );
  }

  action(ShellGoToKind.send, context.l10n.send, 'up');
  action(ShellGoToKind.receive, context.l10n.receive, 'down');
  action(ShellGoToKind.zap, context.l10n.transferZap, 'zap');
  action(
    ShellGoToKind.delegation,
    context.l10n.goToPaletteDelegateAction,
    'stack',
  );
  action(
    ShellGoToKind.deleteCache,
    context.l10n.goToPaletteDeleteCache,
    'trash',
    detail: context.l10n.railSettings,
  );
  int index = 0;
  final Set<String> own = <String>{};
  for (final String candidate in addresses) {
    index++;
    final String? address = ContactsStore.normalize(candidate);
    if (address == null || !own.add(address)) continue;
    entries.add(
      GoToEntry<ShellGoToTarget>(
        id: 'own:$address',
        value: ShellGoToTarget.address(ShellGoToKind.ownAddress, address),
        category: GoToCategory.addresses,
        label: labels[candidate] ?? context.l10n.addressDefaultLabel(index),
        identifier: address,
        iconBuilder: (BuildContext context, Color color) =>
            buildShellSymbol(context, 'book', color: color),
      ),
    );
  }
  final Set<String> book = <String>{};
  for (final Contact contact in contacts) {
    final String? address = ContactsStore.normalize(contact.address);
    if (address == null || !book.add(address)) continue;
    entries.add(
      GoToEntry<ShellGoToTarget>(
        id: 'contact:$address',
        value: ShellGoToTarget.address(ShellGoToKind.contact, address),
        category: GoToCategory.addresses,
        label: contact.name,
        identifier: address,
        detail: context.l10n.goToPaletteSendToHint,
        searchTerms: <String>[context.l10n.goToPaletteSendTo(contact.name)],
        iconBuilder: (BuildContext context, Color color) =>
            buildShellSymbol(context, 'book', color: color),
      ),
    );
  }
  return entries;
}
