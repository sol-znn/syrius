import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/widgets/amount_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/cubit/send_draft_cubit.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/addresses_settings_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/addresses_settings_view.dart';

import 'support.dart';

class _ObservedDraft extends SendDraftCubit {
  VoidCallback? beforeChange;

  @override
  void onChange(Change<SendDraft> change) {
    beforeChange?.call();
    super.onChange(change);
  }
}

Future<void> _frames(WidgetTester tester, [int count = 12]) async {
  for (int frame = 0; frame < count; frame++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

void _viewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _host(
  AddressesFixture source,
  AddressesSettingsPresenter presenter,
  SendDraftCubit draft,
  VoidCallback onSend, {
  bool light = false,
  bool rtl = false,
  double scale = 1,
  bool hideBalances = false,
  bool disableAnimations = false,
}) => MaterialApp(
  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
  locale: const Locale('en'),
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(1280, 780),
      textScaler: TextScaler.linear(scale),
      disableAnimations: disableAnimations,
    ),
    child: Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: 1000,
            height: 650,
            child: AddressesSettingsView(
              presenter: presenter,
              draft: draft,
              isCurrent: source.captureView(),
              onSend: onSend,
              senderIsCurrent: () => true,
              hideBalances: hideBalances,
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  for (final (bool, bool, double, bool) variant in <(bool, bool, double, bool)>[
    (false, false, 1, false),
    (true, true, 1.5, true),
  ]) {
    testWidgets(
      'full-width tables, selected state and closed chain in $variant',
      (WidgetTester tester) async {
        _viewport(tester);
        final AddressesFixture source = AddressesFixture();
        await source.contacts.add(name: 'Alice', address: fixtureAddress(8));
        final AddressesSettingsPresenter presenter = AddressesSettingsPresenter(
          binding: source.bind(),
        );
        final SendDraftCubit draft = SendDraftCubit();
        await tester.pumpWidget(
          _host(
            source,
            presenter,
            draft,
            () {},
            light: variant.$1,
            rtl: variant.$2,
            scale: variant.$3,
            disableAnimations: variant.$4,
          ),
        );
        await _frames(tester);
        expect(find.text('Your addresses'), findsOneWidget);
        expect(find.text('Contacts'), findsOneWidget);
        expect(find.text('Selected'), findsOneWidget);
        expect(find.byType(AmountText), findsNWidgets(4));
        expect(
          find.byKey(const Key('addresses_account_chain_toggle')),
          findsOneWidget,
        );
        expect(find.text('3 blocks'), findsOneWidget);
        expect(find.byKey(const Key('addresses_label_field')), findsNothing);
        expect(
          tester
              .getSize(find.byKey(const Key('addresses_settings_page')))
              .width,
          1000,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await presenter.close();
        await draft.close();
      },
    );
  }

  testWidgets(
    'Send selects one exact committed contact and preserves the draft',
    (WidgetTester tester) async {
      _viewport(tester);
      final AddressesFixture source = AddressesFixture();
      final String address = fixtureAddress(8);
      await source.contacts.add(name: 'Alice', address: address);
      final AddressesSettingsPresenter presenter = AddressesSettingsPresenter(
        binding: source.bind(),
      );
      final SendDraftCubit draft = SendDraftCubit()
        ..save(
          fromAddress: source.members.last,
          tokenStandard: 'fixture-token',
          recipient: fixtureAddress(9),
          amount: '2.5',
        );
      int opened = 0;
      await tester.pumpWidget(_host(source, presenter, draft, () => opened++));
      await _frames(tester);
      final OutlinedButton action = tester.widget<OutlinedButton>(
        find.byKey(ValueKey<String>('addresses_send_$address')),
      );
      action.onPressed!();
      expect(draft.state.recipient, address);
      expect(draft.state.fromAddress, source.members.last);
      expect(draft.state.tokenStandard, 'fixture-token');
      expect(draft.state.amount, '2.5');
      expect(opened, 1);
      action.onPressed!();
      expect(opened, 1);
      expect(source.contacts.lastSent(address), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await presenter.close();
      await draft.close();
    },
  );

  testWidgets('a draft observer can revoke the source before Send navigation', (
    WidgetTester tester,
  ) async {
    _viewport(tester);
    final AddressesFixture source = AddressesFixture();
    final String address = fixtureAddress(8);
    await source.contacts.add(name: 'Alice', address: address);
    final AddressesSettingsPresenter presenter = AddressesSettingsPresenter(
      binding: source.bind(),
    );
    final _ObservedDraft draft = _ObservedDraft();
    int opened = 0;
    await tester.pumpWidget(_host(source, presenter, draft, () => opened++));
    await _frames(tester);
    draft.beforeChange = () => source.visible = false;
    tester
        .widget<OutlinedButton>(
          find.byKey(ValueKey<String>('addresses_send_$address')),
        )
        .onPressed!();
    expect(draft.state.recipient, address);
    expect(opened, 0);
    expect(source.contacts.lastSent(address), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await presenter.close();
    await draft.close();
  });

  testWidgets(
    'retained contact callbacks refuse replacement and leave-return',
    (WidgetTester tester) async {
      _viewport(tester);
      final AddressesFixture source = AddressesFixture();
      final String address = fixtureAddress(8);
      await source.contacts.add(name: 'Alice', address: address);
      final AddressesSettingsPresenter presenter = AddressesSettingsPresenter(
        binding: source.bind(),
      );
      final SendDraftCubit draft = SendDraftCubit();
      int opened = 0;
      await tester.pumpWidget(_host(source, presenter, draft, () => opened++));
      await _frames(tester);
      final VoidCallback retained = tester
          .widget<OutlinedButton>(
            find.byKey(ValueKey<String>('addresses_send_$address')),
          )
          .onPressed!;
      await source.contacts.rename(address, 'Alicia');
      retained();
      expect(draft.state.isEmpty, isTrue);
      expect(opened, 0);
      source.leaveAndReturn();
      retained();
      expect(opened, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await presenter.close();
      await draft.close();
    },
  );

  testWidgets(
    'closed editor preserves its original late failure without paint',
    (WidgetTester tester) async {
      _viewport(tester);
      final AddressesFixture source = AddressesFixture()..delayLabels = true;
      final AddressesSettingsBinding binding = source.bind();
      final AddressesSettingsPresenter presenter = AddressesSettingsPresenter(
        binding: binding,
      );
      final SendDraftCubit draft = SendDraftCubit();
      await tester.pumpWidget(_host(source, presenter, draft, () {}));
      await _frames(tester);
      final Finder rename = find.byKey(
        ValueKey<String>('addresses_rename_${source.members.first}'),
      );
      expect(binding.ownsResources, isTrue);
      expect(binding.busy, isFalse);
      expect(tester.widget<IconButton>(rename).onPressed, isNotNull);
      expect(rename.hitTestable(), findsOneWidget);
      await tester.tap(rename);
      await _frames(tester);
      await tester.enterText(
        find.byKey(const Key('addresses_label_field')),
        'Savings',
      );
      await tester.tap(find.byKey(const Key('addresses_save_label')));
      await _frames(tester, 2);
      expect(source.labelWrites, hasLength(1));
      expect(binding.labels[source.members.first], 'Address 1');
      await tester.pumpWidget(const SizedBox.shrink());
      await presenter.close();
      final StateError original = StateError('late label failure');
      source.labelWrites.single.$3.completeError(original);
      await _frames(tester, 2);
      expect(binding.outcomes.single.error, same(original));
      expect(binding.labels[source.members.first], 'Address 1');
      expect(tester.takeException(), isNull);
      await draft.close();
    },
  );

  testWidgets('hidden balances contain no AmountText values', (
    WidgetTester tester,
  ) async {
    _viewport(tester);
    final AddressesFixture source = AddressesFixture();
    final AddressesSettingsPresenter presenter = AddressesSettingsPresenter(
      binding: source.bind(),
    );
    final SendDraftCubit draft = SendDraftCubit();
    await tester.pumpWidget(
      _host(source, presenter, draft, () {}, hideBalances: true),
    );
    await _frames(tester);
    expect(find.byType(AmountText), findsNothing);
    expect(find.text('••••'), findsNWidgets(4));
    await tester.pumpWidget(const SizedBox.shrink());
    await presenter.close();
    await draft.close();
  });
}
