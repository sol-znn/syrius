part of '../view/node_update_card.dart';

/// Wide enough for a sha256 on one line beside its label.
const double _kDialogWidth = 680;

/// The width of the label column of a [_Fact].
const double _kFactLabelWidth = 124;

/// Asks whether [library] is to be installed, after listing what it is.
/// True for Install; false or null for Cancel, Escape or a click outside.
Future<bool?> _showInstallDialog(
  BuildContext context,
  DownloadedNodeLibrary library,
) {
  return showDialog<bool>(
    context: context,
    builder: (BuildContext context) => _InstallDialog(library),
  );
}

/// Asks whether a release that publishes no hash is to be downloaded with
/// nothing to check it against.
Future<bool?> _showUnverifiedDialog(BuildContext context, NodeRelease release) {
  return showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      final AppTokens tokens = AppTokens.of(context);
      final AppLocalizations l10n = context.l10n;
      return _Question(
        title: l10n.nodeUpdateUnverifiedTitle,
        warn: true,
        cancelKey: const ValueKey<String>('node_update_unverified_cancel'),
        confirmKey: const ValueKey<String>('node_update_unverified_download'),
        confirmLabel: l10n.nodeUpdateUnverifiedDownloadLabel,
        confirmStyle: cardSecondaryButtonStyle(context, line: tokens.warn),
        children: <Widget>[
          Text(
            l10n.nodeUpdateUnverifiedConfirm(release.tag),
            style: TextStyle(color: tokens.warn),
          ),
          const SizedBox(height: 12),
          _Fact(l10n.nodeUpdateRepositoryLabel, release.repository, data: true),
          if (release.asset != null)
            _Fact(l10n.nodeUpdateAssetLabel, release.asset!.name, data: true),
        ],
      );
    },
  );
}

/// Asks whether the override and anything staged are to be removed.
Future<bool?> _showUseBundledDialog(
  BuildContext context,
  NodeLibraryStatus status,
) {
  return showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      final AppLocalizations l10n = context.l10n;
      final NodeLibraryManifest? installed = status.installed;
      final NodeLibraryManifest? staged = status.staged;
      return _Question(
        title: l10n.nodeUpdateUseBundledTitle,
        cancelKey: const ValueKey<String>('node_update_bundled_cancel'),
        confirmKey: const ValueKey<String>('node_update_bundled_confirm'),
        confirmLabel: l10n.nodeUpdateUseBundledLabel,
        confirmStyle: cardSecondaryButtonStyle(context),
        children: <Widget>[
          if (installed != null)
            _Fact(
              l10n.nodeUpdateInstalledLabel,
              _Named.manifest(installed).text,
              data: true,
            ),
          if (staged != null)
            _Fact(
              l10n.nodeUpdateStagedLabel,
              _Named.manifest(staged).text,
              data: true,
            ),
          const SizedBox(height: 4),
          _Statement(l10n.nodeUpdateUseBundledConfirm),
        ],
      );
    },
  );
}

/// Asks whether [previous] is to be put back, after listing what it is.
Future<bool?> _showUsePreviousDialog(
  BuildContext context,
  NodeLibraryManifest previous,
) {
  return showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      final AppLocalizations l10n = context.l10n;
      return _Question(
        title: l10n.nodeUpdateUsePreviousTitle,
        cancelKey: const ValueKey<String>('node_update_previous_cancel'),
        confirmKey: const ValueKey<String>('node_update_previous_confirm'),
        confirmLabel: l10n.nodeUpdateUsePreviousLabel,
        confirmStyle: cardSecondaryButtonStyle(context),
        children: <Widget>[
          _Identity(
            source: previous.source,
            tag: previous.tag,
            asset: previous.asset,
            sha256: previous.sha256,
          ),
          const SizedBox(height: 4),
          _Statement(l10n.nodeUpdateUsePreviousConfirm),
        ],
      );
    },
  );
}

/// The confirmation every install goes through: the repository, the tag,
/// the asset, the library's whole sha256 and what each of the two checks
/// found, then what installing does.
class _InstallDialog extends StatelessWidget {
  const _InstallDialog(this._library);

  final DownloadedNodeLibrary _library;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppTokens tokens = AppTokens.of(context);
    final NodeChecksumFileCheck? checksumFile = _library.checksumFile;
    final NodeApiDigestCheck? apiDigest = _library.apiDigest;
    return _Question(
      title: l10n.nodeUpdateInstallTitle,
      cancelKey: const ValueKey<String>('node_update_dialog_cancel'),
      confirmKey: const ValueKey<String>('node_update_dialog_install'),
      confirmLabel: l10n.nodeUpdateInstallLabel,
      children: <Widget>[
        _Identity(
          source: _library.source,
          tag: _library.tag,
          asset: _library.asset,
          sha256: _library.sha256,
        ),
        _Fact(
          l10n.nodeUpdateChecksumFileLabel,
          _checksumFileText(l10n, checksumFile),
          color: checksumFile == NodeChecksumFileCheck.verified
              ? tokens.znnInk
              : tokens.warn,
        ),
        _Fact(
          l10n.nodeUpdateDigestLabel,
          _apiDigestText(l10n, apiDigest),
          color: apiDigest == NodeApiDigestCheck.verified
              ? tokens.znnInk
              : tokens.warn,
        ),
        const SizedBox(height: 4),
        _Statement(l10n.nodeUpdateInstallConfirm),
      ],
    );
  }
}

/// A dialog with Cancel and one action. Cancel holds the focus when it
/// opens, so Enter and Space back out; the action takes a deliberate Tab or
/// a click. Everything in it can be selected and copied.
class _Question extends StatelessWidget {
  const _Question({
    required this._title,
    required this._children,
    required this._cancelKey,
    required this._confirmKey,
    required this._confirmLabel,
    this._confirmStyle,
    this._warn = false,
  });

  final String _title;
  final List<Widget> _children;
  final Key _cancelKey;
  final Key _confirmKey;
  final String _confirmLabel;

  /// The filled main action when null.
  final ButtonStyle? _confirmStyle;

  /// Whether the title carries the warning mark.
  final bool _warn;

  @override
  Widget build(BuildContext context) {
    // Both actions use ordinary dialog geometry. This is a shared consistency
    // rule; the extra node-management questions have no exact reference shot.
    final ButtonStyle confirmStyle = (_confirmStyle ?? const ButtonStyle())
        .copyWith(
          minimumSize: WidgetStatePropertyAll<Size>(
            Size(64, AppTokens.of(context).buttonHeight),
          ),
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: 16),
          ),
          textStyle: const WidgetStatePropertyAll<TextStyle>(
            kOutlinedButtonTextStyle,
          ),
          visualDensity: VisualDensity.standard,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
    return DialogCard(
      title: _title,
      width: _kDialogWidth,
      icon: _warn
          ? Icon(
              Icons.warning_amber_rounded,
              size: 20,
              color: AppTokens.of(context).warn,
            )
          : null,
      body: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: _children,
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: _cancelKey,
          autofocus: true,
          style: quietButtonStyle(context),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.l10n.cancel),
        ),
        OutlinedButton(
          key: _confirmKey,
          style: confirmStyle,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(_confirmLabel),
        ),
      ],
    );
  }
}

/// What a library is: where it came from, its tag, its file and its hash.
class _Identity extends StatelessWidget {
  const _Identity({
    required this._source,
    required this._tag,
    required this._asset,
    required this._sha256,
  });

  final String _source;
  final String? _tag;
  final String _asset;
  final String _sha256;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final bool fromFile = _source == NodeUpdateSource.file;
    final String? tag = _tag;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (fromFile)
          _Fact(l10n.nodeUpdateRepositoryLabel, l10n.nodeUpdateNoneLabel)
        else
          _Fact(l10n.nodeUpdateRepositoryLabel, _source, data: true),
        if (tag == null)
          _Fact(l10n.nodeUpdateTagLabel, l10n.nodeUpdateNoneLabel)
        else
          _Fact(l10n.nodeUpdateTagLabel, tag, data: true),
        _Fact(
          fromFile ? l10n.nodeUpdateFileNameLabel : l10n.nodeUpdateAssetLabel,
          _asset,
          data: true,
        ),
        _Fact(l10n.nodeUpdateHashLabel, _sha256, data: true),
      ],
    );
  }
}

/// One line of a dialog: a label and its value.
class _Fact extends StatelessWidget {
  const _Fact(this._name, this._value, {this._data = false, this._color});

  final String _name;
  final String _value;

  /// Whether the value is a name, a tag or a hash: mono, and left to right
  /// in every language.
  final bool _data;

  /// The value's ink; the primary text colour when null.
  final Color? _color;

  @override
  Widget build(BuildContext context) {
    final TextStyle base = Theme.of(context).textTheme.bodyMedium!;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: _kFactLabelWidth,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(top: 2),
              child: Text(
                _label(context, _name),
                style: ledgerLabelStyle(context),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _data
                ? Text(
                    _value,
                    textDirection: TextDirection.ltr,
                    textAlign: ltrTextAlign(context),
                    style: monoStyle(base).copyWith(fontSize: 12, height: 1.5),
                  )
                : Text(_value, style: base.copyWith(color: _color)),
          ),
        ],
      ),
    );
  }
}

/// The plain line at the foot of a dialog saying what the action does.
class _Statement extends StatelessWidget {
  const _Statement(this._text);

  final String _text;

  @override
  Widget build(BuildContext context) {
    return Text(_text, style: Theme.of(context).textTheme.bodyMedium);
  }
}
