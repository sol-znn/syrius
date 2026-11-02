import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/model/account_chain_stats.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_change.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/account_chain_stats.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

class _Stats extends Mock implements AccountChainStatsBloc {}

void main() {
  for (final int? sourceChain in <int?>[null, 1, 321]) {
    testWidgets(
      'explorer needs matching observed mainnet blocks, source $sourceChain',
      (
        WidgetTester tester,
      ) async {
        final int? previousChain = kNodeChainId;
        addTearDown(() => kNodeChainId = previousChain);
        kNodeChainId = 1;
        final _Stats bloc = _Stats();
        final AccountChainStats stats = AccountChainStats(
          firstHash: Hash.parse(List<String>.filled(64, 'a').join()),
          chainIdentifier: sourceChain,
          blockCount: 1,
          blockTypeNumOfBlocksMap: <BlockTypeEnum, int>{
            for (final BlockTypeEnum type in BlockTypeEnum.values)
              type: type == BlockTypeEnum.userSend ? 1 : 0,
          },
        );
        when(
          () => bloc.stream,
        ).thenAnswer((_) => Stream<AccountChainStats>.value(stats));
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: const <Locale>[Locale('en')],
            home: Scaffold(
              body: AccountChainStatsWidget(accountChainStatsBloc: bloc),
            ),
          ),
        );
        await tester.pumpAndSettle();
        IconButton explorer() => tester.widget<IconButton>(
          find.byWidgetPredicate(
            (Widget widget) =>
                widget is IconButton && widget.tooltip == 'Open in explorer',
          ),
        );
        expect(explorer().onPressed != null, sourceChain == 1);
        kNodeChainId = 321;
        NodeChange.announce();
        await tester.pumpAndSettle();
        expect(explorer().onPressed, isNull);
        kNodeChainId = null;
        NodeChange.announce();
        await tester.pumpAndSettle();
        expect(explorer().onPressed, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
