import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/segment.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/entry_card_surface.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/import_wallet/import_draft.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';

// Draw the reference contour with the existing SVG renderer.
const String _fileSymbol =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
    'fill="none" stroke="currentColor" stroke-width="1.8" '
    'stroke-linecap="round" stroke-linejoin="round">'
    '<path d="M6 2h8l6 6v14H6zM14 2v6h6"/></svg>';

/// Only owner-supplied draft data and callbacks enter this import view.
class ImportSurface extends StatelessWidget {
  /// Presents private draft validity and guarded actions from the import owner.
  const ImportSurface({
    required this.seedController,
    required this.draft,
    required this.onSeedChanged,
    required this.onWordCountChanged,
    required this.onBrowse,
    required this.onBack,
    required this.onContinue,
    this.fileSelected = false,
    this.fileRefused = false,
    this.pickerFailed = false,
    this.wrapDrop,
    this.background,
    super.key,
  });

  /// The owner's private text buffer; the surface does not retain another copy.
  final TextEditingController seedController;

  /// The exact validation snapshot corresponding to the displayed input.
  final ImportSeedDraft draft;

  /// Replaces the owner's draft after a guarded text edit.
  final ValueChanged<String> onSeedChanged;

  /// Selects the expected mnemonic length, either 12 or 24 words.
  final ValueChanged<int> onWordCountChanged;

  /// Opens the genuine picker only after the current route admits the action.
  final VoidCallback onBrowse;

  /// Returns through the existing entry navigation owner.
  final VoidCallback onBack;

  /// Admits the current seed or file, absent while neither is valid.
  final VoidCallback? onContinue;

  /// Whether a structurally admitted file is selected, before authentication.
  final bool fileSelected;

  /// Whether the last file offer failed the bounded content probe.
  final bool fileRefused;

  /// Whether the platform picker failed, mapped to a safe localized message.
  final bool pickerFailed;

  /// Optional platform drop adapter supplied by the genuine import owner.
  final Widget Function(Widget)? wrapDrop;

  /// Optional inert backdrop for isolated presentation fixtures.
  final Widget? background;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final Widget drop = _buildDrop(context, tokens);
    return EntryCardSurface(
      marker: const Key('import_screen_marker'),
      title: context.l10n.importWalletTitle,
      steps: <String>[
        context.l10n.importSeedOrFile,
        context.l10n.password,
        context.l10n.entryReady,
      ],
      step: 0,
      onBack: onBack,
      background: background,
      footer: Wrap(
        spacing: tokens.entryGap,
        runSpacing: tokens.entryGap,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Segment<int>(
            keyPrefix: 'import_words',
            pillPadding: tokens.importWordChoicePadding,
            items: <SegmentItem<int>>[
              for (final int count in <int>[12, 24])
                SegmentItem<int>(
                  value: count,
                  label: context.l10n.seedChoiceWordsLabel(count),
                  labelStyle: tokens.compactText,
                ),
            ],
            selected: draft.expectedWords,
            onChanged: onWordCountChanged,
          ),
          PrimaryPill(
            key: const Key('import_continue'),
            onPressed: onContinue,
            style: ButtonStyle(
              visualDensity: VisualDensity.standard,
              padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
                tokens.importContinuePadding,
              ),
            ),
            child: Text(context.l10n.continueText),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: tokens.entryGap,
        children: <Widget>[
          wrapDrop?.call(drop) ?? drop,
          Focus(
            canRequestFocus: false,
            skipTraversal: true,
            includeSemantics: false,
            child: Builder(
              builder: (BuildContext context) {
                final bool focused = Focus.of(context).hasFocus;
                return Container(
                  key: const Key('import_seed_panel'),
                  constraints: BoxConstraints(
                    minHeight: tokens.importSeedMinHeight,
                  ),
                  padding: tokens.transferFieldPadding,
                  decoration: BoxDecoration(
                    color: tokens.card2,
                    border: Border.all(
                      color: focused ? tokens.faint : tokens.line,
                    ),
                    borderRadius: BorderRadius.circular(tokens.cardRadius),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Semantics(
                        label: context.l10n.importSeedOrFile,
                        child: TextField(
                          key: const Key('import_seed_field'),
                          controller: seedController,
                          maxLines: null,
                          autocorrect: false,
                          enableSuggestions: false,
                          textDirection: TextDirection.ltr,
                          style: tokens.bodyText,
                          inputFormatters: <TextInputFormatter>[
                            LengthLimitingTextInputFormatter(512),
                          ],
                          decoration: const InputDecoration(
                            isDense: true,
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: onSeedChanged,
                        ),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Text(
                          context.l10n.importWordCount(
                            draft.words.length,
                            draft.expectedWords,
                          ),
                          style: tokens.entryFooterText.copyWith(
                            fontFamily: tokens.monoFontFamily,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (draft.words.length == draft.expectedWords && !draft.valid)
            Text(
              context.l10n.importSeedInvalid,
              style: tokens.entryFooterText.copyWith(color: tokens.error),
            ),
        ],
      ),
    );
  }

  Widget _buildDrop(BuildContext context, AppTokens tokens) => Material(
    color: tokens.card2,
    borderRadius: BorderRadius.circular(tokens.dialogRadius),
    child: InkWell(
      key: const Key('import_file_zone'),
      borderRadius: BorderRadius.circular(tokens.dialogRadius),
      hoverColor: Colors.transparent,
      onTap: onBrowse,
      mouseCursor: SystemMouseCursors.click,
      child: DottedBorder(
        options: RoundedRectDottedBorderOptions(
          color: fileRefused || pickerFailed ? tokens.error : tokens.faint,
          strokeWidth: tokens.importDropLineWidth,
          dashPattern: tokens.importDropDashPattern,
          // The centered stroke overflowed the CSS box and omitted its layout
          // space. Keep its thickness inside the box and reserve that space.
          radius: Radius.circular(
            tokens.dialogRadius - tokens.importDropLineWidth / 2,
          ),
          borderPadding: EdgeInsets.all(tokens.importDropLineWidth / 2),
          padding: EdgeInsets.all(tokens.importDropLineWidth),
        ),
        child: Padding(
          padding: EdgeInsets.all(tokens.importDropPadding),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              spacing: tokens.importDropGap,
              children: <Widget>[
                if (fileRefused || pickerFailed)
                  Icon(
                    Icons.error_outline,
                    size: tokens.importDropIconSize,
                    color: tokens.error,
                  )
                else
                  SvgPicture.string(
                    _fileSymbol,
                    key: const Key('import_file_symbol'),
                    width: tokens.importDropIconSize,
                    height: tokens.importDropIconSize,
                    colorFilter: ColorFilter.mode(
                      tokens.faint,
                      BlendMode.srcIn,
                    ),
                    excludeFromSemantics: true,
                  ),
                Text(
                  pickerFailed
                      ? context.l10n.importFileOpenFailed
                      : fileRefused
                      ? context.l10n.importFileInvalid
                      : fileSelected
                      ? context.l10n.importFileSelected
                      : context.l10n.importSeedHint,
                  textAlign: TextAlign.center,
                  style: tokens.bodyText,
                ),
                Text(
                  context.l10n.importFileHint,
                  textAlign: TextAlign.center,
                  style: tokens.entryFooterText,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Password entry is presentation only; the owner validates and publishes it.
class ImportPasswordSurface extends StatelessWidget {
  /// Presents new encryption-password fields without writing wallet data.
  const ImportPasswordSurface({
    required this.password,
    required this.confirmation,
    required this.onChanged,
    required this.onBack,
    required this.onContinue,
    this.background,
    super.key,
  });

  /// The original owner's private password buffer.
  final TextEditingController password;

  /// The matching-password buffer owned by the same import route.
  final TextEditingController confirmation;

  /// Invalidates the current action source after either field changes.
  final VoidCallback onChanged;

  /// The guarded action returning to the original import step.
  final VoidCallback onBack;

  /// Admits creation only when the owner validated both private fields.
  final VoidCallback? onContinue;

  /// Optional inert backdrop for isolated presentation fixtures.
  final Widget? background;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return EntryCardSurface(
      marker: const Key('import_password_marker'),
      title: context.l10n.importPasswordTitle,
      steps: <String>[
        context.l10n.importSeedOrFile,
        context.l10n.password,
        context.l10n.entryReady,
      ],
      step: 1,
      onBack: onBack,
      background: background,
      footer: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: PrimaryPill(
          key: const Key('import_password_continue'),
          onPressed: onContinue,
          child: Text(context.l10n.continueText),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: tokens.entryGap,
        children: <Widget>[
          Text(context.l10n.importPasswordHint, style: tokens.entryFooterText),
          TextField(
            key: const Key('import_new_password'),
            controller: password,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(labelText: context.l10n.password),
            onChanged: (_) => onChanged(),
            onSubmitted: (_) => onContinue?.call(),
          ),
          TextField(
            key: const Key('import_confirm_password'),
            controller: confirmation,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: context.l10n.importConfirmPassword,
            ),
            onChanged: (_) => onChanged(),
            onSubmitted: (_) => onContinue?.call(),
          ),
          Text(context.l10n.entryPasswordRule, style: tokens.entryFooterText),
        ],
      ),
    );
  }
}

/// The exact encrypted result and its access lifecycle remain with the owner.
class ImportUnlockSurface extends StatelessWidget {
  /// Presents authentication for the exact original encrypted-file selection.
  const ImportUnlockSurface({
    required this.password,
    required this.onChanged,
    required this.onBack,
    required this.onContinue,
    this.error,
    this.busy = false,
    this.background,
    super.key,
  });

  /// The authentication owner's private password buffer.
  final TextEditingController password;

  /// Replaces the action source after an admitted password edit.
  final VoidCallback onChanged;

  /// The guarded action returning to the original file selection.
  final VoidCallback onBack;

  /// Starts the owner's original decrypt attempt, absent while unavailable.
  final VoidCallback? onContinue;

  /// Safe localized failure text, never raw exceptions or private paths.
  final String? error;

  /// Whether original decryption or access and release are still active.
  final bool busy;

  /// Optional inert backdrop for isolated presentation fixtures.
  final Widget? background;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return EntryCardSurface(
      marker: const Key('import_unlock_marker'),
      title: context.l10n.importUnlockTitle,
      steps: <String>[
        context.l10n.importSeedOrFile,
        context.l10n.password,
        context.l10n.entryReady,
      ],
      step: 1,
      onBack: onBack,
      background: background,
      footer: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: PrimaryPill(
          key: const Key('import_unlock_continue'),
          onPressed: busy ? null : onContinue,
          icon: busy
              ? SizedBox.square(
                  dimension: tokens.welcomeGlyphSize,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          child: Text(context.l10n.continueText),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: tokens.entryGap,
        children: <Widget>[
          Text(context.l10n.importUnlockHint, style: tokens.entryFooterText),
          TextField(
            key: const Key('import_unlock_password'),
            controller: password,
            enabled: !busy,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: context.l10n.password,
              errorText: error,
            ),
            onChanged: (_) => onChanged(),
            onSubmitted: (_) {
              if (!busy) onContinue?.call();
            },
          ),
        ],
      ),
    );
  }
}
