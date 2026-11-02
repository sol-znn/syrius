import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/import_wallet/import_draft.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/import_wallet/import_surface.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/new_wallet/seed_quiz.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/new_wallet/seed_quiz_surface.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/welcome_surface.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/tab_children_widgets/lock_card.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/tab_children_widgets/lock_wallet_picker.dart';

import 'capture_protocol.dart';

/// Memory-only scene selection for an independent presentation process.
class HarnessPresentationController extends ChangeNotifier {
  /// Invalid scenes and themes refuse before this owner can display them.
  HarnessPresentationController({
    String surface = 'welcome',
    String theme = 'dark',
  }) : _surface = _validateSurface(surface),
       _theme = _validateTheme(theme);

  /// These scenes require no wallet, native startup or successful initializer.
  static const List<String> surfaces = <String>[
    'welcome',
    'import',
    'seed-quiz',
    'lock-screen',
    'lock-wrong',
    'wallet-picker',
  ];

  String _surface;
  String _theme;
  bool _closed = false;

  /// The selected pure view; it is not an actual-wallet route name.
  String get surface => _surface;

  /// The requested in-memory theme, separate from observed native paint.
  String get theme => _theme;

  /// No system setting or persistent preference is changed by this host.
  ThemeMode get themeMode =>
      _theme == 'dark' ? ThemeMode.dark : ThemeMode.light;

  static String _validateSurface(String surface) {
    if (!surfaces.contains(surface)) {
      throw const CaptureRefused('presentation-surface-unavailable');
    }
    return surface;
  }

  static String _validateTheme(String theme) {
    if (theme != 'dark' && theme != 'light') {
      throw const CaptureRefused('presentation-theme-unavailable');
    }
    return theme;
  }

  void _requireOpen() {
    if (_closed) {
      throw const CaptureRefused('presentation-owner-closed');
    }
  }

  /// Changes a display fixture without constructing a production entry owner.
  void show(String surface) {
    _requireOpen();
    final String selected = _validateSurface(surface);
    if (_surface == selected) {
      return;
    }
    _surface = selected;
    notifyListeners();
  }

  /// Selects only an explicit dark or light in-memory theme.
  void setTheme(String theme) {
    _requireOpen();
    final String selected = _validateTheme(theme);
    if (_theme == selected) {
      return;
    }
    _theme = selected;
    notifyListeners();
  }

  /// Anonymous source facts, never initialization, frame or capture evidence.
  Map<String, Object?> snapshot() => Map<String, Object?>.unmodifiable(
    <String, Object?>{
      'presentation': true,
      'readOnly': true,
      'surface': _surface,
      'theme': _theme,
      'actualCapture': false,
      'walletOwnerMounted': false,
    },
  );

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}

/// Reuses production views without app.main, wallet owners or global services.
class HarnessPresentationHost extends StatefulWidget {
  /// The caller owns [controller] and must not mount a production app beneath.
  const HarnessPresentationHost({
    required this.controller,
    this.background,
    this.welcomeGlobe,
    super.key,
  });

  /// Scene and requested theme remain inside this presentation process.
  final HarnessPresentationController controller;

  /// Finite widget tests can omit shaders without replacing any view layout.
  final Widget? background;

  /// Finite widget tests can omit the original animated globe decoder.
  final Widget? welcomeGlobe;

  @override
  State<HarnessPresentationHost> createState() =>
      _HarnessPresentationHostState();
}

class _HarnessPresentationHostState extends State<HarnessPresentationHost> {
  final GlobalKey _visibilityBoundary = GlobalKey();
  final Object _welcomeSource = Object();
  final TextEditingController _import = TextEditingController();
  final TextEditingController _password = TextEditingController(
    text: 'synthetic-input',
  );
  final ImportSeedDraft _draft = ImportSeedDraft('', expectedWords: 12);
  late final SeedQuiz _quiz = SeedQuiz(
    // Deliberately invalid wallet words cannot become a usable mnemonic.
    List<String>.generate(12, (int index) => 'fixture-word-$index'),
    random: Random(7),
    isValidWord: (String _) => true,
    validateMnemonic: (List<String> _) => true,
  );

  static Never _refuse() =>
      throw const CaptureRefused('presentation-action-refused');

  @override
  void initState() {
    super.initState();
    // Focus exclusion also stops Welcome's visibility clock. This separate
    // host consumes keyboard input before focused controls or shortcuts.
    FocusManager.instance.addEarlyKeyEventHandler(_blockKeyboard);
  }

  KeyEventResult _blockKeyboard(KeyEvent event) => KeyEventResult.handled;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (BuildContext context, Widget? child) => MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: widget.controller.themeMode,
      debugShowCheckedModeBanner: false,
      locale: const Locale('en'),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (BuildContext context, Widget? child) =>
          // Original art's pinned dependencies still use SDK Material widgets.
          // ignore: deprecated_member_use
          MaterialUiCompatibilityBridge(
            child: child ?? const SizedBox.shrink(),
          ),
      home: Scaffold(
        key: const Key('harness_presentation_host'),
        body: Column(
          children: <Widget>[
            const _PresentationBanner(),
            Expanded(
              // The listener identifies this owner's visible input barrier
              // without temporarily enabling any fixture controls.
              child: Listener(
                key: _visibilityBoundary,
                child: AbsorbPointer(
                  key: const Key('harness_presentation_input_barrier'),
                  child: Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    descendantsAreTraversable: false,
                    child: ExcludeSemantics(
                      child: KeyedSubtree(
                        key: ValueKey<String>(
                          'harness_presentation_${widget.controller.surface}',
                        ),
                        child: _buildSurface(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildSurface() {
    switch (widget.controller.surface) {
      case 'welcome':
        return WelcomeSurface(
          source: _welcomeSource,
          onSelected: (WelcomeDestination _) => _refuse(),
          wrapImportDrop: (Widget child) => child,
          background: widget.background,
          globe: widget.welcomeGlobe,
        );
      case 'import':
        return ImportSurface(
          seedController: _import,
          draft: _draft,
          onSeedChanged: (String _) => _refuse(),
          onWordCountChanged: (int _) => _refuse(),
          onBrowse: _refuse,
          onBack: _refuse,
          onContinue: null,
          background: widget.background,
        );
      case 'seed-quiz':
        return SeedQuizSurface(
          quiz: _quiz,
          onSelected: (int _, String _) => _refuse(),
          onBack: _refuse,
          onContinue: null,
          background: widget.background,
        );
      case 'lock-screen':
      case 'lock-wrong':
        final bool wrong = widget.controller.surface == 'lock-wrong';
        return LockCard(
          walletName: 'Synthetic wallet',
          passwordController: _password,
          onUnlock: _refuse,
          canUnlock: false,
          incorrectPassword: wrong,
          failedAttempts: wrong ? 1 : 0,
          attemptsRemaining: wrong ? 2 : 3,
        );
      case 'wallet-picker':
        const LockWalletDisplayEntry current = LockWalletDisplayEntry(
          name: 'Synthetic wallet',
        );
        return LockWalletPicker(
          current: current,
          entries: const <LockWalletDisplayEntry>[
            current,
            LockWalletDisplayEntry(name: 'Synthetic second wallet'),
          ],
          expanded: true,
        );
      default:
        throw const CaptureRefused('presentation-surface-unavailable');
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_blockKeyboard);
    _import.dispose();
    _password.dispose();
    super.dispose();
  }
}

/// Identifies only the original host's own read-only visibility boundary.
/// It is not a renderer frame pin or actual-wallet capture receipt.
RenderObject? presentationVisibilityBoundary(BuildContext original) {
  if (original is! StatefulElement ||
      original.state is! _HarnessPresentationHostState) {
    return null;
  }
  final _HarnessPresentationHostState state =
      original.state as _HarnessPresentationHostState;
  return state._visibilityBoundary.currentContext?.findRenderObject();
}

class _PresentationBanner extends StatelessWidget {
  const _PresentationBanner();

  @override
  Widget build(BuildContext context) => Material(
    child: Padding(
      padding: AppTokens.of(context).cardPadding,
      child: const Text(
        'Synthetic presentation. Read only.',
        key: Key('harness_presentation_banner'),
      ),
    ),
  );
}
