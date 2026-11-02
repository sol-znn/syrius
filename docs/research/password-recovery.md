# Password recovery boundary

The lock mockup draws a forgotten-password link. This tree has single-wallet
unlock and onboarding, but no recovery route with an explicit selected-wallet
owner and secret-handling lifecycle.

Failed-password exhaustion enters the existing global reset flow. It does not
establish a recovery operation for only the displayed wallet. Reusing that
route would present a destructive reset as password recovery.

The link therefore uses `Seam.passwordRecovery`. The typed
`UnbuiltPasswordRecoveryService` refuses before reading a secret, touching a
wallet file, resetting preferences or navigating to a recovery result. Existing
unlock, import and exhaustion behavior remain the responsibility of their
original owners. A future implementation must define its wallet scope,
verification and cancellation behavior before this gate can be removed.
