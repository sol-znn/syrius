import '../app/readonly_native_mode.dart'
    show harnessReadonlyNativeLaunchMatches;
import '../wallet_address_context.dart';
import '../wallet_recipe_failure.dart';

/// Transport and clocks are supplied so offline recipes never need a wallet.
typedef WalletRecipeSend =
    Future<Map<String, dynamic>> Function(
      Map<String, Object?> command,
      Duration timeout,
    );

/// A safe refusal code. Private input and transport diagnostics stay private.
class WalletRecipeRefused implements Exception {
  /// Records only a fixed code, never a command or its response.
  const WalletRecipeRefused(this.code, {this.diagnostic});

  /// The stage that could not establish its required original facts.
  final String code;

  /// Fixed labels retain a refused command's stage without its private data.
  final Map<String, String>? diagnostic;

  @override
  String toString() => code;
}

/// Signing policy must be explicit before the importer sends any private input.
int walletRecipeChain(String? text) {
  final int? value = text != null && RegExp(r'^[0-9]+$').hasMatch(text)
      ? int.tryParse(text)
      : null;
  if (value == null || value <= 0) {
    throw const WalletRecipeRefused('wallet-recipe-positive-chain-required');
  }
  return value;
}

/// Matches the existing node form's bounded endpoint syntax.
bool walletRecipeNode(String text) {
  final Uri? uri = Uri.tryParse(text);
  return uri != null &&
      text == text.trim() &&
      text.length <= 80 &&
      (uri.scheme == 'ws' || uri.scheme == 'wss') &&
      uri.host.isNotEmpty &&
      uri.hasPort &&
      uri.port > 0 &&
      uri.port <= 65535 &&
      uri.userInfo.isEmpty &&
      uri.path.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment;
}

/// Drives the real keyed entry and Settings controls with finite observations.
/// A failed or uncertain command retires this driver instead of retrying it.
class WalletRecipe {
  /// Injected observations exercise ordering and late outcomes without signing.
  WalletRecipe({
    required this.send,
    Future<void> Function(Duration)? wait,
    this._elapsed,
    this.budget = const Duration(minutes: 3),
    this.commandTimeout = const Duration(seconds: 10),
  }) : _inspectionPid = null,
       _wait = wait ?? Future<void>.delayed;

  /// The inspection namespace requires its actual owned process on every reply.
  WalletRecipe.inspection({
    required this.send,
    required int expectedPid,
    Future<void> Function(Duration)? wait,
    this._elapsed,
    this.budget = const Duration(minutes: 3),
    this.commandTimeout = const Duration(seconds: 10),
  }) : _inspectionPid = expectedPid,
       _wait = wait ?? Future<void>.delayed {
    if (expectedPid <= 0) {
      throw const WalletRecipeRefused('wallet-recipe-inspection-pid-required');
    }
  }

  /// Replies retain the harness protocol's explicit success bit.
  final WalletRecipeSend send;

  /// One total deadline bounds every stage, scroll and transport operation.
  final Duration budget;

  /// A stalled command cannot consume an unbounded recipe stage.
  final Duration commandTimeout;
  final Future<void> Function(Duration) _wait;
  final Duration Function()? _elapsed;
  final int? _inspectionPid;
  final Stopwatch _clock = Stopwatch()..start();
  bool _retired = false;
  int? _owner;
  String? _expectedNode;
  int? _expectedChain;
  int? _originalSigningChain;
  String? _selectionOriginNode;
  int? _selectionOriginRevision;
  String? _policyNode;
  String? _startupHandoff;
  String? _startupFilmState;
  bool _restoredStartup = false;
  WalletAddressContext? _addressOrigin;

  Duration get _remaining => budget - (_elapsed?.call() ?? _clock.elapsed);

  Never _refuse(String code, {Map<String, String>? diagnostic}) {
    _retired = true;
    throw WalletRecipeRefused(code, diagnostic: diagnostic == null
        ? null
        : Map<String, String>.unmodifiable(<String, String>{
            ...diagnostic,
            'startup': ?_startupHandoff,
            'film': ?_startupFilmState,
          }));
  }

  Future<Map<String, dynamic>> _command(Map<String, Object?> command) async {
    if (_retired) _refuse('wallet-recipe-retired');
    final Duration remaining = _remaining;
    if (remaining <= Duration.zero) _refuse('wallet-recipe-deadline');
    final Duration limit = remaining < commandTimeout
        ? remaining
        : commandTimeout;
    try {
      final Map<String, dynamic> reply = await send(
        <String, Object?>{
          'cmd': _inspectionPid == null ? 'wallet-recipe' : 'readonly-entry',
          ...command,
        },
        limit,
      ).timeout(limit);
      if (reply['ok'] != true) {
        _refuse(
          'wallet-recipe-command-refused',
          diagnostic: walletRecipeDiagnostic(command, reply['error']),
        );
      }
      if (_inspectionPid != null &&
          !harnessReadonlyNativeLaunchMatches(reply, _inspectionPid)) {
        _refuse('wallet-recipe-inspection-owner-changed');
      }
      if (command['action'] != 'observe' && reply['acted'] != true) {
        _refuse('wallet-recipe-action-unconfirmed');
      }
      return reply;
    } on WalletRecipeRefused {
      rethrow;
    } on Object {
      // The original command may still settle. No follow-up is admitted.
      _refuse('wallet-recipe-command-uncertain');
    }
  }

  Future<void> _tick() async {
    if (_remaining <= Duration.zero) _refuse('wallet-recipe-deadline');
    try {
      await _wait(const Duration(milliseconds: 150)).timeout(_remaining);
    } on Object {
      _refuse('wallet-recipe-deadline');
    }
  }

  Future<Map<String, dynamic>> _observe() async {
    final Map<String, dynamic> value = await _command(<String, Object?>{
      'action': 'observe',
      if (_expectedNode != null) 'expectedNode': _expectedNode,
      if (_expectedChain != null) 'expectedNodeChain': _expectedChain,
      if (_originalSigningChain != null)
        'originalSigningChain': _originalSigningChain,
    });
    if (value['harnessMode'] !=
            (_inspectionPid == null ? 'wallet' : 'readonly-native') ||
        value['booted'] != true ||
        value['controls'] is! List ||
        value['owner'] is! int ||
        value['revision'] is! int ||
        value['hasError'] != false ||
        (value.containsKey('startupFilmState') &&
            !walletRecipeStartupFilmStates.contains(
              value['startupFilmState'],
            )) ||
        (_owner != null && value['owner'] != _owner) ||
        (_policyNode != null && value['node'] != _policyNode)) {
      _refuse('wallet-recipe-observation-refused');
    }
    _startupFilmState = value['startupFilmState'] as String?;
    return value;
  }

  Map<String, dynamic>? _control(Map<String, dynamic> view, String key) {
    final List<dynamic> all = view['controls'] as List<dynamic>;
    if (all.any((dynamic value) => value is! Map<String, dynamic>)) {
      _refuse('wallet-recipe-controls-unavailable');
    }
    final List<Map<String, dynamic>> matches = all
        .cast<Map<String, dynamic>>()
        .where((Map<String, dynamic> value) => value['key'] == key)
        .toList();
    if (matches.length > 1) _refuse('wallet-recipe-control-ambiguous');
    return matches.isEmpty ? null : matches.single;
  }

  Future<Map<String, dynamic>> _until(
    bool Function(Map<String, dynamic>) ready, {
    int turns = 200,
    String? waitingFor,
  }) async {
    Map<String, dynamic>? last;
    for (int turn = 0; turn < turns; turn++) {
      final Map<String, dynamic> value = await _observe();
      last = value;
      if (ready(value)) return value;
      await _tick();
    }
    String reason = 'wallet-recipe-stage-unsettled';
    if (waitingFor != null && last != null) {
      final Map<String, dynamic>? control = _control(last, waitingFor);
      if (control == null) {
        reason = 'wallet-recipe-control-absent';
      } else if (control['enabled'] == false) {
        reason = waitingFor == 'settings_add_address' &&
                control['blockedBy'] == 'widget'
            ? walletRecipeAddressFailure(control['inputGate'])
            : walletRecipeControlFailure(control['blockedBy']);
      }
    }
    _refuse(
      'wallet-recipe-stage-unsettled',
      diagnostic: walletRecipeDiagnostic(<String, Object?>{
        'action': 'observe', 'key': waitingFor,
      }, reason, entryPhase: last?['entryPhase']),
    );
  }

  Future<Map<String, dynamic>> _visible(
    String key, {
    bool reveal = false,
  }) async {
    if (!reveal) {
      return _until(
        (Map<String, dynamic> view) {
          final bool enabled = _control(view, key)?['enabled'] == true;
          if (key != 'launch_skip_hint') return enabled;
          if (_restoredStartup && view['tab'] == 'lock' &&
              view['startupFilmState'] == null &&
              !(view['entryPhase'] as String? ?? '').startsWith('startup')) {
            return true;
          }
          return view['entryPhase'] == 'startup-before-initialization' &&
                  enabled ||
              <String>{
                'startup-initialization-started', 'welcome',
              }.contains(view['entryPhase']);
        },
        waitingFor: key,
      );
    }
    for (final int direction in <int>[-300, 300]) {
      for (int turn = 0; turn < 20; turn++) {
        final Map<String, dynamic> view = await _observe();
        if (_control(view, key)?['enabled'] == true) return view;
        if (view['transitionPending'] != false || view['question'] != null) {
          _refuse('wallet-recipe-scroll-refused');
        }
        await _command(<String, Object?>{
          'action': 'scroll',
          'owner': view['owner'],
          'revision': view['revision'],
          'dy': direction,
        });
      }
    }
    _refuse('wallet-recipe-control-unavailable');
  }

  Future<void> _act(
    String key, {
    String? value,
    bool reveal = false,
    int? question,
  }) async {
    final Map<String, dynamic> view = await _visible(key, reveal: reveal);
    if (key == 'launch_skip_hint' &&
        view['entryPhase'] != 'startup-before-initialization') {
      _startupHandoff = view['entryPhase'] == 'welcome'
          ? 'natural-welcome'
          : 'natural-initialization';
      return;
    }
    if (_originalSigningChain != null &&
        view['signingChainId'] != _originalSigningChain) {
      _refuse('wallet-recipe-original-signing-policy-changed');
    }
    final WalletAddressContext? addressOrigin = _addressOrigin;
    if (addressOrigin != null &&
        !addressOrigin.same(_addressContext(view))) {
      _refuse('wallet-recipe-original-address-context-changed');
    }
    if (key == 'launch_skip_hint') _startupHandoff = 'key-sent';
    await _command(<String, Object?>{
      'action': key == 'launch_skip_hint'
          ? 'key'
          : value == null ? 'tap' : 'type',
      'key': key,
      'owner': view['owner'],
      'revision': view['revision'],
      'value': ?value,
      'question': ?question,
      if (addressOrigin != null) 'addressContext': addressOrigin.toJson(),
      if (_expectedNode != null) 'expectedNode': _expectedNode,
      if (_expectedChain != null) 'expectedNodeChain': _expectedChain,
      if (_originalSigningChain != null)
        'originalSigningChain': _originalSigningChain,
      if (_selectionOriginRevision != null) ...<String, Object?>{
        'originNode': _selectionOriginNode,
        'originRevision': _selectionOriginRevision,
      },
    });
    if (key == 'launch_skip_hint') _startupHandoff = 'key-confirmed';
  }

  void _policy(Map<String, dynamic> view) {
    if (view['signingPolicyReady'] != true ||
        view['signingChainId'] is! int ||
        (view['signingChainId'] as int) <= 0 ||
        view['signingChainId'] != view['savedSigningChainId']) {
      _refuse('wallet-recipe-signing-policy-unavailable');
    }
  }

  WalletAddressContext _addressContext(Map<String, dynamic> view) {
    try {
      return WalletAddressContext.parse(view['addressContext']);
    } on FormatException {
      _refuse('wallet-recipe-address-context-unavailable');
    }
  }

  /// Let the original startup film reach the copied wallet's ordinary lock.
  /// This path admits no Welcome, import, derivation or password input.
  Future<void> settleRestoredStartup() async {
    if (_inspectionPid != null) _refuse('wallet-recipe-fresh-inspection-only');
    if (_restoredStartup) _refuse('wallet-recipe-restored-lock-required');
    _restoredStartup = true;
    try {
      await _awaitRestoredLock();
    } finally {
      _restoredStartup = false;
    }
  }

  Future<void> _awaitRestoredLock() async {
    bool skipped = false;
    Map<String, dynamic>? last;
    for (int turn = 0; turn < 400; turn++) {
      final Map<String, dynamic> view = await _observe();
      last = view;
      final String phase = view['entryPhase'] as String? ?? 'unknown';
      if (view['tab'] == 'lock' && !phase.startsWith('startup') &&
          view['startupFilmState'] == null) {
        return;
      }
      if (view['entryPhase'] == 'welcome' ||
          view['entryPhase'] == 'import' || view['entryPhase'] == 'ready' ||
          view['hasError'] != false || phase.contains('error') ||
          phase.contains('refused')) {
        _refuseRestoredLock(view);
      }
      if (!skipped && view['entryPhase'] == 'startup-before-initialization' &&
          _control(view, 'launch_skip_hint')?['enabled'] == true) {
        skipped = true;
        await _act('launch_skip_hint');
      } else {
        await _tick();
      }
    }
    _refuseRestoredLock(last);
  }

  Never _refuseRestoredLock(Map<String, dynamic>? view) => _refuse(
    'wallet-recipe-restored-lock-required',
    diagnostic: walletRecipeDiagnostic(
      <String, Object?>{'action': 'observe'},
      view?['hasError'] == true
          ? 'wallet-recipe-visible-error'
          : 'wallet-recipe-refused',
      entryPhase: view?['entryPhase'],
    ),
  );

  /// P09 preparation uses only the original Settings controls on chain 321.
  /// One missing index is derived once; uncertain writes retire this driver.
  Future<Map<String, Object>> selectLabAddress() async {
    final Map<String, dynamic> start = await _observe();
    _policy(start);
    if (start['walletPresent'] != true ||
        start['walletInitCompleted'] != true ||
        start['node'] != 'ws://127.0.0.1:45998' ||
        start['chainId'] != 321 || start['signingChainId'] != 321 ||
        start['nodeConnected'] != true ||
        start['nodeSelectionSaved'] != true ||
        start['transitionPending'] != false) {
      _refuse('wallet-recipe-owned-lab-required');
    }
    _owner = start['owner'] as int;
    _policyNode = start['node'] as String;
    _originalSigningChain = 321;
    WalletAddressContext origin = _addressContext(start);
    if (!origin.consistent) {
      _refuse('wallet-recipe-address-selection-unsettled');
    }
    _addressOrigin = origin;
    bool generated = false;
    if (origin.members.length < 2 || origin.selected != origin.members[1]) {
      if (start['tab'] != 'settings') {
        await _act('nav_settings');
        await _until((Map<String, dynamic> view) => view['tab'] == 'settings');
      }
      if ((await _observe())['addressesReady'] != true) {
        await _act('settings_addresses');
      }
      await _until(
        (Map<String, dynamic> view) => view['addressesReady'] == true,
      );
      if (origin.members.length == 1) {
        await _act('settings_add_address');
        generated = true;
        final Map<String, dynamic> extended = await _until(
          (Map<String, dynamic> view) {
            if (view['addressContext'] == null) return false;
            final WalletAddressContext current = _addressContext(view);
            if (current.same(origin)) return false;
            if (!current.derivedFrom(origin)) {
              _refuse('wallet-recipe-original-address-context-changed');
            }
            return view['addressesReady'] == true;
          },
        );
        origin = _addressContext(extended);
        _addressOrigin = origin;
      }
      await _act('addresses_select_${origin.members[1]}', reveal: true);
      final Map<String, dynamic> selected = await _until(
        (Map<String, dynamic> view) {
          if (view['addressContext'] == null) return false;
          final WalletAddressContext current = _addressContext(view);
          if (!current.selectionPending(origin, 1)) {
            _refuse('wallet-recipe-original-address-context-changed');
          }
          return current.selectedFrom(origin, 1) &&
              view['addressesReady'] == true;
        },
      );
      _addressOrigin = _addressContext(selected);
    }
    final Map<String, dynamic> finalView = await _observe();
    final WalletAddressContext finalContext = _addressContext(finalView);
    _policy(finalView);
    if (!finalContext.same(_addressOrigin!) || !finalContext.consistent ||
        finalContext.members.length < 2 ||
        finalContext.selected != finalContext.members[1] ||
        finalView['chainId'] != 321 || finalView['signingChainId'] != 321 ||
        finalView['nodeConnected'] != true ||
        finalView['nodeSelectionSaved'] != true ||
        finalView['transitionPending'] != false) {
      _refuse('wallet-recipe-address-selection-unsettled');
    }
    return <String, Object>{
      'index': 1, 'members': finalContext.members.length,
      'generated': generated,
      'selected': true, 'persisted': true,
    };
  }

  /// Append index two once through Settings, retaining the committed index one.
  Future<WalletAddressContext> prepareSeedAddress(
    WalletAddressContext original,
  ) async {
    if (_inspectionPid != null) _refuse('wallet-recipe-fresh-inspection-only');
    final Map<String, dynamic> start = await _observe();
    _policy(start);
    if (!original.same(_addressContext(start)) || !original.consistent ||
        original.members.length != 2 ||
        original.selected != original.members[1] ||
        start['walletPresent'] != true ||
        start['walletInitCompleted'] != true ||
        start['node'] != 'ws://127.0.0.1:45998' ||
        start['chainId'] != 321 || start['signingChainId'] != 321 ||
        start['nodeConnected'] != true ||
        start['nodeSelectionSaved'] != true ||
        start['transitionPending'] != false) {
      _refuse('wallet-recipe-owned-seed-lab-required');
    }
    _owner = start['owner'] as int;
    _policyNode = start['node'] as String;
    _originalSigningChain = 321;
    _addressOrigin = original;
    if (start['tab'] != 'settings') {
      await _act('nav_settings');
      await _until((Map<String, dynamic> view) => view['tab'] == 'settings');
    }
    if ((await _observe())['addressesReady'] != true) {
      await _act('settings_addresses');
    }
    await _until((Map<String, dynamic> view) => view['addressesReady'] == true);
    await _act('settings_add_address');
    final Map<String, dynamic> extended = await _until(
      (Map<String, dynamic> view) {
        final WalletAddressContext now = _addressContext(view);
        if (now.same(original)) return false;
        if (!now.derivedFrom(original)) {
          _refuse('wallet-recipe-original-address-context-changed');
        }
        return view['addressesReady'] == true;
      },
    );
    final WalletAddressContext result = _addressContext(extended);
    _addressOrigin = result;
    _policy(extended);
    if (extended['chainId'] != 321 ||
        extended['signingChainId'] != 321 ||
        extended['nodeConnected'] != true ||
        extended['nodeSelectionSaved'] != true ||
        extended['transitionPending'] != false) {
      _refuse('wallet-recipe-owned-seed-lab-required');
    }
    return result;
  }

  /// Imports once, opens the original Ready once, then commits signing policy.
  Future<void> importWallet({
    required String? chain,
    required String? mnemonic,
    required String? password,
    String? node,
  }) async {
    final int requested = walletRecipeChain(chain);
    if (_inspectionPid != null &&
        (requested != 321 || node != 'ws://127.0.0.1:45998')) {
      _refuse('wallet-recipe-owned-lab-required');
    }
    final List<String> words = (mnemonic ?? '').trim().split(RegExp(r'\s+'));
    if ((words.length != 12 && words.length != 24) ||
        password == null ||
        password.isEmpty ||
        password.length > 512 ||
        words.join(' ').length > 512 ||
        (node != null && !walletRecipeNode(node))) {
      _refuse('wallet-recipe-import-input-refused');
    }
    final Map<String, dynamic> start = await _observe();
    _policy(start);
    if (start['walletPresent'] != false ||
        start['transitionPending'] != false) {
      _refuse('wallet-recipe-empty-profile-required');
    }
    // The first observation may precede the original startup receipt. Wait
    // for its authenticated hint or a natural handoff before Welcome.
    _startupHandoff = 'observing';
    await _act('launch_skip_hint');
    await _act('welcome_import');
    await _act('import_words_${words.length}');
    await _act('import_seed_field', value: words.join(' '));
    await _act('import_continue');
    await _act('import_new_password', value: password);
    await _act('import_confirm_password', value: password);
    await _act('import_password_continue');
    final Map<String, dynamic> picker = await _until(
      (Map<String, dynamic> view) =>
          view['nodePicker'] == true || view['readyOriginal'] == true,
      turns: 400,
      waitingFor: 'node_settings_add',
    );
    if (picker['nodePicker'] != true ||
        picker['walletPresent'] != true ||
        picker['walletInitCompleted'] != true) {
      _refuse('wallet-recipe-original-node-picker-required');
    }
    final Object? target = node ?? picker['node'];
    if (target is! String || !walletRecipeNode(target)) {
      _refuse('wallet-recipe-explicit-node-required');
    }
    await selectNode(target, onboarding: true, expectedChain: requested);
    await _act('wallet_ready_open');
    await _until(
      (Map<String, dynamic> view) =>
          view['tab'] == 'dashboard' &&
          view['walletInitCompleted'] == true &&
          view['transitionPending'] == false &&
          view['readyOriginal'] == false,
      waitingFor: 'nav_dashboard',
    );
    await changeClientChain(requested);
    await _act('nav_dashboard');
    await _until(
      (Map<String, dynamic> view) =>
          view['tab'] == 'dashboard' &&
          view['node'] == target &&
          view['chainId'] == requested &&
          view['signingChainId'] == requested &&
          view['savedSigningChainId'] == requested &&
          view['transitionPending'] == false,
      waitingFor: 'nav_dashboard',
    );
  }

  /// Selection admits one genuine mismatch only for an explicit expected chain.
  Future<void> selectNode(
    String node, {
    bool onboarding = false,
    int? expectedChain,
  }) async {
    if (_inspectionPid != null &&
        (node != 'ws://127.0.0.1:45998' || expectedChain != 321)) {
      _refuse('wallet-recipe-owned-lab-required');
    }
    if (!walletRecipeNode(node) ||
        (expectedChain != null && expectedChain <= 0)) {
      _refuse('wallet-recipe-node-input-refused');
    }
    final Map<String, dynamic> origin = await _until(
      (Map<String, dynamic> view) => view['nodePicker'] == true,
      waitingFor: 'node_settings_add',
    );
    _policy(origin);
    if (origin['transitionPending'] != false || origin['nodeBusy'] != false) {
      _refuse('wallet-recipe-node-owner-unavailable');
    }
    _owner = origin['owner'] as int;
    _expectedNode = node;
    _expectedChain = expectedChain;
    _originalSigningChain = origin['signingChainId'] as int;
    _selectionOriginNode = origin['node'] as String?;
    _selectionOriginRevision = origin['revision'] as int;
    if (origin['nodeCatalog'] is! List) {
      _refuse('wallet-recipe-node-catalog-unavailable');
    }
    if (!(origin['nodeCatalog'] as List<dynamic>).contains(node)) {
      await _act('node_settings_add', reveal: true);
      await _act('node_settings_endpoint', value: node, reveal: true);
      await _act('node_settings_endpoint_save', reveal: true);
      await _until(
        (Map<String, dynamic> view) =>
            (view['nodeCatalog'] as List<dynamic>?)?.contains(node) == true,
        waitingFor: 'node_settings_endpoint_save',
      );
    }
    if (origin['node'] == node && !onboarding) {
      if (origin['nodeConnected'] != true ||
          origin['nodeSelectionSaved'] != true ||
          origin['chainId'] is! int ||
          (origin['chainId'] as int) <= 0 ||
          (expectedChain != null && origin['chainId'] != expectedChain)) {
        _refuse('wallet-recipe-original-node-unverified');
      }
      return;
    }
    await _act(
      origin['node'] == node
          ? 'node_onboarding_continue'
          : 'node_settings_select_$node',
      reveal: true,
    );
    bool accepted = false;
    for (int turn = 0; turn < 400; turn++) {
      final Map<String, dynamic> view = await _observe();
      _policy(view);
      if (view['signingChainId'] != _originalSigningChain) {
        _refuse('wallet-recipe-original-signing-policy-changed');
      }
      final Object? question = view['question'];
      if (question != null) {
        if (accepted || expectedChain == null || question is! int) {
          _refuse('wallet-recipe-mismatch-refused');
        }
        accepted = true;
        await _act('node_settings_question_accept', question: question);
      } else if (view['node'] == node &&
          view['nodeConnected'] == true &&
          view['nodeSelectionSaved'] == true &&
          view['transitionPending'] == false &&
          view['nodeBusy'] == false &&
          view['chainId'] is int &&
          (view['chainId'] as int) > 0 &&
          (expectedChain == null || view['chainId'] == expectedChain) &&
          (!onboarding || view['readyOriginal'] == true)) {
        return;
      }
      await _tick();
    }
    _refuse('wallet-recipe-node-unsettled');
  }

  /// Verifies SDK policy and the saved preference after using the real control.
  Future<void> changeClientChain(int chain) async {
    if (_inspectionPid != null && chain != 321) {
      _refuse('wallet-recipe-owned-lab-required');
    }
    if (chain <= 0) _refuse('wallet-recipe-positive-chain-required');
    final Map<String, dynamic> origin = await _observe();
    _policy(origin);
    if (origin['walletPresent'] != true ||
        origin['walletInitCompleted'] != true ||
        origin['transitionPending'] != false ||
        origin['nodeConnected'] != true ||
        origin['nodeSelectionSaved'] != true ||
        origin['node'] is! String) {
      _refuse('wallet-recipe-unlocked-owner-required');
    }
    _owner = origin['owner'] as int;
    final String node = origin['node'] as String;
    _policyNode = node;
    _originalSigningChain = origin['signingChainId'] as int;
    if (origin['signingChainId'] == chain) return;
    if (origin['tab'] != 'settings') {
      await _act('nav_settings');
      await _until(
        (Map<String, dynamic> view) => view['tab'] == 'settings',
        waitingFor: 'settings_node',
      );
    }
    final Map<String, dynamic> settings = await _observe();
    if (settings['nodePicker'] != true) await _act('settings_node');
    final Map<String, dynamic> header = await _visible(
      'node_settings_chain_toggle',
      reveal: true,
    );
    final Object? expanded = _control(
      header,
      'node_settings_chain_toggle',
    )?['expanded'];
    if (expanded is! bool) _refuse('wallet-recipe-chain-form-unavailable');
    if (!expanded) await _act('node_settings_chain_toggle');
    await _act('node_settings_client_chain', value: '$chain', reveal: true);
    await _act('node_settings_chain_save', reveal: true);
    await _until(
      (Map<String, dynamic> view) {
        if (view['node'] != node) {
          _refuse('wallet-recipe-original-node-changed');
        }
        return view['signingPolicyReady'] == true &&
            view['signingChainId'] == chain &&
            view['savedSigningChainId'] == chain &&
            view['nodeConnected'] == true &&
            view['nodeSelectionSaved'] == true &&
            view['transitionPending'] == false &&
            view['nodeBusy'] == false;
      },
      waitingFor: 'node_settings_chain_save',
    );
    _originalSigningChain = chain;
  }
}
