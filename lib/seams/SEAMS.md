# Drawn features awaiting implementation

Source discovery: `add99a2cb7128d3e754733130394b9869b708f86`.
These are missing backing implementations, rather than unfinished widgets.
The `Unbuilt…` service implementations in `missing_services.dart` always throw
`SeamNotBuilt`; they have no wallet, filesystem, network or chain dependency.
Their signatures mark the missing operations without specifying their future
request and result models.

| Value | Screen ids | File to fill in | Research brief |
| --- | --- | --- | --- |
| `swapTerms` | `swap-start` | `lib/seams/missing_services.dart`, `UnbuiltSwapTermsService.start`; future two-sided offer and acceptance coordinator beside existing HTLC actions | `docs/research/swap-terms.md` |
| `zapSend` | `home-rest`, `home-open`, `home-hidden`, `home-goto`, `send-rest`, `send-warn`, `receive`, `receive-qr`, `send-confirm`, `zap-form` | `lib/seams/missing_services.dart`, `UnbuiltZapService.send`; future coordinator under `lib/rearchitecture/features/zap/` | `docs/research/zap.md` |
| `zapReceive` | `home-rest`, `home-open`, `home-hidden`, `home-bell`, `home-zap` | `lib/seams/missing_services.dart`, `UnbuiltZapService.receive`; future receipt qualification under `lib/rearchitecture/features/zap/` and durable `ZapReceiveClaims` in `lib/rearchitecture/features/home/view/zap_sparks.dart` | `docs/research/zap.md` |
| `walletPicker` | `lock-screen`, `lock-wrong`, `lock-pick`, `set-wallet` | `lib/seams/missing_services.dart`, `UnbuiltWalletPickerService.open`; `lib/widgets/tab_children_widgets/lock_wallet_picker.dart` draws the current field and gated external-entry menu; production remains closed until wallet catalog, switching and Add wallet exist beside `lib/utils/wallet_utils.dart` | `docs/research/wallet-selection-and-modes.md` |
| `passwordRecovery` | `lock-screen`, `lock-wrong` | `lib/seams/missing_services.dart`, `UnbuiltPasswordRecoveryService.recover`; future owned recovery route beside the lock screen | `docs/research/password-recovery.md` |
| `passwordChangeMigration` | `set-security` | `lib/seams/missing_services.dart`, `UnbuiltPasswordChangeMigrationService.change`; owned wallet-password and recovery-store migration beside the password route | `docs/research/password-change-migration.md` |
| `operatorModes` | `home-rest`, `home-open`, `home-hidden`, `pillars`, `pillar-mine`, `sentinels`, `set-node`, `set-wallet` | `lib/seams/missing_services.dart`, `UnbuiltOperatorModesService.apply`; future policy under `lib/rearchitecture/features/user_modes/` | `docs/research/wallet-selection-and-modes.md` |
| `walletUpdateNotice` | `home-rest`, `lock-screen`, `set-about` | `lib/seams/missing_services.dart`, `UnbuiltWalletUpdateNoticeService.check`; disabled slot in `lib/widgets/shell/strip/update_slot.dart` and About | `docs/research/update-detection.md` |
| `biometricUnlock` | `set-security` | `lib/seams/missing_services.dart`, `UnbuiltBiometricUnlockService.unlock`; future platform authentication behind the Security row | `docs/research/qol-ideas.md` |
| `autoLockOnClose` | `set-security` | `lib/seams/missing_services.dart`, `UnbuiltSecurityPolicyService.lockOnClose`; future close policy beside the positive inactivity timer | `docs/research/qol-ideas.md` |
| `wrongPasswordLimitOff` | `set-security` | `lib/seams/missing_services.dart`, `UnbuiltSecurityPolicyService.disableWrongPasswordLimit`; future disabled-limit policy beside the positive exhaustion limit | `docs/research/qol-ideas.md` |
| `sporks` | `set-node` | `lib/seams/missing_services.dart`, `UnbuiltSporksService.load`; future Sporks feature behind the Node group | `docs/research/extension-parity.md` |
| `pillarAprEstimate` | `pillars`, `pillar-mine` | `lib/seams/missing_services.dart`, `UnbuiltPillarAprService.load`; future qualified return model beside the Pillars list | `docs/research/qol-ideas.md` |

The update notice in `home-rest` represents the shared status strip on shell
screens. It is a wallet release notice. The embedded-node updater already
checks releases and installs libraries through its existing confirmation flow.

Wrap only the missing action in `SeamGate(seam: ..., child: ...)`. Its child
keeps its normal paint and layout; pointer, focus and semantic activation are
blocked, with a basic cursor and the localized tooltip `Not yet`. Palette
selection and shortcuts must also call `runUnlessSeamed`. A refusal returns
false without invoking their callback. Do not convert it into a success event.
The focus barrier also clears a control that was already focused when moved
inside the gate; preventing new focus requests alone leaves that control active.

`walletPicker` covers the new multi-wallet catalog, switching and Add wallet
flow. Existing single-wallet unlock, onboarding and Ledger access stay wired.
The selected address, derived address list and failed-password count are
currently global; adding a dropdown alone would mix wallet state.

`passwordRecovery` gates the drawn forgotten-password link. The existing
failed-password reset is a global exhaustion policy and cannot stand in for a
wallet recovery route. This seam does not change unlock, onboarding, the failure
counter or the existing reset policy.

`autoLockOnClose` and `wrongPasswordLimitOff` cover choices whose backing
policies do not exist. Existing positive inactivity durations and password
attempt limits remain available. A disabled segment must refuse indirect
activation as well as pointer, keyboard and semantic input.

`operatorModes` gates the new Auto / On / Off policy. Existing Pillar and
Sentinel ownership reads, registration, management and pages remain available.
`zapReceive` covers Zap interpretation and celebration; ordinary receives
remain available.

Ledger discovery, creation, unlock and signing already exist in
`lib/screens/onboarding/hardware_wallet/` and `lib/utils/wallet_file.dart`.
WalletConnect session connect approvals already exist in
`lib/services/web3wallet_service.dart`; the bell mockup asks to connect, so
moving that approval into the bell is UI wiring. WalletConnect `znn_sign`
and `znn_send` are still unimplemented; these transaction actions are not
drawn in the bell mockup and must remain refused. Existing Dapp bridge
connection, signing and send approvals also stay wired.

This foundation does not integrate page controls or register these services.
Each page task must apply the matching gate and indirect guard before adding
its drawn controls. Tests check enum coverage, screen ids, reference paths,
activation refusal, unchanged rendering and the throwing service boundaries.
