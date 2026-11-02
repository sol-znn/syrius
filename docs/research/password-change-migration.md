# Password change and recovery-store migration

The password screen exists, but an owned operation for changing the original
wallet password and migrating its recovery stores is missing.

The wallet-file write and encrypted swap-recovery store have separate lifetimes.
Legacy close and reopen helpers can complete against a replacement global
session. Captured writer drains are now authored, but they do not establish an
atomic, recoverable password change. The retained legacy migration deletes a
store before creating its replacement, so the owned store refuses that path
before any opening or deletion. Cursor checkpoints are reproducible metadata;
private recovery and action holds belong to the original encrypted swaps store.

The redesign draws Change behind `Seam.passwordChangeMigration`. The production
route reaches the same throwing service before decryption or storage access.
Presentation fixtures may inject an owned session; they do not enable this
production capability.

Before removing the seam, implement and qualify an operation that owns the
original wallet file and recovery storage, drains original writers,
persists replacement data, verifies completion and can recover an interrupted
migration. Existing software-wallet unlock, seed reveal and Seed Vault export
remain separate available actions.
