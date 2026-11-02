import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/onboarding_scaffold.dart';
import 'package:zenon_syrius_wallet_flutter/screens/screens.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/widgets.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Shows a new seed without changing stored wallet membership.
class NewWalletSeedChoiceScreen extends StatefulWidget {
  /// Ordinary entry returns to the previous route when Back is selected.
  const NewWalletSeedChoiceScreen({super.key, this.export = false});

  /// Export entry returns to the existing access route after backing out.
  final bool export;

  @override
  State<NewWalletSeedChoiceScreen> createState() =>
      _NewWalletSeedChoiceScreenState();
}

class _NewWalletSeedChoiceScreenState extends State<NewWalletSeedChoiceScreen> {
  bool _isSeed12Selected = false;
  bool? _isSeedSecure = false;
  bool? _isSeedWrittenDown = false;

  late List<String> _generatedSeed24;
  late List<String> _generatedSeed12;

  final GlobalKey<SeedGridState> _seedGridKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _generatedSeed24 = Mnemonic.generateMnemonic(256).split(' ');
    _generatedSeed12 = Mnemonic.generateMnemonic(128).split(' ');
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      step: 1,
      title: _isSeed12Selected ? 'Your 12 word seed' : 'Your 24 word seed',
      subtitle: 'Write it down and export it to a safe place',
      help: 'Hover a word to read it. Click its number to keep it shown.',
      onBack: _onBackPressed,
      maxWidth: 880,
      primary: _buildContinueButton(),
      child: Column(
        children: <Widget>[
          // The choice goes once the seed is said to be backed up: changing
          // it then would show a seed that was never written down.
          SizedBox(
            height: 40,
            child: Visibility(
              visible: !_isSeedSecure!,
              child: _getSeedChoice(),
            ),
          ),
          const SizedBox(height: 16),
          _getSeedGrid(),
          const SizedBox(height: 16),
          SizedBox(
            height: 40,
            child: Visibility(
              visible: !_isSeedSecure!,
              child: _getBackUpSeedContainer(),
            ),
          ),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _getConfirmSecureCheckboxContainer(),
              _getConfirmWrittenDownCheckbox(),
            ],
          ),
        ],
      ),
    );
  }

  void _onBackPressed() {
    if (widget.export) {
      Navigator.popUntil(
        context,
        ModalRoute.withName(AccessWalletScreen.route),
      );
    } else {
      Navigator.pop(context);
    }
  }

  SeedGrid _getSeedGrid() {
    return SeedGrid(
      _isSeed12Selected ? _generatedSeed12 : _generatedSeed24,
      enableSeedInputFields: false,
      key: _seedGridKey,
    );
  }

  Widget _getSeedChoice() {
    return SeedChoice(
      isSeed12Selected: _isSeed12Selected,
      onSeed24Selected: () {
        setState(
          () {
            _isSeedWrittenDown = false;
            _isSeed12Selected = false;
            _seedGridKey.currentState!.changedSeed(
              _isSeed12Selected ? _generatedSeed12 : _generatedSeed24,
            );
          },
        );
      },
      onSeed12Selected: () {
        setState(() {
          _isSeedWrittenDown = false;
          _isSeed12Selected = true;
          _seedGridKey.currentState!.changedSeed(
            _isSeed12Selected ? _generatedSeed12 : _generatedSeed24,
          );
        });
      },
    );
  }

  Widget _getBackUpSeedContainer() {
    return Consumer<ValueNotifier<List<String>>>(
      builder: (_, ValueNotifier<List<String>> exportedSeed, _) {
        final bool exported = _isSeedExported(exportedSeed.value);
        return OutlinedButton.icon(
          style: secondaryButtonStyle(context).copyWith(
            side: exported
                ? const WidgetStatePropertyAll<BorderSide>(
                    BorderSide(color: AppColors.znnColor),
                  )
                : null,
          ),
          onPressed: () {
            if (_isSeed12Selected) {
              NavigationUtils.push(
                context,
                ExportWalletInfoScreen(
                  _generatedSeed12.join(' '),
                ),
              );
            } else {
              NavigationUtils.push(
                context,
                ExportWalletInfoScreen(
                  _generatedSeed24.join(' '),
                ),
              );
            }
          },
          icon: exported
              ? const Icon(Icons.check, size: 18, color: AppColors.znnColor)
              : SvgPicture.asset(
                  'assets/svg/ic_export_seed.svg',
                  colorFilter: ColorFilter.mode(
                    Theme.of(context).textTheme.bodyLarge!.color!,
                    BlendMode.srcIn,
                  ),
                  height: 16,
                ),
          label: Text(exported ? 'Exported' : 'Export seed'),
        );
      },
    );
  }

  Widget _getConfirmSecureCheckboxContainer() {
    return _buildCheckRow(
      value: _isSeedSecure,
      label: 'I have backed up my seed in a safe location',
      onChanged: (bool? value) {
        setState(() {
          _isSeedSecure = value;
        });
      },
    );
  }

  Widget _buildContinueButton() {
    return OnboardingButton(
      onPressed:
          _isSeedSecure! &&
              _isSeedWrittenDown! &&
              !_seedGridKey.currentState!.continueButtonDisabled!
          ? () {
              if (_isSeed12Selected) {
                NavigationUtils.push(
                  context,
                  NewWalletConfirmSeedScreen(_generatedSeed12),
                );
              } else {
                NavigationUtils.push(
                  context,
                  NewWalletConfirmSeedScreen(_generatedSeed24),
                );
              }
            }
          : null,
      text: 'Continue',
    );
  }

  Widget _getConfirmWrittenDownCheckbox() {
    return _buildCheckRow(
      value: _isSeedWrittenDown,
      label: 'I have written down my seed',
      onChanged: (bool? value) {
        setState(() {
          _isSeedWrittenDown = value;
        });
      },
    );
  }

  Widget _buildCheckRow({
    required bool? value,
    required String label,
    required ValueChanged<bool?> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Checkbox(
          value: value,
          checkColor: Theme.of(context).colorScheme.primary,
          activeColor: AppColors.znnColor,
          onChanged: onChanged,
        ),
        Text(
          label,
          style: TextStyle(fontSize: 14, color: dimColorOf(context)),
        ),
      ],
    );
  }

  bool _isSeedExported(List<String> exportedSeeds) => _isSeed12Selected
      ? exportedSeeds.contains(_generatedSeed12.join(' '))
      : exportedSeeds.contains(_generatedSeed24.join(' '));
}
