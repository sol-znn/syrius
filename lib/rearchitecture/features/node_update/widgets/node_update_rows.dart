part of '../view/node_update_card.dart';

/// The rows of the panel, once the disk has been read.
class _Body extends StatelessWidget {
  const _Body({required this._pickFile, super.key});

  final NodeLibraryFilePicker _pickFile;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<NodeUpdateCubit, NodeUpdatePanelState, bool>(
      selector: (NodeUpdatePanelState state) =>
          _RollbackRow.offered(state.library),
      builder: (BuildContext context, bool rollback) => SettingsList(
        children: <Widget>[
          const _NowRow(),
          const _CheckRow(),
          _InstallRow(pickFile: _pickFile),
          if (rollback) const _RollbackRow(),
          const _SourceRow(),
        ],
      ),
    );
  }
}

/// Which library is loaded, its hash, and what waits for the next start.
class _NowRow extends StatelessWidget {
  const _NowRow();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return BlocSelector<
      NodeUpdateCubit,
      NodeUpdatePanelState,
      NodeLibraryStatus?
    >(
      selector: (NodeUpdatePanelState state) => state.library,
      builder: (BuildContext context, NodeLibraryStatus? status) {
        if (status == null) {
          return const SizedBox.shrink();
        }
        final _Named? loaded = _Named.loaded(status);
        final NodeLibraryManifest? staged = status.staged;
        // A staged library is promoted before anything is loaded, so it is
        // what the next start uses.
        final _Named? coming = staged != null
            ? _Named.manifest(staged)
            : _Named.resolved(status);
        final _Named? shown = loaded ?? coming;
        final String? comingName = coming?.name;
        final String? pending =
            loaded == null ||
                coming == null ||
                (staged == null && !loaded.differsFrom(coming))
            ? null
            : comingName == null
            ? l10n.nodeUpdateReopenBundledLabel
            : l10n.nodeUpdateReopenStagedLabel(comingName);
        final NodeLibraryBadMarker? bad = status.bad;
        final String? sha256 = shown?.sha256;
        return SettingRow(
          label: loaded == null
              ? l10n.nodeUpdateNextStartLabel
              : l10n.nodeUpdateLoadedLabel,
          below: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (shown == null)
                _Note(l10n.nodeUpdateMissingLabel)
              else
                _LibraryName(shown),
              if (sha256 != null) _HashLine(sha256),
              // There is no safe way to restart from inside: quitting goes
              // through the window's close handler, which stops the node and
              // exits, and nothing starts the wallet again. So the line says
              // what to do and offers no button.
              if (pending != null)
                _Note(
                  pending,
                  icon: Icons.restart_alt,
                  key: const ValueKey<String>('node_update_pending'),
                ),
              // The marker outlives a roll back; it only matters while the
              // override it names is still the installed one.
              if (bad != null && status.installed?.sha256 == bad.sha256)
                _Note(l10n.nodeUpdateBadError),
              if (status.stagedRejected != null)
                _Note(l10n.nodeUpdateStagedRejectedError),
            ],
          ),
        );
      },
    );
  }
}

/// "Bundled", or an override's tag and repository.
class _LibraryName extends StatelessWidget {
  const _LibraryName(this._library);

  final _Named _library;

  @override
  Widget build(BuildContext context) {
    final TextStyle? ink = Theme.of(context).textTheme.bodyMedium;
    final String? name = _library.name;
    if (name == null) {
      return Text(context.l10n.nodeUpdateBundledLabel, style: ink);
    }
    final String? repository = _library.repository;
    return Wrap(
      spacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(name, textDirection: TextDirection.ltr, style: monoStyle(ink)),
        if (repository == null)
          Text(
            context.l10n.nodeUpdateFromFileLabel,
            style: settingHintStyle(context),
          )
        else
          Text(
            repository,
            textDirection: TextDirection.ltr,
            style: settingMonoStyle(context),
          ),
      ],
    );
  }
}

/// A sha256 cut in the middle, whole in its tooltip, with a copy button.
class _HashLine extends StatelessWidget {
  const _HashLine(this._sha256);

  final String _sha256;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          _label(context, l10n.nodeUpdateHashLabel),
          style: ledgerLabelStyle(context),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Tooltip(
            message: _sha256,
            child: Text(
              _middle(_sha256),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              style: settingMonoStyle(context),
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButtonTheme(
          data: IconButtonThemeData(
            style: IconButton.styleFrom(
              padding: const EdgeInsetsDirectional.all(6),
              minimumSize: const Size.square(28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          child: CopyToClipboardButton(
            _sha256,
            iconSize: 14,
            tooltip: l10n.nodeUpdateHashCopyTooltip,
          ),
        ),
      ],
    );
  }
}

/// One line that needs the person, in the warning tone.
class _Note extends StatelessWidget {
  const _Note(
    this._text, {
    this._icon = Icons.warning_amber_rounded,
    super.key,
  });

  final String _text;
  final IconData _icon;

  @override
  Widget build(BuildContext context) {
    final Color warn = AppTokens.of(context).warn;
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 1),
            child: Icon(_icon, size: 16, color: warn),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium!.copyWith(color: warn),
            ),
          ),
        ],
      ),
    );
  }
}

/// A failure in the person's words, with the checksums that go with it.
class _ProblemText extends StatelessWidget {
  const _ProblemText(this._error, {super.key});

  final NodeUpdateException _error;

  @override
  Widget build(BuildContext context) {
    final _Problem problem = _problemOf(context.l10n, _error);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(problem.message, style: settingErrorStyle(context)),
        for (final MapEntry<String, String> value in problem.values.entries)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: _kFactLabelWidth,
                  child: Text(
                    _label(context, value.key),
                    style: ledgerLabelStyle(context),
                  ),
                ),
                Flexible(
                  child: SelectableText(
                    value.value,
                    textDirection: TextDirection.ltr,
                    style: settingMonoStyle(context).copyWith(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The newest release of the repository, asked for with Check and never
/// otherwise.
class _CheckRow extends StatelessWidget {
  const _CheckRow();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return BlocBuilder<NodeUpdateCubit, NodeUpdatePanelState>(
      buildWhen: (NodeUpdatePanelState before, NodeUpdatePanelState now) =>
          before.check != now.check || before.idle != now.idle,
      builder: (BuildContext context, NodeUpdatePanelState state) {
        return SettingRow(
          label: l10n.nodeUpdateReleaseLabel,
          trailing: OutlinedButton(
            key: const ValueKey<String>('node_update_check'),
            style: cardSecondaryButtonStyle(context),
            onPressed: state.idle
                ? () => unawaited(context.read<NodeUpdateCubit>().check())
                : null,
            child: Text(l10n.nodeUpdateCheckLabel),
          ),
          below: StateSwitcher(
            alignment: AlignmentDirectional.topStart,
            child: _buildAnswer(context, state.check),
          ),
        );
      },
    );
  }

  Widget _buildAnswer(BuildContext context, NodeUpdateCheck check) {
    final AppLocalizations l10n = context.l10n;
    switch (check) {
      case NodeUpdateCheckIdle():
        return Text(
          l10n.nodeUpdateNotCheckedHint,
          key: const ValueKey<String>('node_update_check_idle'),
          style: settingHintStyle(context),
        );
      case NodeUpdateCheckRunning():
        return const Padding(
          key: ValueKey<String>('node_update_check_running'),
          padding: EdgeInsetsDirectional.symmetric(vertical: 4),
          child: RepaintBoundary(child: Skeleton(width: 240)),
        );
      case NodeUpdateCheckFailed(:final NodeUpdateException error):
        return _ProblemText(
          error,
          key: const ValueKey<String>('node_update_check_failed'),
        );
      case NodeUpdateCheckDone(
        :final NodeRelease? release,
        :final NodeUpdateState comparison,
      ):
        if (release == null) {
          return Text(
            l10n.nodeUpdateNoReleaseLabel,
            key: const ValueKey<String>('node_update_check_empty'),
            style: settingHintStyle(context),
          );
        }
        return _ReleaseLine(
          release,
          comparison,
          key: ValueKey<String>('node_update_release_${release.tag}'),
        );
    }
  }
}

/// A release's tag, its date and how it stands to what is installed.
class _ReleaseLine extends StatelessWidget {
  const _ReleaseLine(this._release, this._comparison, {super.key});

  final NodeRelease _release;
  final NodeUpdateState _comparison;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppTokens tokens = AppTokens.of(context);
    final TextStyle ink = Theme.of(context).textTheme.bodyMedium!;
    final DateTime? published = _release.publishedAt;
    final Color tone = switch (_comparison) {
      NodeUpdateState.upToDate || NodeUpdateState.staged => tokens.znnInk,
      NodeUpdateState.updateAvailable => tokens.warn,
      NodeUpdateState.unknown => tokens.faint,
    };
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(
          _release.tag,
          textDirection: TextDirection.ltr,
          style: monoStyle(ink),
        ),
        if (published != null)
          Text(
            MaterialLocalizations.of(
              context,
            ).formatShortDate(published.toLocal()),
            style: settingHintStyle(context),
          ),
        Text(
          _comparisonText(l10n, _comparison),
          key: const ValueKey<String>('node_update_comparison'),
          style: ink.copyWith(color: tone),
        ),
        if (_release.asset == null)
          Text(
            l10n.nodeUpdateNoAssetError(_release.tag),
            style: ink.copyWith(color: tokens.warn),
          ),
      ],
    );
  }
}

/// Download and From file, and under them the progress of whichever runs,
/// or why it failed.
class _InstallRow extends StatelessWidget {
  const _InstallRow({required this._pickFile});

  final NodeLibraryFilePicker _pickFile;

  static bool _downloadable(NodeUpdatePanelState state) {
    final NodeUpdateCheck check = state.check;
    return check is NodeUpdateCheckDone && check.downloadable;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return BlocBuilder<NodeUpdateCubit, NodeUpdatePanelState>(
      buildWhen: (NodeUpdatePanelState before, NodeUpdatePanelState now) =>
          before.step != now.step ||
          before.idle != now.idle ||
          _downloadable(before) != _downloadable(now),
      builder: (BuildContext context, NodeUpdatePanelState state) {
        final NodeUpdateCubit cubit = context.read<NodeUpdateCubit>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SettingRow(
              label: l10n.nodeUpdateInstallLabel,
              hint: l10n.nodeUpdateInstallHint,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  OutlinedButton(
                    key: const ValueKey<String>(
                      'node_update_install_from_file',
                    ),
                    style: cardSecondaryButtonStyle(context),
                    onPressed: state.idle
                        ? () => unawaited(_onFromFile(cubit))
                        : null,
                    child: Text(l10n.nodeUpdateFileLabel),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    key: const ValueKey<String>('node_update_download'),
                    // The filled main action, at the height of the
                    // secondary one beside it.
                    style: OutlinedButton.styleFrom(
                      minimumSize: Size(
                        64,
                        AppTokens.of(context).compactButtonHeight,
                      ),
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: 12,
                      ),
                      textStyle: kTextButtonTextStyle,
                      visualDensity: VisualDensity.standard,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: state.idle && _downloadable(state)
                        ? () => unawaited(cubit.download())
                        : null,
                    child: Text(l10n.nodeUpdateDownloadLabel),
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: Durations.medium1,
              curve: Easing.standard,
              alignment: AlignmentDirectional.topStart,
              child: StateSwitcher(
                alignment: AlignmentDirectional.topStart,
                child: _buildActivity(context, cubit, state.step),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _onFromFile(NodeUpdateCubit cubit) async {
    final String? picked = await _pickFile();
    if (picked != null) {
      await cubit.installFromFile(File(picked));
    }
  }

  Widget _buildActivity(
    BuildContext context,
    NodeUpdateCubit cubit,
    NodeUpdateStep step,
  ) {
    final AppLocalizations l10n = context.l10n;
    switch (step) {
      // While a question is open the dialog says everything there is.
      case NodeUpdateStepIdle() ||
          NodeUpdateConfirmAsk() ||
          NodeUpdateUnverifiedAsk():
        return const SizedBox(
          key: ValueKey<String>('node_update_activity_none'),
          width: double.infinity,
        );
      case NodeUpdateDownloading(:final int received, :final int total):
        return _Activity(
          key: const ValueKey<String>('node_update_activity_download'),
          text: l10n.nodeUpdateProgressLabel(
            _megabytes(received),
            _megabytes(total),
          ),
          fraction: total > 0 ? (received / total).clamp(0, 1).toDouble() : 0,
          onCancel: cubit.cancelDownload,
        );
      case NodeUpdateReadingFile(:final String name):
        return _Activity(
          key: const ValueKey<String>('node_update_activity_file'),
          text: l10n.nodeUpdateReadingFileLabel(name),
        );
      case NodeUpdateStaging():
        return _Activity(
          key: const ValueKey<String>('node_update_activity_staging'),
          text: l10n.nodeUpdateStagingLabel,
        );
      case NodeUpdateStepFailed(:final NodeUpdateException error):
        return Padding(
          key: const ValueKey<String>('node_update_activity_failed'),
          padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: _ProblemText(error),
          ),
        );
    }
  }
}

/// Something under way: a bar, a line about it, and Cancel when it can be
/// stopped. Without a fraction the bar runs without an end.
class _Activity extends StatelessWidget {
  const _Activity({
    required this._text,
    this._fraction,
    this._onCancel,
    super.key,
  });

  final String _text;
  final double? _fraction;
  final VoidCallback? _onCancel;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? onCancel = _onCancel;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                RepaintBoundary(child: _buildBar(context)),
                const SizedBox(height: 6),
                Text(
                  _text,
                  textDirection: ltrUnlessRtl(_text),
                  textAlign: ltrTextAlign(context),
                  style: settingMonoStyle(context),
                ),
              ],
            ),
          ),
          if (onCancel != null) ...<Widget>[
            const SizedBox(width: 12),
            OutlinedButton(
              key: const ValueKey<String>('node_update_cancel'),
              style: cardSecondaryButtonStyle(context),
              onPressed: onCancel,
              child: Text(context.l10n.cancel),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBar(BuildContext context) {
    final Color ink = AppTokens.of(context).znnInk;
    final Color track = cardLineColor(context);
    final double? fraction = _fraction;
    if (fraction == null) {
      return LinearProgressIndicator(
        minHeight: 4,
        color: ink,
        backgroundColor: track,
        borderRadius: BorderRadius.circular(2),
      );
    }
    // The bar glides to each new figure instead of jumping to it.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: fraction),
      duration: Durations.short4,
      curve: Easing.standard,
      builder: (BuildContext context, double value, Widget? child) =>
          LinearProgressIndicator(
            value: value,
            minHeight: 4,
            color: ink,
            backgroundColor: track,
            borderRadius: BorderRadius.circular(2),
          ),
    );
  }
}

/// Back to the bundled library, or to the override installed before.
class _RollbackRow extends StatelessWidget {
  const _RollbackRow();

  /// Whether there is anything to go back from, or to.
  static bool offered(NodeLibraryStatus? status) =>
      status != null &&
      (status.installed != null ||
          status.staged != null ||
          status.previous != null);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return BlocBuilder<NodeUpdateCubit, NodeUpdatePanelState>(
      buildWhen: (NodeUpdatePanelState before, NodeUpdatePanelState now) =>
          before.library != now.library || before.idle != now.idle,
      builder: (BuildContext context, NodeUpdatePanelState state) {
        final NodeLibraryStatus? status = state.library;
        if (status == null) {
          return const SizedBox.shrink();
        }
        final NodeLibraryManifest? previous = status.previous;
        final bool overridden =
            status.installed != null || status.staged != null;
        return SettingRow(
          label: l10n.nodeUpdateRollbackLabel,
          hint: l10n.nodeUpdateRollbackHint,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (previous != null)
                OutlinedButton(
                  key: const ValueKey<String>('node_update_use_previous'),
                  style: cardSecondaryButtonStyle(context),
                  onPressed: state.idle
                      ? () => unawaited(_onUsePrevious(context, previous))
                      : null,
                  child: Text(l10n.nodeUpdateUsePreviousLabel),
                ),
              if (previous != null && overridden) const SizedBox(width: 8),
              if (overridden)
                OutlinedButton(
                  key: const ValueKey<String>('node_update_use_bundled'),
                  style: cardSecondaryButtonStyle(context),
                  onPressed: state.idle
                      ? () => unawaited(_onUseBundled(context, status))
                      : null,
                  child: Text(l10n.nodeUpdateUseBundledLabel),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _onUseBundled(
    BuildContext context,
    NodeLibraryStatus status,
  ) async {
    final NodeUpdateCubit cubit = context.read<NodeUpdateCubit>();
    if (await _showUseBundledDialog(context, status) ?? false) {
      await cubit.useBundled();
    }
  }

  Future<void> _onUsePrevious(
    BuildContext context,
    NodeLibraryManifest previous,
  ) async {
    final NodeUpdateCubit cubit = context.read<NodeUpdateCubit>();
    if (await _showUsePreviousDialog(context, previous) ?? false) {
      await cubit.usePrevious();
    }
  }
}

/// The repository the next Check reads.
class _SourceRow extends StatefulWidget {
  const _SourceRow();

  @override
  State<_SourceRow> createState() => _SourceRowState();
}

class _SourceRowState extends State<_SourceRow> {
  late final TextEditingController _controller = TextEditingController(
    text: context.read<NodeUpdateCubit>().state.repository,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    final String typed = _controller.text.trim();
    if (await context.read<NodeUpdateCubit>().setRepository(typed) && mounted) {
      // What was saved, without the blanks typed around it.
      _controller.text = typed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return BlocBuilder<NodeUpdateCubit, NodeUpdatePanelState>(
      buildWhen: (NodeUpdatePanelState before, NodeUpdatePanelState now) =>
          before.repository != now.repository || before.idle != now.idle,
      builder: (BuildContext context, NodeUpdatePanelState state) {
        final String typed = _controller.text.trim();
        final bool valid = NodeUpdateSource.isValid(typed);
        final bool savable = state.idle && valid && typed != state.repository;
        return SettingRow(
          label: l10n.nodeUpdateSourceLabel,
          hint: l10n.nodeUpdateSourceHint,
          below: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      key: const ValueKey<String>('node_update_repository'),
                      controller: _controller,
                      enabled: state.idle,
                      autocorrect: false,
                      enableSuggestions: false,
                      // A repository name reads left to right in every
                      // language; the error line under it keeps the app's
                      // direction.
                      textDirection: TextDirection.ltr,
                      style: monoStyle(
                        Theme.of(context).textTheme.bodyMedium,
                      ),
                      onChanged: (String value) => setState(() {}),
                      onSubmitted: (String value) {
                        if (savable) {
                          unawaited(_onSave());
                        }
                      },
                      decoration: InputDecoration(
                        filled: true,
                        isDense: true,
                        contentPadding: const EdgeInsetsDirectional.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        hintText: NodeUpdateSource.defaultRepository,
                        hintTextDirection: TextDirection.ltr,
                        errorText: typed.isEmpty || valid
                            ? null
                            : l10n.nodeUpdateSourceError,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    key: const ValueKey<String>('node_update_repository_save'),
                    style: cardSecondaryButtonStyle(context),
                    onPressed: savable ? () => unawaited(_onSave()) : null,
                    child: Text(l10n.nodeUpdateSourceSaveLabel),
                  ),
                ],
              ),
              AnimatedSize(
                duration: Durations.short4,
                curve: Easing.standard,
                alignment: AlignmentDirectional.topStart,
                child: valid && typed != NodeUpdateSource.defaultRepository
                    ? _Note(
                        l10n.nodeUpdateSourceForeignHint,
                        key: const ValueKey<String>('node_update_foreign'),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        );
      },
    );
  }
}
