import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:open_filex/open_filex.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/disclosure.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_strip.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/navigation_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/help_widgets/about_information.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/help_widgets/community_card.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/help_widgets/licences.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_parts.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/copy_to_clipboard_button.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';

/// Installed wallet facts and the closed About groups, independent of RPC.
class AboutCard extends StatefulWidget {
  /// Optional sources keep finite view checks away from platform data.
  const AboutCard({
    this.loadInformation,
    this.openLink,
    this.openFolder,
    this.loadLicences,
    this.licencesTrailingBuilder,
    this.afterLicences,
    super.key,
  });

  /// Production reads PackageInfo and existing local metadata once per view.
  final Future<AboutInformation> Function()? loadInformation;

  /// Existing browser and folder actions, injectable without native calls.
  final ValueChanged<String>? openLink;

  /// The existing local-folder action, injectable without opening a window.
  final Future<void> Function(String path)? openFolder;

  /// Production consumes the actual Flutter registry on first opening.
  final AboutLicenceLoader? loadLicences;

  /// Content after the final real licence, owned by Settings.
  final WidgetBuilder? licencesTrailingBuilder;

  /// A separately owned sibling after the Licences group.
  final Widget? afterLicences;

  @override
  State<AboutCard> createState() => _AboutCardState();
}

class _AboutCardState extends State<AboutCard> {
  AboutInformation _information = AboutInformation();
  int _informationEpoch = 0;
  bool _licencesOpened = false;

  @override
  void initState() {
    super.initState();
    _readInformation();
  }

  @override
  void didUpdateWidget(AboutCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.loadInformation, widget.loadInformation)) {
      _readInformation();
    }
  }

  void _readInformation() {
    final int epoch = ++_informationEpoch;
    _information = AboutInformation();
    unawaited(
      Future<AboutInformation>.sync(
        widget.loadInformation ?? readAboutInformation,
      ).then(
        (AboutInformation value) {
          if (mounted && epoch == _informationEpoch) {
            setState(() => _information = value);
          }
        },
        onError: (Object _, StackTrace _) {
          // An old source cannot replace a newer snapshot or expose its error.
          if (mounted && epoch == _informationEpoch) {
            setState(() => _information = AboutInformation());
          }
        },
      ),
    );
  }

  String _value(String? value) =>
      value == null || value.trim().isEmpty ? context.l10n.aboutUnknown : value;

  void _openLink(String url) {
    final ValueChanged<String>? open = widget.openLink;
    if (open != null) {
      open(url);
    } else {
      unawaited(NavigationUtils.openUrl(url));
    }
  }

  Future<void> _openFolder(String path) async {
    final Future<void> Function(String)? open = widget.openFolder;
    if (open != null) {
      await open(path);
    } else {
      await OpenFilex.open(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double licencesHeight = math.max(
          tokens.aboutLicencesMinHeight,
          constraints.hasBoundedHeight
              ? constraints.maxHeight -
                    3 * (tokens.aboutGroupHeaderHeight + tokens.pageGap)
              : tokens.aboutLicencesMinHeight,
        );
        return SettingsSection(
          key: const Key('about_page'),
          children: <Widget>[
            _buildStrip(tokens),
            CommunityCard(openLink: _openLink),
            Panel(
              key: const Key('about_computer'),
              child: Disclosure(
                title: context.l10n.aboutComputer,
                summary: context.l10n.aboutComputerHint,
                keyPrefix: 'about_computer',
                keepAlive: true,
                child: _buildComputer(tokens),
              ),
            ),
            Panel(
              key: const Key('about_licences'),
              child: Disclosure(
                title: context.l10n.aboutLicences,
                keyPrefix: 'about_licences',
                keepAlive: true,
                onChanged: (bool open) {
                  if (open && !_licencesOpened) {
                    setState(() => _licencesOpened = true);
                  }
                },
                child: _licencesOpened
                    ? SizedBox(
                        height: licencesHeight,
                        child: Licences(
                          loadLicences: widget.loadLicences,
                          trailingBuilder: widget.licencesTrailingBuilder,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            if (widget.afterLicences != null) widget.afterLicences!,
          ],
        );
      },
    );
  }

  Widget _buildStrip(AppTokens tokens) {
    final List<StripFigure> figures = <StripFigure>[
      StripFigure(
        label: context.l10n.aboutSyrius,
        value: Ltr(
          child: Text(
            _value(_information.version),
            key: const Key('about_version'),
          ),
        ),
      ),
      StripFigure(
        label: context.l10n.aboutEmbeddedNode,
        value: Ltr(
          child: Text(
            _value(_information.embeddedNodeVersion),
            key: const Key('about_embedded_version'),
          ),
        ),
      ),
      StripFigure(
        label: context.l10n.aboutBuild,
        value: Tooltip(
          message: _value(_information.build),
          child: Text(
            _value(_information.build),
            key: const Key('about_build'),
            textDirection: TextDirection.ltr,
            style: tokens.dataText.copyWith(color: tokens.dim),
          ),
        ),
      ),
    ];
    final Widget updates = SeamGate(
      key: const Key('about_update_gate'),
      seam: Seam.walletUpdateNotice,
      child: Wrap(
        spacing: tokens.inlineGap,
        runSpacing: tokens.inlineGap,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Text(
            context.l10n.stripWalletUpdates,
            key: const Key('about_update_label'),
            style: tokens.compactText.copyWith(color: tokens.dim),
          ),
          SecondaryAction(
            child: OutlinedButton(
              key: const Key('about_what_changed'),
              onPressed: () =>
                  throw const SeamNotBuilt(Seam.walletUpdateNotice),
              child: Text(context.l10n.aboutWhatChanged),
            ),
          ),
          PrimaryPill(
            key: const Key('about_download_verify'),
            onPressed: () => throw const SeamNotBuilt(Seam.walletUpdateNotice),
            icon: Icon(Icons.download_outlined, size: tokens.railIconSize),
            child: Text(context.l10n.aboutDownloadVerify),
          ),
        ],
      ),
    );
    // Actions wrap below the figures when text scaling uses the strip's room.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double scaledActions = MediaQuery.textScalerOf(
          context,
        ).scale(tokens.settingsMenuWidth * 2);
        final bool stacked =
            constraints.maxWidth <=
            scaledActions + tokens.settingsMenuWidth * 2;
        if (!stacked) {
          return PageStrip(
            key: const Key('about_strip'),
            figures: figures,
            actions: <Widget>[updates],
          );
        }
        return Panel(
          key: const Key('about_strip'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              PageStrip(figures: figures),
              Padding(
                padding: tokens.stripPadding,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: updates,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildComputer(AppTokens tokens) {
    final Map<AboutField, String> facts = _information.details;
    Widget row(
      String key,
      String label,
      String? value, {
      bool folder = false,
      bool link = false,
    }) {
      final bool present = value != null && value.trim().isNotEmpty;
      final Uri? uri = link && present ? Uri.tryParse(value) : null;
      final bool canOpen =
          folder && present ||
          uri != null &&
              (uri.scheme == 'https' || uri.scheme == 'http') &&
              uri.host.isNotEmpty;
      return _InfoRow(
        key: ValueKey<String>('about_info_$key'),
        label: label,
        value: _value(value),
        copyValue: present ? value : null,
        openTooltip: folder
            ? context.l10n.aboutOpenFolder
            : context.l10n.aboutOpenLink,
        onOpen: !canOpen
            ? null
            : folder
            ? () => unawaited(_openFolder(value!))
            : () => _openLink(value!),
      );
    }

    return Padding(
      padding: EdgeInsetsDirectional.only(bottom: tokens.cardGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          row('version', context.l10n.aboutVersion, _information.version),
          row('build', context.l10n.aboutBuildNumber, _information.buildNumber),
          row(
            'wallet_type',
            context.l10n.aboutWalletType,
            facts[AboutField.walletType],
          ),
          row('sdk', context.l10n.aboutSdk, facts[AboutField.sdk]),
          row('branch', context.l10n.aboutBranch, facts[AboutField.branch]),
          row('commit', context.l10n.aboutCommit, facts[AboutField.commit]),
          row(
            'commit_message',
            context.l10n.aboutCommitMessage,
            facts[AboutField.commitMessage],
          ),
          row(
            'commit_date',
            context.l10n.aboutCommitDate,
            facts[AboutField.commitDate],
          ),
          row(
            'origin',
            context.l10n.aboutOrigin,
            facts[AboutField.origin],
            link: true,
          ),
          row(
            'hostname',
            context.l10n.aboutHostname,
            facts[AboutField.hostname],
          ),
          row('local_ip', context.l10n.aboutLocalIp, facts[AboutField.localIp]),
          row(
            'os',
            context.l10n.aboutOperatingSystem,
            facts[AboutField.operatingSystem],
          ),
          row(
            'os_version',
            context.l10n.aboutVersion,
            facts[AboutField.operatingSystemVersion],
          ),
          row(
            'processors',
            context.l10n.aboutProcessors,
            facts[AboutField.processors],
          ),
          Padding(
            padding: tokens.settingsRowPadding,
            child: Text(
              usesLatinScript(context)
                  ? context.l10n.aboutPaths.toUpperCase()
                  : context.l10n.aboutPaths,
              style: tokens.ledgerText,
            ),
          ),
          row(
            'zenon_data',
            context.l10n.aboutZenonData,
            facts[AboutField.zenonData],
            folder: true,
          ),
          row(
            'cache',
            context.l10n.aboutCache,
            facts[AboutField.cache],
            folder: true,
          ),
          row(
            'wallet',
            context.l10n.aboutWallet,
            facts[AboutField.wallet],
            folder: true,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.copyValue,
    this.onOpen,
    this.openTooltip,
    super.key,
  });

  final String label;
  final String value;
  final String? copyValue;
  final VoidCallback? onOpen;
  final String? openTooltip;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Padding(
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: tokens.cardPadding.horizontal / 2,
        vertical: tokens.statusDotSize / 2,
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double labelWidth = math.min(
            tokens.aboutInfoLabelWidth,
            constraints.maxWidth / 3,
          );
          return Row(
            children: <Widget>[
              SizedBox(
                width: labelWidth,
                child: Text(label, style: tokens.settingsHintText),
              ),
              SizedBox(width: tokens.inlineGap),
              Expanded(
                child: Tooltip(
                  message: value,
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: ltrUnlessRtl(value),
                    textAlign: ltrTextAlign(context),
                    style: tokens.dataText,
                  ),
                ),
              ),
              IconButtonTheme(
                data: IconButtonThemeData(
                  style: IconButton.styleFrom(
                    minimumSize: Size.square(tokens.aboutInfoActionSize),
                    padding: EdgeInsets.all(tokens.fieldLabelGap),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (copyValue != null)
                      CopyToClipboardButton(
                        copyValue!,
                        iconSize: tokens.settingsIconSize,
                      ),
                    if (onOpen != null)
                      IconButton(
                        tooltip: openTooltip,
                        iconSize: tokens.settingsIconSize,
                        icon: Icon(Icons.open_in_new, color: tokens.faint),
                        onPressed: onOpen,
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
