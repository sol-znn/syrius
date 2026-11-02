import 'dart:async';

import 'package:flutter_vector_icons/flutter_vector_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/disclosure.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/navigation_utils.dart';

/// All original community destinations, inside one initially closed group.
class CommunityCard extends StatelessWidget {
  /// Browser opening is injectable for finite checks without external actions.
  const CommunityCard({this.openLink, super.key});

  /// Null retains the existing system-browser action.
  final ValueChanged<String>? openLink;

  @override
  Widget build(BuildContext context) {
    final List<(IconData, String, String)> links = <(IconData, String, String)>[
      (MaterialCommunityIcons.home, context.l10n.aboutZenonNetwork, kWebsite),
      (
        MaterialCommunityIcons.forum,
        context.l10n.aboutCommunityForum,
        kOrgCommunityForum,
      ),
      (MaterialCommunityIcons.tools, context.l10n.aboutZenonTools, kTools),
      (
        MaterialCommunityIcons.web,
        context.l10n.aboutZenonOrg,
        kOrgCommunityWebsite,
      ),
      (
        MaterialCommunityIcons.lan,
        context.l10n.aboutZenonHub,
        kHubCommunityWebsite,
      ),
      (Icons.explore_outlined, context.l10n.aboutExplorer, kExplorer),
      (
        Icons.explore_outlined,
        context.l10n.aboutHubExplorer,
        kHubCommunityExplorer,
      ),
      (MaterialCommunityIcons.twitter, context.l10n.aboutTwitter, kTwitter),
      (MaterialCommunityIcons.discord, context.l10n.aboutDiscord, kDiscord),
      (Icons.telegram, context.l10n.aboutTelegram, kTelegram),
      (Icons.article_outlined, context.l10n.aboutMedium, kMedium),
      (MaterialCommunityIcons.github, context.l10n.aboutGithub, kGithub),
      (
        MaterialCommunityIcons.bitcoin,
        context.l10n.aboutBitcoinTalk,
        kBitcoinTalk,
      ),
      (MaterialCommunityIcons.reddit, context.l10n.aboutReddit, kReddit),
      (MaterialCommunityIcons.youtube, context.l10n.aboutYoutube, kYoutube),
      (
        MaterialCommunityIcons.book_open_page_variant,
        context.l10n.aboutWiki,
        kWiki,
      ),
      (
        MaterialCommunityIcons.book_multiple,
        context.l10n.aboutCommunityWiki,
        kOrgCommunityWiki,
      ),
      (
        MaterialCommunityIcons.file_document,
        context.l10n.aboutWhitepaper,
        kWhitepaper,
      ),
    ];
    final Map<int, String> groups = <int, String>{
      0: context.l10n.aboutWebsites,
      5: context.l10n.aboutExplorers,
      7: context.l10n.aboutSocial,
      15: context.l10n.aboutDocumentation,
    };
    final AppTokens tokens = AppTokens.of(context);
    return Panel(
      key: const Key('about_links'),
      child: Disclosure(
        title: context.l10n.aboutLinks,
        summary: context.l10n.aboutLinksHint,
        count: links.length,
        keyPrefix: 'about_links',
        keepAlive: true,
        child: Padding(
          padding: EdgeInsetsDirectional.only(bottom: tokens.cardGap),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int index = 0; index < links.length; index++) ...<Widget>[
                if (groups[index] != null)
                  Padding(
                    padding: tokens.settingsRowPadding,
                    child: Text(
                      usesLatinScript(context)
                          ? groups[index]!.toUpperCase()
                          : groups[index]!,
                      style: tokens.ledgerText,
                    ),
                  ),
                _Link(
                  key: ValueKey<String>('about_link_$index'),
                  icon: links[index].$1,
                  title: links[index].$2,
                  url: links[index].$3,
                  openLink: openLink,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({
    required this.icon,
    required this.title,
    required this.url,
    this.openLink,
    super.key,
  });

  final IconData icon;
  final String title;
  final String url;
  final ValueChanged<String>? openLink;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Tooltip(
      message: url,
      waitDuration: Durations.long2,
      child: Semantics(
        link: true,
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          hoverColor: tokens.hover,
          onTap: () {
            final ValueChanged<String>? open = openLink;
            if (open != null) {
              open(url);
            } else {
              unawaited(NavigationUtils.openUrl(url));
            }
          },
          child: Padding(
            padding: EdgeInsetsDirectional.symmetric(
              horizontal: tokens.cardPadding.horizontal / 2,
              vertical: tokens.inlineGap,
            ),
            child: Row(
              children: <Widget>[
                Icon(icon, size: tokens.railIconSize, color: tokens.faint),
                SizedBox(width: tokens.cardGap),
                Expanded(child: Text(title, style: tokens.bodyText)),
                Icon(
                  Icons.open_in_new,
                  size: tokens.settingsIconSize,
                  color: tokens.faint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
