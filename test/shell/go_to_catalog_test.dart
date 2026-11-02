import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/go_to_palette.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/services/contacts_store.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/go_to_catalog.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/tabs.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

void main() {
  testWidgets(
    'catalog keeps complete addresses and distinct ownership actions',
    (
      WidgetTester tester,
    ) async {
      final String own = Address(
        Address.prefix,
        List<int>.generate(20, (int i) => i == 0 ? 0 : 1),
      ).toString();
      final String other = Address(
        Address.prefix,
        List<int>.generate(20, (int i) => i == 0 ? 0 : 2),
      ).toString();
      late List<GoToEntry<ShellGoToTarget>> entries;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: const <Locale>[Locale('en')],
          home: Builder(
            builder: (BuildContext context) {
              entries = buildShellGoToCatalog(
                context: context,
                chordName: 'Cmd',
                addresses: <String>[own, own, 'invalid'],
                labels: <String, String>{own: 'Primary'},
                contacts: <Contact>[
                  Contact(
                    name: 'Test contact',
                    address: other,
                    added: DateTime(2026),
                  ),
                  Contact(
                    name: 'Duplicate',
                    address: other,
                    added: DateTime(2026),
                  ),
                  Contact(
                    name: 'Invalid',
                    address: 'z1short',
                    added: DateTime(2026),
                  ),
                ],
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final List<GoToEntry<ShellGoToTarget>> addresses = entries
          .where(
            (GoToEntry<ShellGoToTarget> e) =>
                e.category == GoToCategory.addresses,
          )
          .toList();
      expect(addresses, hasLength(2));
      expect(addresses.first.label, 'Primary');
      expect(addresses.first.value.kind, ShellGoToKind.ownAddress);
      expect(addresses.first.identifier, own);
      expect(addresses.first.value.address, own);
      expect(addresses.last.label, 'Test contact');
      expect(addresses.last.value.kind, ShellGoToKind.contact);
      expect(addresses.last.value.address, other);
      expect(addresses.last.identifier, other);
      expect(addresses.last.detail, 'Send to');
      final GoToEntry<ShellGoToTarget> delegation = entries.singleWhere(
        (GoToEntry<ShellGoToTarget> e) => e.id == 'page:delegation',
      );
      expect(delegation.label, 'Delegation');
      expect(delegation.value.page, Tabs.pillars);
      expect(delegation.shortcut, 'Cmd 4');
      expect(
        entries.map((GoToEntry<ShellGoToTarget> e) => e.id).toSet(),
        hasLength(entries.length),
      );
      final GoToEntry<ShellGoToTarget> zap = entries.singleWhere(
        (GoToEntry<ShellGoToTarget> e) => e.value.kind == ShellGoToKind.zap,
      );
      int submitted = 0;
      expect(zap.seam, Seam.zapSend);
      expect(zap.value.seam, Seam.zapSend);
      expect(
        runUnlessSeamed(seam: zap.value.seam, action: () => submitted++),
        false,
      );
      expect(submitted, 0);
    },
  );
}
